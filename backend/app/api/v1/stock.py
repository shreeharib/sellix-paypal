"""Stock for the coming days: items the shop sells ahead ("available for pickup all week").

Quantities are per day, like today's stock: a customer picks a day and only that day's stock
is held for their order.
"""

from datetime import date, timedelta

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from app.api.v1 import schemas
from app.api.v1.deps import Shop
from app.core.db import session_scope
from app.modules.inventory import service as inventory
from app.modules.inventory.schemas import OpeningStockLine
from app.modules.merchants import service as merchants

router = APIRouter(prefix="/stock", tags=["stock"])

MAX_DAYS_AHEAD = 30


class UpcomingStock(BaseModel):
    from_date: date
    to_date: date
    lines: list[schemas.StockLine] = Field(min_length=1, max_length=200)


class UpcomingItem(BaseModel):
    product: str
    variant: str | None
    price_minor: int
    currency: str
    available: int


class UpcomingDay(BaseModel):
    date: date
    items: list[UpcomingItem]


@router.put("/upcoming")
async def set_upcoming(shop: Shop, body: UpcomingStock) -> list[UpcomingDay]:
    """The same quantity each day from `from_date` to `to_date` (a later call replaces it)."""
    async with session_scope() as session:
        today = merchants.business_date(await merchants.get_merchant(session, shop.merchant_id))
    if body.from_date < today or body.to_date < body.from_date:
        raise HTTPException(status_code=400, detail="The dates must run from today onwards")
    if body.to_date > today + timedelta(days=MAX_DAYS_AHEAD):
        raise HTTPException(
            status_code=400, detail=f"Stock can be set up to {MAX_DAYS_AHEAD} days ahead"
        )
    lines = [
        OpeningStockLine(
            product=line.product,
            variant=line.variant,
            price_minor=line.price_minor,
            quantity=line.quantity,
            currency=line.currency,
        )
        for line in body.lines
    ]
    try:
        async with session_scope() as session:
            day = body.from_date
            while day <= body.to_date:
                await inventory.set_opening_stock(
                    session, merchant_id=shop.merchant_id, business_date=day, lines=lines
                )
                day += timedelta(days=1)
    except ValueError as exc:  # includes StockConflict
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    return await _upcoming(shop, today)  # the coming days, as GET shows them


@router.get("/upcoming")
async def upcoming(shop: Shop) -> list[UpcomingDay]:
    async with session_scope() as session:
        today = merchants.business_date(await merchants.get_merchant(session, shop.merchant_id))
    return await _upcoming(shop, today)


async def _upcoming(shop: Shop, after: date) -> list[UpcomingDay]:
    async with session_scope() as session:
        found = await inventory.upcoming_stock(session, shop.merchant_id, after, MAX_DAYS_AHEAD)
    return [
        UpcomingDay(
            date=day,
            items=[
                UpcomingItem(
                    product=item.product,
                    variant=item.variant,
                    price_minor=item.price_minor,
                    currency=item.currency,
                    available=item.available,
                )
                for item in stock
            ],
        )
        for day, stock in found.items()
    ]
