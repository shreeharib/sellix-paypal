"""Stock for the coming days: items the shop sells ahead ("available for pickup all week").

Quantities are per day, like today's stock: a customer picks a day and only that day's stock
is held for their order.
"""

import uuid
from datetime import date, timedelta

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from app.api.v1 import schemas
from app.api.v1.deps import Shop
from app.core.db import session_scope
from app.modules.catalog import service as catalog
from app.modules.inventory import service as inventory
from app.modules.inventory.schemas import OpeningStockLine
from app.modules.merchants import service as merchants

router = APIRouter(prefix="/stock", tags=["stock"])

MAX_DAYS_AHEAD = 30


class UpcomingStock(BaseModel):
    from_date: date
    to_date: date
    lines: list[schemas.StockLine] = Field(min_length=1, max_length=200)
    # For a single day: products this call creates become that day's items, sold only on
    # `from_date` and absent from other days' stock (a Diwali cake for pickup on 9 Nov).
    # Products that already sell every day are not changed. `last_order_date` is the last day
    # customers can order those items.
    one_day_only: bool = False
    last_order_date: date | None = None


class UpcomingItem(BaseModel):
    product: str
    variant: str | None
    price_minor: int
    currency: str
    available: int
    variant_id: uuid.UUID | None = None
    opening: int = 0  # what was set for the day; `available` is less once orders hold some
    stock_mode: str = "daily"
    shelf_life_days: int | None = None
    available_on: date | None = None  # set: sold on this one day only
    order_by_date: date | None = None  # set: the last day to order


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
    single_day = body.from_date == body.to_date
    if (body.one_day_only or body.last_order_date is not None) and not single_day:
        raise HTTPException(status_code=400, detail="One-day items need a single date")
    if body.last_order_date is not None and not body.one_day_only:
        raise HTTPException(status_code=400, detail="A last order date is for one-day items")
    if body.last_order_date is not None and (
        body.last_order_date < today or body.last_order_date > body.from_date
    ):
        raise HTTPException(
            status_code=400, detail="The last order date must be from today to the day it's sold"
        )
    names = {line.product for line in lines}
    try:
        async with session_scope() as session:
            existing = await catalog.products_by_names(session, shop.merchant_id, names)
            for product in existing.values():
                if product.available_on is not None and (
                    not single_day or product.available_on != body.from_date
                ):
                    raise ValueError(
                        f"{product.name} is only sold on {product.available_on:%d %b}. "
                        "Change its day first."
                    )
            day = body.from_date
            while day <= body.to_date:
                await inventory.set_opening_stock(
                    session, merchant_id=shop.merchant_id, business_date=day, lines=lines
                )
                day += timedelta(days=1)
            if body.one_day_only:
                # New products set up for one day belong to that day only, not to today's list.
                fixed = {name.strip().lower() for name in names} - existing.keys()
                fixed |= {n for n, p in existing.items() if p.available_on == body.from_date}
                await catalog.set_sold_on(
                    session,
                    shop.merchant_id,
                    fixed,
                    day=body.from_date,
                    order_by_date=body.last_order_date,
                )
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
                    variant_id=item.variant_id,
                    opening=item.opening,
                    stock_mode=item.stock_mode,
                    shelf_life_days=item.shelf_life_days,
                    available_on=item.available_on,
                    order_by_date=item.order_by_date,
                )
                for item in stock
            ],
        )
        for day, stock in found.items()
    ]
