"""Public interface of the payments module: checkout links and payment confirmation.

An order counts as paid only when PayPal confirms the capture: never from a screenshot,
and never from the buyer merely returning to our page.
"""

import dataclasses
import uuid
from collections.abc import Mapping
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any, Literal

import structlog
from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.db import session_scope
from app.modules.merchants import service as merchants
from app.modules.orders import service as orders
from app.modules.orders.schemas import PaymentResult, PlacedOrder, RefundStatus, RefundTicket
from app.modules.payments import paypal, upi
from app.modules.payments.models import Payment
from app.modules.shop_profile import service as shop_profile

log = structlog.get_logger()

PayPalError = paypal.PayPalError


class PaymentUnavailable(RuntimeError):
    """No online payment for this order; the message says why (for logs and the merchant)."""


@dataclass(frozen=True)
class PaymentFailed:
    """PayPal declined the payment; the order is still waiting for payment."""

    order_id: uuid.UUID
    number: int
    conversation_id: uuid.UUID | None
    outcome: Literal["payment_failed"] = "payment_failed"


@dataclass(frozen=True)
class RefundOutcome:
    order_id: uuid.UUID
    refund_id: str
    amount_minor: int
    currency: str
    status: str


@dataclass(frozen=True)
class OrderPaymentLink:
    order_id: uuid.UUID
    order_number: int
    payment_method: Literal["upi", "paypal"]
    payment_link: str
    currency: str
    total_minor: int


def configured() -> bool:
    """Whether customers can be sent a payment link at all (PayPal keys are set)."""
    return paypal.configured()


def accepts(currency: str) -> bool:
    """Whether an online payment link can be offered for an order in this currency via PayPal."""
    return paypal.configured() and currency in paypal.SUPPORTED_CURRENCIES


def create_upi_checkout(
    placed: PlacedOrder,
    *,
    vpa: str,
    shop_name: str,
) -> str:
    """Generate the standard UPI payment link for an INR order (no QR code needed)."""
    return upi.create_upi_link(
        vpa=vpa,
        payee_name=shop_name,
        amount_minor=placed.total_minor,
        order_number=placed.number,
        currency=placed.currency,
    )


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
        order = await orders.get_order(session, placed.order_id)
        if order is None or order.merchant_id is None:
            raise LookupError(f"No order {placed.order_id}")
        await session.execute(
            pg_insert(Payment)
            .values(
                merchant_id=order.merchant_id,
                order_id=order.id,
                provider="paypal",
                method="paypal_wallet",
                provider_order_id=created.paypal_order_id,
                status="created",
                currency=placed.currency,
                amount_minor=placed.total_minor,
                approve_url=created.approve_url,
            )
            .on_conflict_do_nothing(index_elements=[Payment.provider, Payment.provider_order_id])
        )
    return created.approve_url


def record_manual_payment(
    session: AsyncSession,
    *,
    merchant_id: uuid.UUID,
    order_id: uuid.UUID,
    order_number: int,
    currency: str,
    amount_minor: int,
    method: str = "upi",
    reference_id: str | None = None,
) -> None:
    """Record a manual UPI or counter cash payment in the payments ledger."""
    provider = "upi_manual" if method == "upi" else ("cash" if method == "cash" else "manual")
    payment = Payment(
        merchant_id=merchant_id,
        order_id=order_id,
        provider=provider,
        method=method,
        kind="full",
        provider_order_id=reference_id or f"MANUAL-{order_number}",
        status="completed",
        currency=currency,
        amount_minor=amount_minor,
        paid_at=datetime.now(UTC),
    )
    session.add(payment)


async def mark_order_paid(
    session: AsyncSession,
    order_id: uuid.UUID,
    *,
    merchant_id: uuid.UUID,
    actor: str = "merchant",
    method: str = "upi",
    reference_id: str | None = None,
) -> PaymentResult:
    """Confirm a manual UPI or counter cash payment and mark the order paid."""
    order = await orders.get_order(session, order_id, merchant_id)
    if order is None:
        raise LookupError(f"No order {order_id}")
    if order.status in ("cancelled", "expired"):
        raise ValueError(f"Cannot mark order as paid when status is '{order.status}'")

    if order.status not in ("paid", "completed", "refunded"):
        record_manual_payment(
            session,
            merchant_id=merchant_id,
            order_id=order.id,
            order_number=order.number,
            currency=order.currency,
            amount_minor=order.total_minor,
            method=method,
            reference_id=reference_id,
        )

    return await orders.record_payment(
        session,
        order_id,
        amount_minor=order.total_minor,
        currency=order.currency,
        actor=actor,
    )


