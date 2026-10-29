"""The Orders screen."""

import uuid
from typing import Annotated, Literal

from fastapi import APIRouter, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1 import schemas
from app.api.v1.deps import Shop
from app.core.db import session_scope
from app.modules.conversations import service as conversations
from app.modules.orders import service as orders
from app.modules.orders.schemas import OrderSummary
from app.modules.payments import service as payments

router = APIRouter(prefix="/orders", tags=["orders"])

OrderStatus = Literal[
    "awaiting_payment",
    "paid",
    "expired",
    "cancelled",
    "completed",
    "refunded",
    "draft",
    "pending",
    "confirmed",
    "ready",
    "delivered",
]
PaymentStatus = Literal["pending", "paid", "partially_refunded", "refunded", "failed"]


@router.get("")
async def list_orders(
    shop: Shop,
    status: Annotated[list[OrderStatus] | None, Query()] = None,
    payment_status: Annotated[list[PaymentStatus] | None, Query()] = None,
    limit: Annotated[int, Query(ge=1, le=200)] = 50,
) -> list[schemas.Order]:
    async with session_scope() as session:
        found = await orders.list_orders(
            session,
            shop.merchant_id,
            statuses=tuple(status) if status else None,
            payment_statuses=tuple(payment_status) if payment_status else None,
            limit=limit,
        )
    return [_to_order_schema(order) for order in found]


class RefundRequest(schemas.BaseModel):
    reason: str | None = None
    restock: bool = True


class RefundResponse(schemas.BaseModel):
    order_id: str
    refund_id: str
    amount_minor: int
    currency: str
    status: str


@router.post("/{order_id}/refund", response_model=RefundResponse)
async def refund_order(
    shop: Shop,
    order_id: uuid.UUID,
    payload: RefundRequest | None = None,
) -> RefundResponse:
    reason = payload.reason if payload else None
    restock = payload.restock if payload else True
    try:
        outcome = await payments.refund_order(
            order_id, merchant_id=shop.merchant_id, reason=reason, restock=restock
        )
    except LookupError as exc:
        raise HTTPException(status_code=404, detail="Order not found") from exc
    except RuntimeError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return RefundResponse(
        order_id=str(outcome.order_id),
        refund_id=outcome.refund_id,
        amount_minor=outcome.amount_minor,
        currency=outcome.currency,
        status=outcome.status,
    )


class CreateInvoiceRequest(schemas.BaseModel):
    customer_name: str | None = None
    customer_email: str | None = None


class CreateInvoiceResponse(schemas.BaseModel):
    order_id: str
    invoice_id: str
    payer_view_url: str


@router.post("/{order_id}/invoice", response_model=CreateInvoiceResponse)
async def create_order_invoice(
    shop: Shop,
    order_id: uuid.UUID,
    payload: CreateInvoiceRequest | None = None,
) -> CreateInvoiceResponse:
    """Generate and send a PayPal invoice for an order, returning the invoice payment link."""
    cust_name = payload.customer_name if payload else None
    cust_email = payload.customer_email if payload else None
    if not cust_name:
        async with session_scope() as session:
            order = await orders.get_order(session, order_id, shop.merchant_id)
            if order is not None:
                cust_name = await conversations.get_customer_display_name(
                    session, order.customer_id
                )

    try:
        created = await payments.create_order_invoice(
            order_id,
            merchant_id=shop.merchant_id,
            customer_name=cust_name,
            customer_email=cust_email,
        )
    except LookupError as exc:
        raise HTTPException(status_code=404, detail="Order not found") from exc
    except (ValueError, payments.PaymentUnavailable) as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    return CreateInvoiceResponse(
        order_id=str(order_id),
        invoice_id=created.invoice_id,
        payer_view_url=created.payer_view_url,
    )


@router.post("/{order_id}/mark-paid", response_model=schemas.Order)
async def mark_order_paid(
    shop: Shop,
    order_id: uuid.UUID,
    payload: schemas.MarkPaidRequest | None = None,
) -> schemas.Order:
    """Owner tap-to-confirm when receiving a UPI payment alert or counter cash."""
    method = payload.method if payload else "upi"
    ref_id = payload.reference_id if payload else None
    try:
        async with session_scope() as session:
            result = await payments.mark_order_paid(
                session,
                order_id,
                merchant_id=shop.merchant_id,
                actor="merchant",
                method=method,
                reference_id=ref_id,
            )
            order_res = await _order_response(session, order_id, shop.merchant_id)
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    if result.outcome in ("paid", "paid_stock_short"):
        await conversations.after_payment(result)
    return order_res


