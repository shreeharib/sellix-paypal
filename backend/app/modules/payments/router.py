"""Pages PayPal sends the buyer back to after approving or cancelling a payment."""

import uuid
from html import escape
from typing import Annotated

import structlog
from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import HTMLResponse

from app.core.money import format_money
from app.modules.conversations import service as conversations
from app.modules.payments import service, simulator
from app.webhooks import simulator as simulator_webhook

router = APIRouter(prefix="/payments/paypal", tags=["payments"])
simulator_router = APIRouter(prefix="/payments/simulator", tags=["payments"])
log = structlog.get_logger()


@router.get("/return", response_class=HTMLResponse)
async def paypal_return(token: Annotated[str | None, Query()] = None) -> HTMLResponse:
    """`token` is the PayPal order ID. Capturing here is a shortcut: PayPal's webhooks
    confirm the payment too, so a buyer who closes the page is still covered."""
    if not token:
        return _page("Payment", "Something went wrong. Please go back to the chat.", 400)
    try:
        result = await service.capture(token)
    except service.PayPalError as exc:
        log.error("payments.capture_failed", paypal_order_id=token, error=str(exc))
        return _page(
            "Payment processing",
            "We're confirming your payment. You'll get a message in the chat shortly.",
            200,
        )
    if result is not None:
        await conversations.after_payment(result)
    if isinstance(result, service.PaymentFailed):
        return _page(
            "Payment not completed",
            "PayPal couldn't complete the payment. Please go back to the chat and try again.",
            200,
        )
    return _page(
        "Thank you!",
        "Your payment is being confirmed. You'll get a message in the chat. "
        "You can close this page.",
        200,
    )


@router.get("/cancel", response_class=HTMLResponse)
async def paypal_cancel() -> HTMLResponse:
    return _page(
        "Payment cancelled",
        "No payment was taken. Go back to the chat if you'd like to pay or change your order.",
        200,
    )


@simulator_router.get("/{payment_id}", response_class=HTMLResponse)
async def simulator_checkout(payment_id: uuid.UUID) -> HTMLResponse:
    """The simulator's stand-in for PayPal's page: Accept payment or Reject payment."""
    return await _simulator_page(payment_id)


@simulator_router.post("/{payment_id}/accept", response_class=HTMLResponse)
async def simulator_accept(payment_id: uuid.UUID) -> HTMLResponse:
    return await _simulator_decide(payment_id, "accepted")


@simulator_router.post("/{payment_id}/reject", response_class=HTMLResponse)
async def simulator_reject(payment_id: uuid.UUID) -> HTMLResponse:
    return await _simulator_decide(payment_id, "rejected")


async def _simulator_page(payment_id: uuid.UUID) -> HTMLResponse:
    if not simulator.enabled():
        raise HTTPException(status_code=404, detail="Not found")
    view = await service.simulated_checkout(payment_id)
    if view is None:
        return HTMLResponse(simulator.missing_page(), status_code=404)
    return HTMLResponse(
        simulator.checkout_page(
            payment_id=view.payment_id,
            shop_name=view.shop_name,
            order_number=view.order_number,
            amount=format_money(view.amount_minor, view.currency),
            status=view.status,
        )
    )


async def _simulator_decide(payment_id: uuid.UUID, decision: simulator.Decision) -> HTMLResponse:
    """A button press becomes a signed webhook delivery, exactly as a real provider would send."""
    if not simulator.enabled():
        raise HTTPException(status_code=404, detail="Not found")
    view = await service.simulated_checkout(payment_id)
    if view is None:
        return HTMLResponse(simulator.missing_page(), status_code=404)
    if view.status == "created":
        body = simulator.event_body(
            decision,
            payment_id=view.payment_id,
            amount_minor=view.amount_minor,
            currency=view.currency,
        )
        await simulator_webhook.deliver(body, simulator.sign(body))
    return HTMLResponse(simulator.result_page(decision))


def _page(title: str, message: str, status_code: int) -> HTMLResponse:
    html = (
        "<!doctype html><html lang='en'><head><meta charset='utf-8'>"
        "<meta name='viewport' content='width=device-width, initial-scale=1'>"
        f"<title>{escape(title)}</title>"
        "<style>body{font-family:system-ui,sans-serif;max-width:32rem;margin:4rem auto;"
        "padding:0 1rem;line-height:1.5}</style></head>"
        f"<body><h1>{escape(title)}</h1><p>{escape(message)}</p></body></html>"
    )
    return HTMLResponse(html, status_code=status_code)
