"""The Orders screen."""

import uuid
from typing import Annotated, Literal

from fastapi import APIRouter, HTTPException, Query
from sqlalchemy import select

from app.api.v1 import schemas
from app.api.v1.deps import Shop
from app.core.db import session_scope
from app.modules.conversations.models import Customer
from app.modules.merchants import service as merchants
from app.modules.orders import service as orders
from app.modules.orders.models import Order, OrderItem
from app.modules.orders.schemas import PlacedOrder
from app.modules.payments import service as payments

router = APIRouter(prefix="/orders", tags=["orders"])

OrderStatus = Literal["awaiting_payment", "paid", "expired", "cancelled", "completed", "refunded"]


@router.get("")
async def list_orders(
    shop: Shop,
    status: Annotated[list[OrderStatus] | None, Query()] = None,
    limit: Annotated[int, Query(ge=1, le=200)] = 50,
) -> list[schemas.Order]:
    async with session_scope() as session:
        found = await orders.list_orders(
            session, shop.merchant_id, statuses=tuple(status) if status else None, limit=limit
        )
    return [
        schemas.Order(
            id=order.id,
            number=order.number,
            status=order.status,
            currency=order.currency,
            total_minor=order.total_minor,
            fulfilment=order.fulfilment,
            delivery_address=order.delivery_address,
            needed_by=order.needed_by,
            notes=order.notes,
            conversation_id=order.conversation_id,
            created_at=order.created_at,
            paid_at=order.paid_at,
            hold_expires_at=order.hold_expires_at,
            items=[schemas.OrderItem(**vars(item)) for item in order.items],
        )
        for order in found
    ]


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
        outcome = await payments.refund_order(order_id, reason=reason, restock=restock)
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
    async with session_scope() as session:
        order = await session.scalar(
            select(Order).where(Order.id == order_id, Order.merchant_id == shop.merchant_id)
        )
        if order is None:
            raise HTTPException(status_code=404, detail="Order not found")
        if order.status in ("paid", "completed", "refunded"):
            raise HTTPException(
                status_code=400,
                detail=f"Cannot generate invoice for order with status '{order.status}'",
            )

        merchant = await merchants.get_merchant(session, shop.merchant_id)
        shop_name = merchant.name if merchant else "Sellix Shop"

        items = list(await session.scalars(select(OrderItem).where(OrderItem.order_id == order.id)))
        item_dicts = [
            {
                "name": (
                    f"{item.product_name} ({item.variant_name})"
                    if item.variant_name
                    else item.product_name
                ),
                "unit_price_minor": item.unit_price_minor,
                "quantity": item.quantity,
            }
            for item in items
        ]

        customer = await session.get(Customer, order.customer_id)
        cust_name = (
            payload.customer_name
            if (payload and payload.customer_name)
            else (customer.display_name if customer else None)
        )
        cust_email = payload.customer_email if payload else None

        placed = PlacedOrder(
            order_id=order.id,
            number=order.number,
            currency=order.currency,
            total_minor=order.total_minor,
            hold_minutes=15,
        )

    try:
        created = await payments.create_invoice_checkout(
            placed,
            shop_name=shop_name,
            customer_name=cust_name,
            customer_email=cust_email,
            items=item_dicts,
        )
    except payments.PaymentUnavailable as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    return CreateInvoiceResponse(
        order_id=str(order.id),
        invoice_id=created.invoice_id,
        payer_view_url=created.payer_view_url,
    )
