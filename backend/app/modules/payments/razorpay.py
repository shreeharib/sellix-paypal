"""Razorpay REST API: Payment Links (create, look up, cancel), payments, refunds, signatures.

Each shop connects its own Razorpay account (payments/accounts.py), so every call takes the
credentials to use and the money settles straight into that shop's account. Amounts are in the
currency's smallest unit (paise for rupees), as Razorpay expects.

Facts this module relies on (Razorpay docs, read 24 Nov 2026):
- `expire_by` must be at least 15 minutes in the future (else 400).
- `reference_id` is at most 40 characters and must be unique per Payment Link.
- Unknown request fields are refused ("extra fields sent"), so only documented fields are sent.
- The callback signature is HMAC-SHA256 (key secret) of
  `link_id|reference_id|status|payment_id`; webhooks are HMAC-SHA256 (webhook secret) of the raw
  body, in the `X-Razorpay-Signature` header.
- Refunds are idempotent with the `X-Refund-Idempotency` header (10+ characters).
"""

import asyncio
import hashlib
import hmac
import re
from collections.abc import Mapping
from dataclasses import dataclass, field
from typing import Any, Literal

import httpx2

from app.core.config import get_settings

DEFAULT_API_BASE = "https://api.razorpay.com"
TIMEOUT_SECONDS = 20
# Currencies offered. Razorpay takes others only once international payments are activated on
# the merchant's account, which we can't see; rupee shops are the product's market.
SUPPORTED_CURRENCIES = frozenset({"INR"})
# Razorpay refuses an expire_by closer than 15 minutes; one more minute covers clock skew.
MIN_LINK_LIFETIME_SECONDS = 16 * 60
SIGNATURE_HEADER = "x-razorpay-signature"
EVENT_ID_HEADER = "x-razorpay-event-id"

Mode = Literal["test", "live"]
_KEY_ID = re.compile(r"^rzp_(test|live)_[A-Za-z0-9]{6,40}$")
_RETRY_DELAYS = (0.5, 1.5)  # seconds before the 2nd and 3rd try of a safe request

# Tests route every call through a fake Razorpay (httpx2.MockTransport); None: the network.
_transport: httpx2.AsyncBaseTransport | None = None


def use_transport(transport: httpx2.AsyncBaseTransport | None) -> None:
    """Send every Razorpay call through `transport` (tests); None restores the network."""
    global _transport
    _transport = transport


@dataclass(frozen=True)
class Credentials:
    key_id: str
    key_secret: str = field(repr=False)

    @property
    def mode(self) -> Mode | None:
        return mode_of(self.key_id)


class RazorpayError(RuntimeError):
    """Razorpay refused a call or couldn't be reached (`status` 0)."""

    def __init__(
        self,
        status: int,
        description: str,
        *,
        code: str = "",
        reason: str | None = None,
        field: str | None = None,
    ) -> None:
        super().__init__(f"Razorpay error {status}: {description}")
        self.status = status
        self.code = code
        self.description = description
        self.reason = reason
        self.field = field

    @property
    def retryable(self) -> bool:
        """A network failure, a rate limit or a server error: trying again later may work."""
        return self.status in (0, 408, 409, 429) or self.status >= 500

    @property
    def bad_keys(self) -> bool:
        """Razorpay didn't accept the key id and secret."""
        text = self.description.lower()
        return self.status == 401 or "api key" in text or "authentication" in text


@dataclass(frozen=True)
class LinkPayment:
    """A captured payment listed on a Payment Link."""

    payment_id: str
    amount_minor: int
    method: str | None
    status: str


@dataclass(frozen=True)
class Link:
    id: str
    short_url: str
    status: str  # created | partially_paid | paid | cancelled | expired
    amount_minor: int
    amount_paid_minor: int
    currency: str
    reference_id: str
    order_id: str  # Razorpay's own order behind the link ("" until Razorpay makes one)
    notes: Mapping[str, str]
    payments: tuple[LinkPayment, ...]

    @property
    def captured_payment(self) -> LinkPayment | None:
        captured = [p for p in self.payments if p.status == "captured"]
        return captured[-1] if captured else None


@dataclass(frozen=True)
class PaymentInfo:
    id: str
    status: str  # created | authorized | captured | refunded | failed
    amount_minor: int
    currency: str
    method: str | None
    fee_minor: int
    order_id: str
    notes: Mapping[str, str]
    error_description: str | None


@dataclass(frozen=True)
class RefundInfo:
    id: str
    status: str  # pending | processed | failed
    amount_minor: int
    currency: str
    payment_id: str
    receipt: str


