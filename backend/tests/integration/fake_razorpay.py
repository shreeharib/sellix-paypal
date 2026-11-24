"""A fake Razorpay: its HTTP API (Payment Links, payments, refunds) on an httpx2 MockTransport.

The real client (app/modules/payments/razorpay.py) talks to it, so tests cover the requests we
send (auth, bodies, headers) and how we read Razorpay's answers. It follows the documented rules
that matter to us: expire_by at least 15 minutes ahead, unique reference ids of at most 40
characters, no undocumented fields, cancelling only an unpaid link, refunds idempotent by the
X-Refund-Idempotency header and the receipt.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import itertools
import json
import time
from dataclasses import dataclass, field
from typing import Any

import httpx2

_LINK_FIELDS = {
    "amount",
    "currency",
    "accept_partial",
    "first_min_partial_amount",
    "upi_link",
    "expire_by",
    "reference_id",
    "description",
    "customer",
    "notify",
    "reminder_enable",
    "notes",
    "callback_url",
    "callback_method",
}


def _error(status: int, description: str, code: str = "BAD_REQUEST_ERROR") -> httpx2.Response:
    return httpx2.Response(
        status,
        json={
            "error": {
                "code": code,
                "description": description,
                "source": "business",
                "step": "payment_initiation",
                "reason": "input_validation_failed",
                "metadata": {},
            }
        },
    )


@dataclass
class FakeRazorpay:
    accounts: dict[str, str] = field(default_factory=dict)  # key id -> key secret
    links: dict[str, dict[str, Any]] = field(default_factory=dict)
    payments: dict[str, dict[str, Any]] = field(default_factory=dict)
    refunds: dict[str, dict[str, Any]] = field(default_factory=dict)
    requests: list[tuple[str, str, str, dict[str, Any]]] = field(default_factory=list)
    # Queued answers for the next calls: (status, description), returned instead of the real one.
    fail_next: list[tuple[int, str]] = field(default_factory=list)
    refund_status: str = "processed"  # what a new refund starts as
    _ids: itertools.count[int] = field(default_factory=lambda: itertools.count(1))
    _idempotency: dict[str, str] = field(default_factory=dict)  # key -> refund id
    _references: set[str] = field(default_factory=set)

    # -- set-up ---------------------------------------------------------------------------------

    def add_account(self, key_id: str, key_secret: str) -> None:
        self.accounts[key_id] = key_secret

    def transport(self) -> httpx2.MockTransport:
        return httpx2.MockTransport(self._handle)

    # -- what a customer does on Razorpay's page --------------------------------------------------

    def pay(self, link_id: str, *, method: str = "upi", fee: int = 236) -> str:
        """The customer pays the link in full; returns the payment id."""
        link = self.links[link_id]
        payment_id = f"pay_{next(self._ids):014d}"
        self.payments[payment_id] = {
            "id": payment_id,
            "entity": "payment",
            "amount": link["amount"],
            "currency": link["currency"],
            "status": "captured",
            "captured": True,
            "order_id": link["order_id"],
            "method": method,
            "fee": fee,
            "tax": 36,
            "notes": dict(link["notes"]),
            "error_description": None,
            "created_at": int(time.time()),
        }
        link["status"] = "paid"
        link["amount_paid"] = link["amount"]
        link["payments"] = [
            {
                "payment_id": payment_id,
                "amount": link["amount"],
                "method": method,
                "status": "captured",
                "created_at": int(time.time()),
            }
        ]
        return payment_id

    def fail_attempt(self, link_id: str, *, method: str = "upi") -> dict[str, Any]:
        """A try that fails (the link stays open); returns the payment entity."""
        link = self.links[link_id]
        payment_id = f"pay_{next(self._ids):014d}"
        entity = {
            "id": payment_id,
            "entity": "payment",
            "amount": link["amount"],
            "currency": link["currency"],
            "status": "failed",
            "captured": False,
            "order_id": link["order_id"],
            "method": method,
            "notes": dict(link["notes"]),
            "error_code": "BAD_REQUEST_ERROR",
            "error_description": "Payment was declined by the bank",
            "error_source": "bank",
            "error_step": "payment_authorization",
            "error_reason": "payment_failed",
        }
        self.payments[payment_id] = entity
        return entity

    def expire(self, link_id: str) -> None:
        self.links[link_id]["status"] = "expired"

    def only_link(self) -> dict[str, Any]:
        assert len(self.links) == 1, f"{len(self.links)} links"
        return next(iter(self.links.values()))

    # -- what Razorpay sends ----------------------------------------------------------------------

    def event(self, name: str, **entities: dict[str, Any]) -> dict[str, Any]:
        return {
            "entity": "event",
            "account_id": "acc_TEST",
            "event": name,
            "contains": list(entities),
            "payload": {key: {"entity": value} for key, value in entities.items()},
            "created_at": int(time.time()),
        }

    @staticmethod
    def sign(body: bytes, secret: str) -> str:
        return hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()

    @staticmethod
    def callback_query(link: dict[str, Any], payment_id: str, key_secret: str) -> dict[str, str]:
        """The query Razorpay puts on callback_url after a payment, signed with the key secret."""
        fields = (link["id"], link["reference_id"], link["status"], payment_id)
        signature = hmac.new(
            key_secret.encode(), "|".join(fields).encode(), hashlib.sha256
        ).hexdigest()
        return {
            "razorpay_payment_id": payment_id,
            "razorpay_payment_link_id": link["id"],
            "razorpay_payment_link_reference_id": link["reference_id"],
            "razorpay_payment_link_status": link["status"],
            "razorpay_signature": signature,
        }

    # -- the HTTP API -----------------------------------------------------------------------------

    def _handle(self, request: httpx2.Request) -> httpx2.Response:
        key_id = self._authenticate(request)
        if key_id is None:
            return _error(401, "The api key provided is invalid")
        body: dict[str, Any] = json.loads(request.content) if request.content else {}
        path = request.url.path.rstrip("/")
        self.requests.append((request.method, path, key_id, body))
        if self.fail_next:
            status, description = self.fail_next.pop(0)
            return _error(
                status, description, "SERVER_ERROR" if status >= 500 else "BAD_REQUEST_ERROR"
            )
        parts = path.strip("/").split("/")  # v1, resource, id, action
        method = request.method
        if method == "GET" and parts == ["v1", "payments"]:
            return httpx2.Response(200, json={"entity": "collection", "count": 0, "items": []})
        if parts[:2] == ["v1", "payment_links"]:
            if method == "POST" and len(parts) == 2:
                return self._create_link(body, key_id)
            link = self.links.get(parts[2]) if len(parts) > 2 else None
            if link is None or link["_account"] != key_id:
                return _error(400, "The id provided does not exist")
            if method == "GET" and len(parts) == 3:
                return httpx2.Response(200, json=self._public(link))
            if method == "POST" and parts[3:] == ["cancel"]:
                if link["status"] in ("paid", "partially_paid"):
                    return _error(
                        400, "cannot cancel or expire an already paid/partially paid link"
                    )
                if link["status"] in ("expired", "cancelled"):
                    return _error(400, "cannot cancel or expire an expired link")
                link["status"] = "cancelled"
                link["cancelled_at"] = int(time.time())
                return httpx2.Response(200, json=self._public(link))
        if parts[:2] == ["v1", "payments"] and len(parts) >= 3:
            payment = self.payments.get(parts[2])
            if payment is None:
                return _error(400, "The id provided does not exist")
            if method == "GET" and len(parts) == 3:
                return httpx2.Response(200, json=payment)
            if method == "POST" and parts[3:] == ["refund"]:
                return self._refund(payment, body, request.headers.get("x-refund-idempotency"))
            if method == "GET" and parts[3:] == ["refunds"]:
                items = [r for r in self.refunds.values() if r["payment_id"] == payment["id"]]
                return httpx2.Response(200, json={"entity": "collection", "items": items})
        if parts[:2] == ["v1", "refunds"] and len(parts) == 3 and method == "GET":
            refund = self.refunds.get(parts[2])
            if refund is None:
                return _error(400, "The id provided does not exist")
            return httpx2.Response(200, json=refund)
        return _error(404, "The requested URL was not found on the server.")

    def _authenticate(self, request: httpx2.Request) -> str | None:
        scheme, _, value = request.headers.get("authorization", "").partition(" ")
        if scheme.lower() != "basic":
            return None
        key_id, _, secret = base64.b64decode(value).decode().partition(":")
        return key_id if self.accounts.get(key_id) == secret and secret else None

    def _create_link(self, body: dict[str, Any], key_id: str) -> httpx2.Response:
        extra = set(body) - _LINK_FIELDS
        if extra:
            return _error(
                400, f"{', '.join(sorted(extra))} is/are not required and should not be sent"
            )
        amount = body.get("amount")
        if not isinstance(amount, int) or amount < 100:
            return _error(400, "The amount must be atleast INR 1.00")
        if body.get("expire_by") is not None and body["expire_by"] < time.time() + 15 * 60:
            return _error(400, "timestamp must be atleast 15 minutes in future")
        reference = str(body.get("reference_id") or "")
        if len(reference) > 40:
            return _error(400, "The reference id may not be greater than 40 characters.")
        if reference in self._references:
            return _error(400, "payment link creation with reference ID already attempted")
        if body.get("callback_url") and body.get("callback_method") != "get":
            return _error(400, "callback_method must be get")
        notes = body.get("notes") or {}
        if len(notes) > 15 or any(len(str(v)) > 255 for v in notes.values()):
            return _error(400, "notes is too long")
        self._references.add(reference)
        number = next(self._ids)
        link = {
            "id": f"plink_{number:014d}",
            "short_url": f"https://rzp.io/rzp/{number:06d}",
            "status": "created",
            "amount": amount,
            "amount_paid": 0,
            "currency": body.get("currency", "INR"),
            "accept_partial": body.get("accept_partial", False),
            "reference_id": reference,
            "description": body.get("description", ""),
            "expire_by": body.get("expire_by"),
            "callback_url": body.get("callback_url"),
            "callback_method": body.get("callback_method"),
            "notes": notes if notes else [],
            "payments": None,
            "order_id": f"order_{number:014d}",
            "created_at": int(time.time()),
            "_account": key_id,
        }
        self.links[link["id"]] = link
        created = self._public(link)
        created.pop("order_id")  # Razorpay's create answer has no order id; fetch does
        return httpx2.Response(200, json=created)

    def _refund(
        self, payment: dict[str, Any], body: dict[str, Any], idempotency: str | None
    ) -> httpx2.Response:
        if idempotency and idempotency in self._idempotency:
            return httpx2.Response(200, json=self.refunds[self._idempotency[idempotency]])
        receipt = body.get("receipt")
        if receipt and any(
            r["receipt"] == receipt and r["payment_id"] == payment["id"]
            for r in self.refunds.values()
        ):
            return _error(400, "Duplicate receipt found for this refund request.")
        amount = body.get("amount", payment["amount"])
        refunded = sum(
            r["amount"] for r in self.refunds.values() if r["payment_id"] == payment["id"]
        )
        if amount + refunded > payment["amount"]:
            return _error(400, "The refund amount provided is greater than amount captured")
        refund_id = f"rfnd_{next(self._ids):014d}"
        self.refunds[refund_id] = {
            "id": refund_id,
            "entity": "refund",
            "amount": amount,
            "currency": payment["currency"],
            "payment_id": payment["id"],
            "notes": body.get("notes") or [],
            "receipt": receipt,
            "status": self.refund_status,
            "speed_requested": body.get("speed", "normal"),
            "created_at": int(time.time()),
        }
        if idempotency:
            self._idempotency[idempotency] = refund_id
        return httpx2.Response(200, json=self.refunds[refund_id])

    @staticmethod
    def _public(link: dict[str, Any]) -> dict[str, Any]:
        return {key: value for key, value in link.items() if not key.startswith("_")}
