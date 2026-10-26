"""PayPal REST API: OAuth, Orders v2 (create, capture, look up) and webhook verification."""

import time
from collections.abc import Mapping
from dataclasses import dataclass
from decimal import Decimal
from typing import Any

import httpx2

from app.core.config import get_settings

API_BASE = {"sandbox": "https://api-m.sandbox.paypal.com", "live": "https://api-m.paypal.com"}
# Currencies with two decimal places that PayPal accepts for cross-border payments. INR is
# missing on purpose: PayPal only allows it between Indian accounts.
SUPPORTED_CURRENCIES = frozenset({"USD", "EUR", "GBP", "AUD", "CAD", "SGD", "NZD"})
TIMEOUT_SECONDS = 20
_TOKEN_MARGIN_SECONDS = 120

_token_cache: dict[str, tuple[str, float]] = {}  # client ID -> (token, expires at)


class PayPalError(RuntimeError):
    def __init__(self, status: int, message: str, issue: str | None = None) -> None:
        super().__init__(f"PayPal error {status}: {message}")
        self.status = status
        self.issue = issue


@dataclass(frozen=True)
class CreatedOrder:
    paypal_order_id: str
    approve_url: str


@dataclass(frozen=True)
class CreatedInvoice:
    invoice_id: str
    payer_view_url: str


@dataclass(frozen=True)
class Capture:
    status: str  # COMPLETED, PENDING, DECLINED, FAILED
    capture_id: str
    amount_minor: int
    currency: str


@dataclass(frozen=True)
class RefundResult:
    refund_id: str
    status: str
    amount_minor: int
    currency: str


def configured() -> bool:
    settings = get_settings()
    return bool(settings.paypal_client_id and settings.paypal_client_secret)


def to_amount(minor: int) -> str:
    return f"{Decimal(minor) / 100:.2f}"


def to_minor(amount: str) -> int:
    return int((Decimal(amount) * 100).to_integral_value())


async def create_order(
    *,
    reference_id: str,
    description: str,
    amount_minor: int,
    currency: str,
    brand_name: str,
    return_url: str,
    cancel_url: str,
) -> CreatedOrder:
    """Create a PayPal order the buyer approves at the returned link."""
    data = await _request(
        "POST",
        "/v2/checkout/orders",
        # Same order, same request ID: a retry returns the existing PayPal order.
        request_id=f"sellix-order-{reference_id}",
        json={
            "intent": "CAPTURE",
            "purchase_units": [
                {
                    "reference_id": reference_id,
                    "custom_id": reference_id,
                    "description": description[:127],
                    "amount": {"currency_code": currency, "value": to_amount(amount_minor)},
                }
            ],
            "payment_source": {
                "paypal": {
                    "experience_context": {
                        "brand_name": brand_name[:127],
                        "user_action": "PAY_NOW",
                        "shipping_preference": "NO_SHIPPING",
                        "landing_page": "GUEST_CHECKOUT",
                        "return_url": return_url,
                        "cancel_url": cancel_url,
                    }
                }
            },
        },
    )
    links = {link.get("rel"): link.get("href") for link in data.get("links", [])}
    approve_url = links.get("payer-action") or links.get("approve")
    if not approve_url:
        raise PayPalError(200, "PayPal returned no approval link")
    return CreatedOrder(paypal_order_id=data["id"], approve_url=approve_url)


async def capture_order(paypal_order_id: str) -> Capture | None:
    """Capture an approved order. None if the buyer hasn't approved it yet."""
    try:
        data = await _request(
            "POST",
            f"/v2/checkout/orders/{paypal_order_id}/capture",
            request_id=f"sellix-capture-{paypal_order_id}",
            json={},
        )
    except PayPalError as exc:
        if exc.issue == "ORDER_ALREADY_CAPTURED":
            data = await _request("GET", f"/v2/checkout/orders/{paypal_order_id}")
        elif exc.issue in ("ORDER_NOT_APPROVED", "PAYER_ACTION_REQUIRED"):
            return None
        else:
            raise
    return capture_from_order(data)


def capture_from_order(order: Mapping[str, Any]) -> Capture | None:
    captures = order.get("purchase_units", [{}])[0].get("payments", {}).get("captures", [])
    return capture_from_resource(captures[0]) if captures else None


def capture_from_resource(capture: Mapping[str, Any]) -> Capture:
    amount = capture.get("amount", {})
    return Capture(
        status=str(capture.get("status", "")),
        capture_id=str(capture.get("id", "")),
        amount_minor=to_minor(str(amount.get("value", "0"))),
        currency=str(amount.get("currency_code", "")),
    )