async def create_invoice_checkout(
    placed: PlacedOrder,
    *,
    shop_name: str,
    customer_name: str | None = None,
    customer_email: str | None = None,
    items: list[dict[str, Any]] | None = None,
) -> paypal.CreatedInvoice:
    """Create a PayPal invoice for an order and return the created invoice details."""
    if not paypal.configured():
        raise PaymentUnavailable("PayPal isn't set up")
    if placed.currency not in paypal.SUPPORTED_CURRENCIES:
        raise PaymentUnavailable(f"PayPal can't take payments in {placed.currency}")

    try:
        invoice_id = await paypal.create_invoice(
            reference_id=str(placed.order_id),
            invoice_number=f"INV-{placed.number}",
            description=f"{shop_name} order #{placed.number}",
            items=items or [],
            total_minor=placed.total_minor,
            currency=placed.currency,
            brand_name=shop_name,
            customer_name=customer_name,
            customer_email=customer_email,
        )
        payer_view_url = await paypal.send_invoice(invoice_id)
    except paypal.PayPalError as exc:
        raise PaymentUnavailable(str(exc)) from exc

    async with session_scope() as session:
        order = await orders.get_order(session, placed.order_id)
        if order is None or order.merchant_id is None:
            raise LookupError(f"No order {placed.order_id}")
        await session.execute(
            pg_insert(Payment)
            .values(
                merchant_id=order.merchant_id,
                order_id=order.id,
                provider="paypal",
                method="paypal_wallet",
                provider_order_id=invoice_id,
                status="created",
                currency=placed.currency,
                amount_minor=placed.total_minor,
                approve_url=payer_view_url,
            )
            .on_conflict_do_nothing(index_elements=[Payment.provider, Payment.provider_order_id])
        )
    return paypal.CreatedInvoice(invoice_id=invoice_id, payer_view_url=payer_view_url)


async def create_order_invoice(
    order_id: uuid.UUID,
    *,
    merchant_id: uuid.UUID,
    customer_name: str | None = None,
    customer_email: str | None = None,
) -> paypal.CreatedInvoice:
    """Validate order state, build line items, and create/send a PayPal invoice for an order."""
    async with session_scope() as session:
        order = await orders.get_order(session, order_id, merchant_id)
        if order is None:
            raise LookupError(f"No order {order_id}")
        if order.status in ("paid", "completed", "refunded"):
            raise ValueError(f"Cannot generate invoice for order with status '{order.status}'")

        merchant = await merchants.find_merchant(session, merchant_id)
        shop_name = merchant.name if merchant else "Sellix Shop"

        item_dicts = [
            {
                "name": (f"{item.product} ({item.variant})" if item.variant else item.product),
                "unit_price_minor": item.unit_price_minor,
                "quantity": item.quantity,
            }
            for item in order.items
        ]
        placed = PlacedOrder(
            order_id=order.id,
            number=order.number,
            currency=order.currency,
            total_minor=order.total_minor,
            hold_minutes=15,
        )

    return await create_invoice_checkout(
        placed,
        shop_name=shop_name,
        customer_name=customer_name,
        customer_email=customer_email,
        items=item_dicts,
    )


async def get_order_payment_link(
    order_id: uuid.UUID,
    *,
    merchant_id: uuid.UUID,
) -> OrderPaymentLink:
    """Resolve and create the payment link for an order (UPI for INR, PayPal otherwise)."""
    async with session_scope() as session:
        order = await orders.get_order(session, order_id, merchant_id)
        if order is None:
            raise LookupError(f"No order {order_id}")

        merchant = await merchants.find_merchant(session, merchant_id)
        shop_name = merchant.name if merchant else "Sellix Shop"

        placed = PlacedOrder(
            order_id=order.id,
            number=order.number,
            currency=order.currency,
            total_minor=order.total_minor,
            hold_minutes=15,
        )

        if order.currency == "INR":
            onboarding = await shop_profile.get_onboarding(session, merchant_id)
            vpa = (
                onboarding.answers.get("upi_id") if onboarding and onboarding.answers else None
            ) or f"{shop_name.lower().replace(' ', '')}@upi"
            link = create_upi_checkout(placed, vpa=vpa, shop_name=shop_name)
            method: Literal["upi", "paypal"] = "upi"
        elif accepts(order.currency):
            link = await create_checkout(placed, shop_name=shop_name)
            method = "paypal"
        else:
            raise PaymentUnavailable(
                f"No online payment method available for currency {order.currency}"
            )

    return OrderPaymentLink(
        order_id=order.id,
        order_number=order.number,
        payment_method=method,
        payment_link=link,
        currency=order.currency,
        total_minor=order.total_minor,
    )


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
    return await verify_and_record(paypal_order_id)


