"""Public interface of the inventory module: the daily stock ledger.

Every change is one conditional UPDATE on the variant's row for the day, so concurrent orders
can never take stock below zero (the table's check constraint is the last line of defence).
"""

import uuid
from datetime import date

from sqlalchemy import ColumnElement, select, update
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.catalog import service as catalog
from app.modules.catalog.models import Product, ProductVariant
from app.modules.inventory.models import DailyStock
from app.modules.inventory.schemas import LedgerRow, OpeningStockLine, StockItem


class StockConflict(ValueError):
    """The change would make stock negative (more promised than made)."""


async def day_ledger(
    session: AsyncSession, merchant_id: uuid.UUID, business_date: date
) -> list[LedgerRow]:
    """Every variant's stock for the day: opening, restocked, held, sold, counter, left."""
    rows = await session.execute(
        select(
            DailyStock,
            Product.name,
            ProductVariant.name,
            ProductVariant.price_minor,
            ProductVariant.currency,
        )
        .join(ProductVariant, ProductVariant.id == DailyStock.variant_id)
        .join(Product, Product.id == ProductVariant.product_id)
        .where(DailyStock.merchant_id == merchant_id, DailyStock.business_date == business_date)
        .order_by(Product.name, ProductVariant.name)
    )
    return [
        LedgerRow(
            variant_id=stock.variant_id,
            product=product,
            variant=variant,
            price_minor=price,
            currency=currency,
            opening=stock.opening,
            restocked=stock.restocked,
            held=stock.held,
            sold=stock.sold,
            counter_sales=stock.counter_sales,
            available=stock.available,
        )
        for stock, product, variant, price, currency in rows
    ]


async def today_stock(
    session: AsyncSession, merchant_id: uuid.UUID, business_date: date
) -> list[StockItem]:
    rows = await session.execute(
        select(
            Product.name,
            ProductVariant.name,
            ProductVariant.price_minor,
            ProductVariant.currency,
            DailyStock.available,
            ProductVariant.id,
        )
        .join(ProductVariant, ProductVariant.id == DailyStock.variant_id)
        .join(Product, Product.id == ProductVariant.product_id)
        .where(
            DailyStock.merchant_id == merchant_id,
            DailyStock.business_date == business_date,
            Product.is_active,
            ProductVariant.is_active,
        )
        .order_by(Product.name, ProductVariant.name)
    )
    return [
        StockItem(
            product=product,
            variant=variant,
            price_minor=price,
            currency=currency,
            available=available,
            variant_id=variant_id,
        )
        for product, variant, price, currency, available, variant_id in rows
    ]


async def set_opening_stock(
    session: AsyncSession,
    *,
    merchant_id: uuid.UUID,
    business_date: date,
    lines: list[OpeningStockLine],
) -> None:
    """Record the morning stock update: creates products and variants as needed."""
    for line in lines:
        if line.quantity < 0:
            raise ValueError(f"Quantity for {line.product} can't be negative")
        variant = await catalog.upsert_variant(
            session,
            merchant_id=merchant_id,
            product_name=line.product,
            variant_name=line.variant,
            price_minor=line.price_minor,
            currency=line.currency,
        )
        statement = pg_insert(DailyStock).values(
            merchant_id=merchant_id,
            variant_id=variant.id,
            business_date=business_date,
            opening=line.quantity,
        )
        try:
            async with session.begin_nested():
                await session.execute(
                    statement.on_conflict_do_update(
                        index_elements=[DailyStock.variant_id, DailyStock.business_date],
                        set_={"opening": statement.excluded.opening},
                    )
                )
        except IntegrityError as exc:
            raise StockConflict(
                f"{line.product}: {line.quantity} is less than what's already sold or held"
            ) from exc


async def hold(
    session: AsyncSession, *, variant_id: uuid.UUID, business_date: date, quantity: int
) -> bool:
    """Reserve stock for an unpaid order. False if not enough is available."""
    return await _apply(
        session,
        variant_id,
        business_date,
        condition=DailyStock.available >= quantity,
        held=DailyStock.held + quantity,
    )


async def release(
    session: AsyncSession, *, variant_id: uuid.UUID, business_date: date, quantity: int
) -> bool:
    """Give held stock back (the order expired or was cancelled before payment)."""
    return await _apply(
        session,
        variant_id,
        business_date,
        condition=DailyStock.held >= quantity,
        held=DailyStock.held - quantity,
    )


async def confirm_sale(
    session: AsyncSession, *, variant_id: uuid.UUID, business_date: date, quantity: int
) -> bool:
    """Turn held stock into sold stock (the order was paid)."""
    return await _apply(
        session,
        variant_id,
        business_date,
        condition=DailyStock.held >= quantity,
        held=DailyStock.held - quantity,
        sold=DailyStock.sold + quantity,
    )


async def sell_unheld(
    session: AsyncSession, *, variant_id: uuid.UUID, business_date: date, quantity: int
) -> bool:
    """Sell stock that wasn't held (payment arrived after the hold expired)."""
    return await _apply(
        session,
        variant_id,
        business_date,
        condition=DailyStock.available >= quantity,
        sold=DailyStock.sold + quantity,
    )


async def _apply(
    session: AsyncSession,
    variant_id: uuid.UUID,
    business_date: date,
    *,
    condition: ColumnElement[bool],
    **changes: ColumnElement[int],
) -> bool:
    updated = await session.scalar(
        update(DailyStock)
        .where(
            DailyStock.variant_id == variant_id,
            DailyStock.business_date == business_date,
            condition,
        )
        .values(**changes)
        .returning(DailyStock.id)
    )
    return updated is not None
