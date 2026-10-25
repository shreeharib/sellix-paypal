"""The Orders screen."""

from typing import Annotated, Literal

from fastapi import APIRouter, Query

from app.api.v1 import schemas
from app.api.v1.deps import Shop
from app.core.db import session_scope
from app.modules.orders import service as orders

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