def mode_of(key_id: str) -> Mode | None:
    """`test` or `live` from the key id's prefix; None if it isn't a Razorpay key id."""
    match = _KEY_ID.match(key_id.strip())
    if match is None:
        return None
    return "test" if match.group(1) == "test" else "live"


def looks_like_key_id(key_id: str) -> bool:
    return mode_of(key_id) is not None


def looks_like_key_secret(key_secret: str) -> bool:
    secret = key_secret.strip()
    return 12 <= len(secret) <= 64 and secret.isalnum()


async def create_link(
    credentials: Credentials,
    *,
    amount_minor: int,
    currency: str,
    reference_id: str,
    description: str,
    expire_by: int,
    callback_url: str,
    notes: Mapping[str, str],
) -> Link:
    """Create a Payment Link the customer pays at `short_url`.

    Never retried here: a second try with the same `reference_id` is refused by Razorpay, and
    one with a new reference could make two links. The caller asks again with a new reference.
    """
    body: dict[str, Any] = {
        "amount": amount_minor,
        "currency": currency,
        "accept_partial": False,
        "reference_id": reference_id[:40],
        "description": description[:2048],
        "expire_by": expire_by,
        "notify": {"sms": False, "email": False},
        "reminder_enable": False,
        "notes": {key: str(value)[:255] for key, value in list(notes.items())[:15]},
        "callback_url": callback_url,
        "callback_method": "get",
    }
    return _link(await _request(credentials, "POST", "/v1/payment_links/", json=body, retry=False))


async def fetch_link(credentials: Credentials, link_id: str) -> Link:
    return _link(await _request(credentials, "GET", f"/v1/payment_links/{link_id}"))


async def cancel_link(credentials: Credentials, link_id: str) -> Link:
    """Stop a link taking payments. Razorpay refuses (400) once it is paid, expired or cancelled."""
    return _link(await _request(credentials, "POST", f"/v1/payment_links/{link_id}/cancel"))


async def fetch_payment(credentials: Credentials, payment_id: str) -> PaymentInfo:
    data = await _request(credentials, "GET", f"/v1/payments/{payment_id}")
    return payment_info(data)


async def create_refund(
    credentials: Credentials,
    payment_id: str,
    *,
    amount_minor: int,
    idempotency_key: str,
    notes: Mapping[str, str] | None = None,
) -> RefundInfo:
    """Refund a captured payment. The same `idempotency_key` (also sent as the receipt) never
    refunds twice, so this is safe to retry."""
    body: dict[str, Any] = {
        "amount": amount_minor,
        "speed": "normal",
        "receipt": idempotency_key[:40],
    }
    if notes:
        body["notes"] = {key: str(value)[:255] for key, value in list(notes.items())[:15]}
    data = await _request(
        credentials,
        "POST",
        f"/v1/payments/{payment_id}/refund",
        json=body,
        headers={"X-Refund-Idempotency": idempotency_key},
    )
    return refund_info(data)


async def fetch_refund(credentials: Credentials, refund_id: str) -> RefundInfo:
    return refund_info(await _request(credentials, "GET", f"/v1/refunds/{refund_id}"))


async def payment_refunds(credentials: Credentials, payment_id: str) -> list[RefundInfo]:
    """Every refund of a payment (to find one whose answer never reached us, by its receipt)."""
    data = await _request(credentials, "GET", f"/v1/payments/{payment_id}/refunds")
    return [refund_info(item) for item in data.get("items") or []]


async def check_keys(credentials: Credentials) -> None:
    """Raise RazorpayError unless Razorpay accepts these keys (a cheap authenticated read)."""
    await _request(credentials, "GET", "/v1/payments", params={"count": 1})


def webhook_signature(body: bytes, secret: str) -> str:
    return hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()


def verify_webhook(body: bytes, signature: str, secret: str) -> bool:
    """A webhook delivery is genuine when its signature is the HMAC of the raw body."""
    if not signature or not secret:
        return False
    return hmac.compare_digest(webhook_signature(body, secret), signature.strip())


def callback_signature(
    *, link_id: str, reference_id: str, status: str, payment_id: str, key_secret: str
) -> str:
    message = "|".join((link_id, reference_id, status, payment_id))
    return hmac.new(key_secret.encode(), message.encode(), hashlib.sha256).hexdigest()