async def create_invoice(
    *,
    reference_id: str,
    invoice_number: str | None = None,
    description: str,
    items: list[dict[str, Any]] | None = None,
    total_minor: int,
    currency: str,
    brand_name: str,
    customer_name: str | None = None,
    customer_email: str | None = None,
) -> str:
    """Create a draft invoice in PayPal for the full order amount. Returns invoice ID."""
    invoice_items: list[dict[str, Any]] = []
    if items:
        for item in items:
            unit_price = int(item.get("unit_price_minor", 0))
            qty = int(item.get("quantity", 1))
            invoice_items.append(
                {
                    "name": str(item.get("name") or description)[:300],
                    "quantity": str(qty),
                    "unit_amount": {
                        "currency_code": currency,
                        "value": to_amount(unit_price),
                    },
                    "unit_of_measure": "QUANTITY",
                }
            )
    if not invoice_items:
        invoice_items.append(
            {
                "name": description[:300],
                "quantity": "1",
                "unit_amount": {
                    "currency_code": currency,
                    "value": to_amount(total_minor),
                },
                "unit_of_measure": "QUANTITY",
            }
        )

    recipient_info: dict[str, Any] = {
        "email_address": customer_email or f"customer-{reference_id[:8]}@sellix.local"
    }
    if customer_name:
        recipient_info["name"] = {"given_name": customer_name[:140]}

    payload: dict[str, Any] = {
        "detail": {
            "currency_code": currency,
            "reference": reference_id[:60],
            "note": f"Thank you for ordering with {brand_name}!",
            "payment_term": {"term_type": "DUE_ON_RECEIPT"},
        },
        "invoicer": {
            "business_name": brand_name[:300],
        },
        "primary_recipients": [{"billing_info": recipient_info}],
        "items": invoice_items,
        "amount": {
            "currency_code": currency,
            "value": to_amount(total_minor),
            "breakdown": {
                "item_total": {
                    "currency_code": currency,
                    "value": to_amount(total_minor),
                }
            },
        },
    }
    if invoice_number:
        payload["detail"]["invoice_number"] = invoice_number

    data = await _request(
        "POST",
        "/v2/invoicing/invoices",
        request_id=f"sellix-invoice-{reference_id}",
        json=payload,
    )
    return str(data["id"])


async def send_invoice(invoice_id: str) -> str:
    """Activate an invoice without emailing the recipient. Returns payer_view_url."""
    data = await _request(
        "POST",
        f"/v2/invoicing/invoices/{invoice_id}/send",
        request_id=f"sellix-send-{invoice_id}",
        json={"send_to_recipient": False, "send_to_invoicer": False},
    )
    links = {link.get("rel"): link.get("href") for link in data.get("links", [])}
    payer_view = links.get("payer-view")
    if not payer_view:
        invoice_data = await _request("GET", f"/v2/invoicing/invoices/{invoice_id}")
        metadata = invoice_data.get("detail", {}).get("metadata", {})
        payer_view = metadata.get("payer_view_url")
    if not payer_view:
        raise PayPalError(200, "PayPal returned no payer view link for invoice")
    return payer_view


async def refund_capture(
    capture_id: str,
    *,
    amount_minor: int | None = None,
    currency: str | None = None,
    note: str | None = None,
) -> RefundResult:
    """Refund a captured payment. Full refund if amount_minor is None."""
    payload: dict[str, Any] = {}
    if amount_minor is not None and currency is not None:
        payload["amount"] = {"value": to_amount(amount_minor), "currency_code": currency}
    if note:
        payload["note_to_payer"] = note[:255]
    data = await _request(
        "POST",
        f"/v2/payments/captures/{capture_id}/refund",
        request_id=f"sellix-refund-{capture_id}",
        json=payload,
    )
    amt = data.get("amount", {})
    return RefundResult(
        refund_id=str(data.get("id", "")),
        status=str(data.get("status", "")),
        amount_minor=to_minor(str(amt.get("value", "0"))),
        currency=str(amt.get("currency_code", "")),
    )


async def verify_webhook(*, headers: Mapping[str, str], event: Mapping[str, Any]) -> bool:
    """Ask PayPal whether a webhook delivery is genuine."""
    webhook_id = get_settings().paypal_webhook_id
    if not webhook_id:
        return False
    required = {
        "auth_algo": "paypal-auth-algo",
        "cert_url": "paypal-cert-url",
        "transmission_id": "paypal-transmission-id",
        "transmission_sig": "paypal-transmission-sig",
        "transmission_time": "paypal-transmission-time",
    }
    lowered = {key.lower(): value for key, value in headers.items()}
    if any(header not in lowered for header in required.values()):
        return False
    data = await _request(
        "POST",
        "/v1/notifications/verify-webhook-signature",
        json={
            **{field: lowered[header] for field, header in required.items()},
            "webhook_id": webhook_id,
            "webhook_event": event,
        },
    )
    return data.get("verification_status") == "SUCCESS"


def _client() -> httpx2.AsyncClient:
    return httpx2.AsyncClient(base_url=API_BASE[get_settings().paypal_env], timeout=TIMEOUT_SECONDS)


async def _access_token(client: httpx2.AsyncClient) -> str:
    settings = get_settings()
    cached = _token_cache.get(settings.paypal_client_id)
    if cached and cached[1] > time.monotonic():
        return cached[0]
    response = await client.post(
        "/v1/oauth2/token",
        auth=(settings.paypal_client_id, settings.paypal_client_secret),
        data={"grant_type": "client_credentials"},
    )
    if response.is_error:
        raise PayPalError(response.status_code, "authentication failed")
    body = response.json()
    expires_at = time.monotonic() + int(body.get("expires_in", 0)) - _TOKEN_MARGIN_SECONDS
    _token_cache[settings.paypal_client_id] = (body["access_token"], expires_at)
    return body["access_token"]


async def _request(
    method: str,
    path: str,
    *,
    json: Mapping[str, Any] | None = None,
    request_id: str | None = None,
) -> dict[str, Any]:
    if not configured():
        raise PayPalError(0, "PayPal isn't configured")
    try:
        async with _client() as client:
            headers = {"Authorization": f"Bearer {await _access_token(client)}"}
            if request_id:
                headers["PayPal-Request-Id"] = request_id
            response = await client.request(method, path, json=json, headers=headers)
    except httpx2.HTTPError as exc:
        raise PayPalError(0, f"network error: {exc.__class__.__name__}") from exc
    try:
        body: dict[str, Any] = response.json()
    except ValueError:
        body = {}
    if response.is_error:
        details = body.get("details") or [{}]
        raise PayPalError(
            response.status_code,
            str(body.get("message") or response.text[:300]),
            issue=details[0].get("issue"),
        )
    return body
