"""The page Razorpay sends the customer back to after paying, and the simulator's pages."""

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

router = APIRouter(prefix="/payments/razorpay", tags=["payments"])
simulator_router = APIRouter(prefix="/payments/simulator", tags=["payments"])
log = structlog.get_logger()


@router.get("/return", response_class=HTMLResponse)
async def razorpay_return(
    razorpay_payment_id: Annotated[str, Query()] = "",
    razorpay_payment_link_id: Annotated[str, Query()] = "",
    razorpay_payment_link_reference_id: Annotated[str, Query()] = "",
    razorpay_payment_link_status: Annotated[str, Query()] = "",
    razorpay_signature: Annotated[str, Query()] = "",
) -> HTMLResponse:
    """Razorpay's redirect after a payment. Confirming here is a shortcut: the webhook and the
    settle job confirm it too, so a customer who closes the page is still covered."""
    if not razorpay_payment_link_id:
        return _page("Payment", "Something went wrong. Please go back to the chat.", 400)
    try:
        check = await service.check_return(
            link_id=razorpay_payment_link_id,
            reference_id=razorpay_payment_link_reference_id,
            status=razorpay_payment_link_status,
            payment_id=razorpay_payment_id,
            signature=razorpay_signature,
        )
    except service.RazorpayError as exc:
        log.error("payments.return_check_failed", link_id=razorpay_payment_link_id, error=str(exc))
        return _page(
            "Confirming your payment",
            "We're confirming your payment. You'll get a message in the chat shortly.",
            200,
        )
    if not check.genuine:
        return _page(
            "Payment",
            "We couldn't check this payment page. If you paid, you'll get a message in the chat "
            "shortly.",
            400,
        )
    if check.result is not None:
        await conversations.after_payment(check.result)
    order = f"order #{check.order_number}" if check.order_number else "your order"
    shop = check.shop_name or "the shop"
    if check.paid:
        return _page(
            "Thank you!",
            f"Your payment for {order} with {shop} is received. You'll get a message in the "
            "chat. You can close this page.",
            200,
        )
    return _page(
        "Confirming your payment",
        f"We're confirming your payment for {order}. You'll get a message in the chat shortly.",
        200,
    )


@simulator_router.get("/{payment_id}", response_class=HTMLResponse)
async def simulator_checkout(payment_id: uuid.UUID) -> HTMLResponse:
    """The simulator's stand-in for a payment page: Accept payment or Reject payment."""
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
        "padding:0 1rem;line-height:1.5;color:#1a1a1a}h1{font-size:1.5rem}"
        "@media (prefers-color-scheme:dark){body{background:#111;color:#eee}}</style></head>"
        f"<body><h1>{escape(title)}</h1><p>{escape(message)}</p></body></html>"
    )
    return HTMLResponse(html, status_code=status_code)