def verify_callback(
    *,
    link_id: str,
    reference_id: str,
    status: str,
    payment_id: str,
    signature: str,
    key_secret: str,
) -> bool:
    """The redirect after payment is genuine when its signature matches (checked with the key
    secret, unlike webhooks)."""
    if not signature:
        return False
    expected = callback_signature(
        link_id=link_id,
        reference_id=reference_id,
        status=status,
        payment_id=payment_id,
        key_secret=key_secret,
    )
    return hmac.compare_digest(expected, signature.strip())


def payment_info(data: Mapping[str, Any]) -> PaymentInfo:
    return PaymentInfo(
        id=str(data.get("id", "")),
        status=str(data.get("status", "")),
        amount_minor=int(data.get("amount") or 0),
        currency=str(data.get("currency", "")),
        method=str(data["method"]) if data.get("method") else None,
        fee_minor=int(data.get("fee") or 0),
        order_id=str(data.get("order_id") or ""),
        notes=_notes(data.get("notes")),
        error_description=str(data["error_description"]) if data.get("error_description") else None,
    )


def refund_info(data: Mapping[str, Any]) -> RefundInfo:
    return RefundInfo(
        id=str(data.get("id", "")),
        status=str(data.get("status", "")),
        amount_minor=int(data.get("amount") or 0),
        currency=str(data.get("currency", "")),
        payment_id=str(data.get("payment_id", "")),
        receipt=str(data.get("receipt") or ""),
    )


def link_from(data: Mapping[str, Any]) -> Link:
    return _link(data)


def _link(data: Mapping[str, Any]) -> Link:
    payments = tuple(
        LinkPayment(
            payment_id=str(item.get("payment_id", "")),
            amount_minor=int(item.get("amount") or 0),
            method=str(item["method"]) if item.get("method") else None,
            status=str(item.get("status", "")),
        )
        for item in data.get("payments") or []
        if isinstance(item, Mapping)
    )
    return Link(
        id=str(data.get("id", "")),
        short_url=str(data.get("short_url", "")),
        status=str(data.get("status", "")),
        amount_minor=int(data.get("amount") or 0),
        amount_paid_minor=int(data.get("amount_paid") or 0),
        currency=str(data.get("currency", "")),
        reference_id=str(data.get("reference_id") or ""),
        order_id=str(data.get("order_id") or ""),
        notes=_notes(data.get("notes")),
        payments=payments,
    )


def _notes(value: object) -> dict[str, str]:
    # Razorpay sends an empty list, not an object, when there are no notes.
    if isinstance(value, Mapping):
        return {str(key): str(item) for key, item in value.items()}
    return {}


def _api_base() -> str:
    return (get_settings().razorpay_api_base or DEFAULT_API_BASE).rstrip("/")


async def _request(
    credentials: Credentials,
    method: str,
    path: str,
    *,
    json: Mapping[str, Any] | None = None,
    params: Mapping[str, Any] | None = None,
    headers: Mapping[str, str] | None = None,
    retry: bool = True,
) -> dict[str, Any]:
    delays = _RETRY_DELAYS if retry else ()
    attempt = 0
    while True:
        try:
            return await _send(credentials, method, path, json=json, params=params, headers=headers)
        except RazorpayError as exc:
            if not exc.retryable or attempt >= len(delays):
                raise
            await asyncio.sleep(delays[attempt])
            attempt += 1


async def _send(
    credentials: Credentials,
    method: str,
    path: str,
    *,
    json: Mapping[str, Any] | None,
    params: Mapping[str, Any] | None,
    headers: Mapping[str, str] | None,
) -> dict[str, Any]:
    if not credentials.key_id or not credentials.key_secret:
        raise RazorpayError(0, "Razorpay keys are missing")
    try:
        async with httpx2.AsyncClient(
            base_url=_api_base(), timeout=TIMEOUT_SECONDS, transport=_transport
        ) as client:
            response = await client.request(
                method,
                path,
                json=json,
                params=params,
                headers=dict(headers or {}),
                auth=(credentials.key_id, credentials.key_secret),
            )
    except httpx2.HTTPError as exc:
        raise RazorpayError(0, f"network error: {exc.__class__.__name__}") from exc
    try:
        body: Any = response.json()
    except ValueError:
        body = {}
    if not isinstance(body, dict):
        body = {}
    if response.is_error:
        error: Mapping[str, Any] = body.get("error") or {}
        raise RazorpayError(
            response.status_code,
            str(error.get("description") or response.text[:300] or "request failed"),
            code=str(error.get("code") or ""),
            reason=str(error["reason"]) if error.get("reason") else None,
            field=str(error["field"]) if error.get("field") else None,
        )
    return body
