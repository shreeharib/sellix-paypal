"""A payment provider for demos and tests: a hosted checkout page with Accept and Reject buttons.

It stands where PayPal stands. The customer gets a link to a page here instead of PayPal's, and
the buttons send a signed webhook to /webhooks/simulator. That webhook is stored in the same
inbox and applied by a job, like PayPal's, so everything behind it (order paid, payment
declined, a new link, the order cancelled) is the real order flow. It takes no card or login.

Never offered in production.
"""

import hashlib
import hmac
import json
import uuid
from html import escape
from typing import Literal

from app.core.config import get_settings

SOURCE = "simulator"
PROVIDER = "simulator"
ACCEPTED = "SIMULATOR.PAYMENT.ACCEPTED"
REJECTED = "SIMULATOR.PAYMENT.REJECTED"
SIGNATURE_HEADER = "x-simulator-signature"

Decision = Literal["accepted", "rejected"]


def enabled() -> bool:
    settings = get_settings()
    return settings.payment_provider == "simulator" and settings.app_env != "prod"


def _key() -> bytes:
    # Derived from the app's own signing key, so there is no extra secret to set or leak.
    base = (get_settings().session_signing_key or "sellix-dev-simulator").encode()
    return hashlib.sha256(b"payment-simulator:" + base).digest()


def sign(body: bytes) -> str:
    return hmac.new(_key(), body, hashlib.sha256).hexdigest()


def verify(body: bytes, signature: str) -> bool:
    return hmac.compare_digest(sign(body), signature)


def event_body(
    decision: Decision, *, payment_id: uuid.UUID, amount_minor: int, currency: str
) -> bytes:
    """The webhook payload for one button press. A fresh event id each time: pressing the button
    again is a new delivery, and the payment itself decides whether it still counts."""
    event = {
        "source": SOURCE,
        "event_id": str(uuid.uuid4()),
        "event_type": ACCEPTED if decision == "accepted" else REJECTED,
        "resource": {
            "payment_id": str(payment_id),
            "amount_minor": amount_minor,
            "currency": currency,
        },
    }
    return json.dumps(event, sort_keys=True).encode()


_STYLE = (
    "body{font-family:system-ui,sans-serif;max-width:26rem;margin:2.5rem auto;padding:0 1rem;"
    "line-height:1.5;color:#1a1a1a}.tag{display:inline-block;background:#fff3cd;color:#664d03;"
    "border-radius:.4rem;padding:.15rem .5rem;font-size:.8rem}.amount{font-size:2.2rem;"
    "font-weight:700;margin:.2rem 0 1rem}form{display:inline}"
    "button{font-size:1rem;padding:.7rem 1.2rem;"
    "border:0;border-radius:.6rem;cursor:pointer;margin-right:.5rem}.ok{background:#198754;"
    "color:#fff}.no{background:#dc3545;color:#fff}.note{color:#555;font-size:.9rem}"
)


def _page(title: str, body: str) -> str:
    return (
        "<!doctype html><html lang='en'><head><meta charset='utf-8'>"
        "<meta name='viewport' content='width=device-width, initial-scale=1'>"
        f"<title>{escape(title)}</title><style>{_STYLE}</style></head><body>"
        f"<p class='tag'>Payment simulator: no real money</p>{body}</body></html>"
    )


def checkout_page(
    *, payment_id: uuid.UUID, shop_name: str, order_number: int, amount: str, status: str
) -> str:
    head = f"<h1>{escape(shop_name)}</h1><p>Order #{order_number}</p>"
    head += f"<div class='amount'>{escape(amount)}</div>"
    if status != "created":
        shown = {"completed": "paid", "denied": "declined"}.get(status, status)
        return _page(
            "Payment",
            head + f"<p>This payment is already <b>{escape(shown)}</b>. Go back to the chat.</p>",
        )
    base = f"/payments/simulator/{payment_id}"
    return _page(
        "Payment",
        head
        + "<p>Choose what the customer's bank would answer:</p>"
        + f"<form method='post' action='{base}/accept'>"
        + "<button class='ok'>Accept payment</button></form>"
        + f"<form method='post' action='{base}/reject'>"
        + "<button class='no'>Reject payment</button></form>"
        + "<p class='note'>Either button sends a webhook to the shop's server, which then places "
        "the order, or offers a new link.</p>",
    )


def result_page(decision: Decision) -> str:
    if decision == "accepted":
        message = "<h1>Payment accepted</h1><p>The shop has been told. Go back to the chat.</p>"
    else:
        message = (
            "<h1>Payment rejected</h1><p>The shop has been told. Go back to the chat: "
            "you can ask for a new link there.</p>"
        )
    return _page("Payment", message)


def missing_page() -> str:
    return _page("Payment", "<h1>Payment not found</h1><p>Go back to the chat.</p>")