async def verify_and_record(paypal_order_id: str) -> PaymentResult | PaymentFailed | None:
    """Mark an order paid only after re-fetching it from PayPal (agent-phase-2.md 14, item 1).

    Webhook bodies and capture answers only say which order to check. PayPal's own record must
    show the order COMPLETED, a COMPLETED capture, and our order id as custom_id. The amount
    and currency PayPal reports go to orders.record_payment, which refuses a mismatch and
    alerts the merchant. (Once shops connect their own PayPal accounts, the payee is checked
    here too: agent-phase-2.md section 21, item 7.)
    """
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
        return None  # already recorded: a replayed webhook or a second return
    data = await paypal.get_order(paypal_order_id)
    unit: dict[str, Any] = (data.get("purchase_units") or [{}])[0]
    if str(unit.get("custom_id") or unit.get("reference_id") or "") != str(payment.order_id):
        log.error(
            "payments.payment_verification_failed",
            paypal_order_id=paypal_order_id,
            reason="custom_id doesn't match this order",
        )
        return None
    captured = paypal.capture_from_order(data)
    if captured is None:
        return None
    if captured.status == "COMPLETED" and data.get("status") != "COMPLETED":
        captured = paypal.Capture("PENDING", captured.capture_id, 0, captured.currency)
    return await _record_verified(paypal_order_id, captured)


async def _record_verified(
    paypal_order_id: str, result: paypal.Capture
) -> PaymentResult | PaymentFailed | None:
    """Record a capture already checked against PayPal (only verify_and_record calls this)."""
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
            payment.paid_at = datetime.now(UTC)
            return await orders.record_payment(
                session,
                payment.order_id,
                amount_minor=result.amount_minor,
                currency=result.currency,
                actor="paypal",
            )
        if result.status in ("DECLINED", "FAILED"):
            payment.status = "denied"
            order = await orders.get_order(session, payment.order_id)
            if order is None:
                return None
            return PaymentFailed(order.id, order.number, order.conversation_id)
        payment.status = "approved"  # PENDING: PayPal sends PAYMENT.CAPTURE.COMPLETED later
        return None


async def record_invoice_payment(
    invoice_id: str,
    paid_amount_minor: int,
    currency: str,
) -> PaymentResult | None:
    async with session_scope() as session:
        payment = await session.scalar(
            select(Payment)
            .where(Payment.provider == "paypal", Payment.provider_order_id == invoice_id)
            .with_for_update()
        )
        if payment is None:
            log.warning("payments.unknown_paypal_invoice", invoice_id=invoice_id)
            return None
        payment.status = "completed"
        payment.paid_at = datetime.now(UTC)
        return await orders.record_payment(
            session,
            payment.order_id,
            amount_minor=paid_amount_minor,
            currency=currency,
            actor="paypal",
        )


async def refund_order(
    order_id: uuid.UUID,
    *,
    merchant_id: uuid.UUID,
    reason: str | None = None,
    restock: bool = True,
) -> RefundOutcome:
    """Refund a paid order of this merchant's shop through PayPal.

    The refund is committed as pending before PayPal is called, so money PayPal sends back is
    always on record. PayPal's answer settles it; if that answer is lost, the
    PAYMENT.CAPTURE.REFUNDED webhook or reconcile_refunds does.
    """
    if not paypal.configured():
        raise RuntimeError("PayPal isn't configured")
    async with session_scope() as session:
        order = await orders.get_order(session, order_id, merchant_id)
        if order is None:
            raise LookupError(f"No order {order_id}")
        capture = await _captured_payment(session, order_id, merchant_id)
        if capture is None:
            raise RuntimeError(f"No completed PayPal payment capture found for order {order_id}")
        ticket = await orders.open_refund(session, order_id, restock=restock, reason=reason)

    result = await _request_refund(ticket, capture)
    return RefundOutcome(
        order_id=order_id,
        refund_id=result.refund_id,
        amount_minor=result.amount_minor,
        currency=result.currency,
        status=result.status,
    )


async def reconcile_refunds(older_than: timedelta = timedelta(minutes=5)) -> int:
    """Settle refunds still pending after `older_than`; returns how many completed."""
    async with session_scope() as session:
        stuck = [
            (ticket, await _captured_payment(session, ticket.order_id))
            for ticket in await orders.pending_refunds(session, older_than=older_than)
        ]
    completed = 0
    for ticket, capture in stuck:
        if capture is None:
            log.error("payments.refund_without_capture", refund_id=str(ticket.id))
            continue
        try:
            if ticket.provider_refund_id:
                result = await paypal.get_refund(ticket.provider_refund_id)
                await _record_refund(ticket.id, capture.capture_id, result)
            else:
                result = await _request_refund(ticket, capture)
        except (paypal.PayPalError, RuntimeError) as exc:
            log.warning(
                "payments.refund_reconcile_failed", refund_id=str(ticket.id), error=str(exc)
            )
            continue
        if result.status == "COMPLETED":
            completed += 1
    return completed


