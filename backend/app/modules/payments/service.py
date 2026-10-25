"""Public interface of the payments module: checkout links and payment confirmation.

An order counts as paid only when PayPal confirms the capture: never from a screenshot,
and never from the buyer merely returning to our page.
"""

import uuid
from collections.abc import Mapping
from dataclasses import dataclass
from typing import Any, Literal

import structlog
from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert

from app.core.config import get_settings
from app.core.db import session_scope
from app.modules.orders import service as orders
from app.modules.orders.models import Order
from app.modules.orders.schemas import PaymentResult, PlacedOrder
from app.modules.payments import paypal
from app.modules.payments.models import Payment

log = structlog.get_logger()


class PaymentUnavailable(RuntimeError):
    """No online payment for this order; the message says why (for logs and the merchant)."""


@dataclass(frozen=True)
class PaymentFailed:
    """PayPal declined the payment; the order is still waiting for payment."""

    order_id: uuid.UUID
    number: int
    conversation_id: uuid.UUID | None
    outcome: Literal["payment_failed"] = "payment_failed"


def configured() -> bool:
    """Whether customers can be sent a payment link at all (PayPal keys are set)."""
    return paypal.configured()


def accepts(currency: str) -> bool:
    """Whether an online payment link can be offered for an order in this currency."""
    return paypal.configured() and currency in paypal.SUPPORTED_CURRENCIES


async def create_checkout(placed: PlacedOrder, *, shop_name: str) -> str:
    """Create the PayPal payment for an order and return the link the customer pays at."""
    if not paypal.configured():
        raise PaymentUnavailable("PayPal isn't set up")
    if placed.currency not in paypal.SUPPORTED_CURRENCIES:
        raise PaymentUnavailable(f"PayPal can't take payments in {placed.currency}")

    base_url = get_settings().public_base_url.rstrip("/")
    try:
        created = await paypal.create_order(
            reference_id=str(placed.order_id),
            description=f"{shop_name} order #{placed.number}",
            amount_minor=placed.total_minor,
            currency=placed.currency,
            brand_name=shop_name,
            return_url=f"{base_url}/payments/paypal/return",
            cancel_url=f"{base_url}/payments/paypal/cancel",
        )
    except paypal.PayPalError as exc:
        raise PaymentUnavailable(str(exc)) from exc

    async with session_scope() as session:
        order = await session.get(Order, placed.order_id)
        if order is None:
            raise LookupError(f"No order {placed.order_id}")
        await session.execute(
            pg_insert(Payment)
            .values(
                merchant_id=order.merchant_id,
                order_id=order.id,
                provider="paypal",
                provider_order_id=created.paypal_order_id,
                status="created",
                currency=placed.currency,
                amount_minor=placed.total_minor,
                approve_url=created.approve_url,
            )
            .on_conflict_do_nothing(index_elements=[Payment.provider, Payment.provider_order_id])
        )
    return created.approve_url


async def capture(paypal_order_id: str) -> PaymentResult | PaymentFailed | None:
    """Capture an approved PayPal order (buyer returned, or PayPal's approval webhook)."""
    async with session_scope() as session:
        payment = await session.scalar(
            select(Payment).where(
                Payment.provider == "paypal", Payment.provider_order_id == paypal_order_id
            )
        )
    if payment is None:
        log.warning("payments.unknown_paypal_order", paypal_order_id=paypal_order_id)
        return None
    if payment.status in ("completed", "refunded"):
        return None
    result = await paypal.capture_order(paypal_order_id)
    if result is None:
        return None  # not approved yet
    return await record_capture(paypal_order_id, result)


async def record_capture(
    paypal_order_id: str, result: paypal.Capture
) -> PaymentResult | PaymentFailed | None:
    async with session_scope() as session:
        payment = await session.scalar(
            select(Payment)
            .where(Payment.provider == "paypal", Payment.provider_order_id == paypal_order_id)
            .with_for_update()
        )
        if payment is None:
            log.warning("payments.unknown_paypal_order", paypal_order_id=paypal_order_id)
            return None
        if result.status == "COMPLETED":
            payment.status = "completed"
            payment.provider_capture_id = result.capture_id or None
            return await orders.record_payment(
                session,
                payment.order_id,
                amount_minor=result.amount_minor,
                currency=result.currency,
                actor="paypal",
            )
        if result.status in ("DECLINED", "FAILED"):
            payment.status = "denied"
            order = await session.get(Order, payment.order_id)
            if order is None:
                return None
            return PaymentFailed(order.id, order.number, order.conversation_id)
        payment.status = "approved"  # PENDING: PayPal sends PAYMENT.CAPTURE.COMPLETED later
        return None


async def handle_webhook(event: Mapping[str, Any]) -> PaymentResult | PaymentFailed | None:
    """Apply a verified PayPal webhook event."""
    event_type = event.get("event_type")
    resource: Mapping[str, Any] = event.get("resource") or {}
    if event_type == "CHECKOUT.ORDER.APPROVED":
        return await capture(str(resource.get("id", "")))
    if event_type in ("PAYMENT.CAPTURE.COMPLETED", "PAYMENT.CAPTURE.DENIED"):
        related = (resource.get("supplementary_data") or {}).get("related_ids") or {}
        paypal_order_id = related.get("order_id")
        if not paypal_order_id:
            log.warning("payments.capture_without_order", event_type=event_type)
            return None
        return await record_capture(str(paypal_order_id), paypal.capture_from_resource(resource))
    log.info("payments.webhook_ignored", event_type=event_type)
    return None


async def verify_webhook(headers: Mapping[str, str], event: Mapping[str, Any]) -> bool:
    try:
        return await paypal.verify_webhook(headers=headers, event=event)
    except paypal.PayPalError as exc:
        log.error("payments.webhook_verification_failed", error=str(exc))
        raise