@router.post("/{order_id}/complete", response_model=schemas.Order)
async def complete_order(shop: Shop, order_id: uuid.UUID) -> schemas.Order:
    """Mark an order as completed (picked up or delivered)."""
    try:
        async with session_scope() as session:
            await orders.complete_order(
                session, order_id, merchant_id=shop.merchant_id, actor="merchant"
            )
            return await _order_response(session, order_id, shop.merchant_id)
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.post("/{order_id}/cancel", response_model=schemas.Order)
async def cancel_order(
    shop: Shop, order_id: uuid.UUID, body: schemas.CancelOrderRequest | None = None
) -> schemas.Order:
    """Cancel an unpaid order and release its held stock back to today's ledger."""
    reason = body.reason if body else None
    try:
        async with session_scope() as session:
            await orders.cancel_order(
                session,
                order_id,
                merchant_id=shop.merchant_id,
                actor="merchant",
                reason=reason,
            )
            return await _order_response(session, order_id, shop.merchant_id)
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.get("/{order_id}/payment-link", response_model=schemas.PaymentLinkResponse)
async def get_payment_link(shop: Shop, order_id: uuid.UUID) -> schemas.PaymentLinkResponse:
    """Get the payment link for an order: dynamic UPI link for INR, PayPal for cross-border."""
    try:
        outcome = await payments.get_order_payment_link(order_id, merchant_id=shop.merchant_id)
    except LookupError as exc:
        raise HTTPException(status_code=404, detail="Order not found") from exc
    except (ValueError, payments.PaymentUnavailable) as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    return schemas.PaymentLinkResponse(
        order_id=outcome.order_id,
        order_number=outcome.order_number,
        payment_method=outcome.payment_method,
        payment_link=outcome.payment_link,
        currency=outcome.currency,
        total_minor=outcome.total_minor,
    )


@router.patch("/{order_id}/status", response_model=schemas.Order)
async def update_order_status(
    shop: Shop, order_id: uuid.UUID, body: schemas.UpdateOrderStatusRequest
) -> schemas.Order:
    """Advance an order through enterprise fulfillment / operational stages."""
    try:
        async with session_scope() as session:
            await orders.advance_order_status(
                session,
                order_id,
                merchant_id=shop.merchant_id,
                new_status=body.status,
                actor="merchant",
                comment=body.comment,
            )
            return await _order_response(session, order_id, shop.merchant_id)
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.get("/{order_id}/timeline", response_model=list[schemas.OrderTimelineEvent])
async def get_order_timeline(shop: Shop, order_id: uuid.UUID) -> list[schemas.OrderTimelineEvent]:
    """Fetch order status timeline history auto-logged by database triggers."""
    try:
        async with session_scope() as session:
            events = await orders.get_order_timeline(session, order_id, shop.merchant_id)
            return [
                schemas.OrderTimelineEvent(
                    id=e.id,
                    order_id=e.order_id,
                    from_status=e.from_status,
                    to_status=e.to_status,
                    triggered_by=e.triggered_by,
                    comment=e.comment,
                    created_at=e.created_at,
                )
                for e in events
            ]
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


async def _order_response(
    session: AsyncSession, order_id: uuid.UUID, merchant_id: uuid.UUID
) -> schemas.Order:
    order = await orders.get_order(session, order_id, merchant_id)
    if order is None:
        raise HTTPException(status_code=404, detail="Order not found")
    return _to_order_schema(order)


def _to_order_schema(order: OrderSummary) -> schemas.Order:
    return schemas.Order(
        id=order.id,
        number=order.number,
        status=order.status,
        payment_status=order.payment_status,
        fulfilment_status=order.fulfilment_status,
        fulfilment_method=order.fulfilment_method,
        channel=order.channel,
        currency=order.currency,
        total_minor=order.total_minor,
        delivery_address=order.delivery_address,
        customer_note=order.customer_note,
        conversation_id=order.conversation_id,
        created_at=order.created_at,
        paid_at=order.paid_at,
        hold_expires_at=order.hold_expires_at,
        items=[schemas.OrderItem(**vars(item)) for item in order.items],
        order_number=order.order_number,
        fulfilment=order.fulfilment,
        delivery_type=order.delivery_type,
        source_channel=order.source_channel,
        total_amount_minor=order.total_amount_minor,
        needed_by=order.needed_by,
        notes=order.notes,
    )