@dataclass(frozen=True)
class _Capture:
    capture_id: str
    amount_minor: int
    currency: str


_REFUND_STATUSES: dict[str, RefundStatus] = {
    "COMPLETED": "completed",
    "FAILED": "failed",
    "CANCELLED": "failed",
}


async def _captured_payment(
    session: AsyncSession, order_id: uuid.UUID, merchant_id: uuid.UUID | None = None
) -> _Capture | None:
    query = select(Payment).where(
        Payment.order_id == order_id,
        Payment.provider == "paypal",
        Payment.status == "completed",
    )
    if merchant_id is not None:
        query = query.where(Payment.merchant_id == merchant_id)
    payment = await session.scalar(query)
    if payment is None or not payment.provider_capture_id:
        return None
    return _Capture(payment.provider_capture_id, payment.amount_minor, payment.currency)


async def _request_refund(ticket: RefundTicket, capture: _Capture) -> paypal.RefundResult:
    """Ask PayPal to refund the capture and record its answer.

    Every try uses the same PayPal-Request-Id, so retrying never refunds twice.
    """
    try:
        result = await paypal.refund_capture(
            capture.capture_id,
            amount_minor=capture.amount_minor,
            currency=capture.currency,
            note=ticket.reason,
        )
    except paypal.PayPalError as exc:
        unknown = paypal.RefundResult(
            ticket.provider_refund_id or "", "PENDING", capture.amount_minor, capture.currency
        )
        if exc.issue == "CAPTURE_FULLY_REFUNDED":
            # The money is already back with the buyer: an earlier try, or the PayPal dashboard.
            result = dataclasses.replace(unknown, status="COMPLETED")
        elif exc.status in (0, 408, 429) or exc.status >= 500:
            log.warning("payments.refund_unconfirmed", refund_id=str(ticket.id), error=str(exc))
            return unknown
        else:
            await _record_refund(
                ticket.id, capture.capture_id, dataclasses.replace(unknown, status="FAILED")
            )
            raise RuntimeError(f"PayPal refused the refund: {exc}") from exc
    await _record_refund(ticket.id, capture.capture_id, result)
    return result


async def _record_refund(
    refund_id: uuid.UUID, capture_id: str, result: paypal.RefundResult
) -> None:
    status = _REFUND_STATUSES.get(result.status, "pending")
    async with session_scope() as session:
        if status == "completed":
            payment = await session.scalar(
                select(Payment)
                .where(Payment.provider == "paypal", Payment.provider_capture_id == capture_id)
                .with_for_update()
            )
            if payment is not None:
                payment.status = "refunded"
        await orders.settle_refund(
            session, refund_id, status=status, provider_refund_id=result.refund_id or None
        )


async def _refund_reported(resource: Mapping[str, Any]) -> None:
    """PayPal reports a refund: re-fetch it from PayPal rather than trusting the event body."""
    refund_id = str(resource.get("id", ""))
    links: list[Mapping[str, Any]] = resource.get("links") or []
    capture_url = next((str(link.get("href", "")) for link in links if link.get("rel") == "up"), "")
    capture_id = capture_url.rsplit("/", 1)[-1]
    if not refund_id or not capture_id:
        log.warning("payments.refund_event_incomplete", refund_id=refund_id)
        return
    async with session_scope() as session:
        payment = await session.scalar(
            select(Payment).where(
                Payment.provider == "paypal", Payment.provider_capture_id == capture_id
            )
        )
        pending = (
            await orders.pending_refunds(session, order_id=payment.order_id) if payment else []
        )
    if not pending:
        log.info("payments.refund_event_ignored", refund_id=refund_id)
        return
    await _record_refund(pending[0].id, capture_id, await paypal.get_refund(refund_id))


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
        # The body only says which order to look at; PayPal's record decides.
        return await verify_and_record(str(paypal_order_id))
    if event_type == "PAYMENT.CAPTURE.REFUNDED":
        await _refund_reported(resource)
        return None
    if event_type == "INVOICING.INVOICE.PAID":
        invoice_id = str(resource.get("id", ""))
        amount_data = resource.get("amount") or (
            resource.get("payments", [{}])[-1].get("amount") if resource.get("payments") else {}
        )
        paid_amount_minor = paypal.to_minor(str(amount_data.get("value", "0")))
        currency = str(amount_data.get("currency_code", ""))
        return await record_invoice_payment(invoice_id, paid_amount_minor, currency)
    log.info("payments.webhook_ignored", event_type=event_type)
    return None


async def verify_webhook(headers: Mapping[str, str], event: Mapping[str, Any]) -> bool:
    try:
        return await paypal.verify_webhook(headers=headers, event=event)
    except paypal.PayPalError as exc:
        log.error("payments.webhook_verification_failed", error=str(exc))
        raise
