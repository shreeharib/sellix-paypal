"""Public interface of the inventory module: the daily stock ledger.

Every change is one conditional UPDATE on the variant's row for the day, so concurrent orders
can never take stock below zero (the table's check constraint is the last line of defence).
"""

import re
import uuid
from datetime import UTC, date, datetime, timedelta
from decimal import Decimal, InvalidOperation

from sqlalchemy import ColumnElement, select, text, update
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.catalog import service as catalog
from app.modules.inventory.models import DailyStock, StockHold
from app.modules.inventory.schemas import (
    LedgerRow,
    OpeningStockLine,
    RolloverItemSelection,
    StockItem,
    YesterdayLeftover,
)


class StockConflict(ValueError):
    """The change would make stock negative (more promised than made)."""


async def day_ledger(
    session: AsyncSession, merchant_id: uuid.UUID, business_date: date
) -> list[LedgerRow]:
    """Every variant's stock for the day: opening, restocked, held, sold, counter, left."""
    stocks = {
        s.variant_id: s
        for s in await session.scalars(
            select(DailyStock).where(
                DailyStock.merchant_id == merchant_id,
                DailyStock.business_date == business_date,
            )
        )
    }
    variants = await catalog.list_variants_by_ids(
        session, merchant_id, stocks.keys(), active_only=False
    )
    return [
        LedgerRow(
            variant_id=v.variant_id,
            product=v.product_name,
            variant=v.variant_name,
            price_minor=v.price_minor,
            currency=v.currency,
            opening=stocks[v.variant_id].opening,
            restocked=stocks[v.variant_id].restocked,
            held=stocks[v.variant_id].held,
            sold=stocks[v.variant_id].sold,
            counter_sales=stocks[v.variant_id].counter_sales,
            available=stocks[v.variant_id].available,
        )
        for v in variants
    ]


async def today_stock(
    session: AsyncSession, merchant_id: uuid.UUID, business_date: date
) -> list[StockItem]:
    stocks = {
        s.variant_id: s
        for s in await session.scalars(
            select(DailyStock).where(
                DailyStock.merchant_id == merchant_id,
                DailyStock.business_date == business_date,
            )
        )
    }
    variants = await catalog.list_variants_by_ids(
        session, merchant_id, stocks.keys(), active_only=True
    )
    return [
        StockItem(
            product=v.product_name,
            variant=v.variant_name,
            price_minor=v.price_minor,
            currency=v.currency,
            available=stocks[v.variant_id].available,
            variant_id=v.variant_id,
        )
        for v in variants
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
    session: AsyncSession,
    *,
    variant_id: uuid.UUID,
    business_date: date,
    quantity: int,
    order_id: uuid.UUID | None = None,
    conversation_id: uuid.UUID | None = None,
    expires_at: datetime | None = None,
) -> bool:
    """Reserve stock for an unpaid order. False if not enough is available.

    Updates daily_stock.held and creates a record in stock_holds as the source of truth.
    """
    applied = await _apply(
        session,
        variant_id,
        business_date,
        condition=DailyStock.available >= quantity,
        held=DailyStock.held + quantity,
    )
    if not applied:
        return False

    hold_row = StockHold(
        variant_id=variant_id,
        conversation_id=conversation_id,
        order_id=order_id,
        quantity=quantity,
        status="held",
        expires_at=expires_at or (datetime.now(UTC) + timedelta(minutes=15)),
    )
    session.add(hold_row)
    return True


async def release(
    session: AsyncSession,
    *,
    variant_id: uuid.UUID,
    business_date: date,
    quantity: int,
    order_id: uuid.UUID | None = None,
    status: str = "released",
) -> bool:
    """Give held stock back (the order expired or was cancelled before payment)."""
    applied = await _apply(
        session,
        variant_id,
        business_date,
        condition=DailyStock.held >= quantity,
        held=DailyStock.held - quantity,
    )
    if applied and order_id is not None:
        await session.execute(
            update(StockHold)
            .where(
                StockHold.order_id == order_id,
                StockHold.variant_id == variant_id,
                StockHold.status == "held",
            )
            .values(status=status)
        )
    return applied


async def confirm_sale(
    session: AsyncSession,
    *,
    variant_id: uuid.UUID,
    business_date: date,
    quantity: int,
    order_id: uuid.UUID | None = None,
) -> bool:
    """Turn held stock into sold stock (the order was paid)."""
    applied = await _apply(
        session,
        variant_id,
        business_date,
        condition=DailyStock.held >= quantity,
        held=DailyStock.held - quantity,
        sold=DailyStock.sold + quantity,
    )
    if applied and order_id is not None:
        await session.execute(
            update(StockHold)
            .where(
                StockHold.order_id == order_id,
                StockHold.variant_id == variant_id,
                StockHold.status == "held",
            )
            .values(status="converted")
        )
    return applied


async def release_expired_holds(
    session: AsyncSession,
    *,
    now: datetime | None = None,
    business_date: date | None = None,
) -> list[uuid.UUID]:
    """Sweep stock_holds for expired records, decrement daily_stock.held, and mark status='expired'.

    Returns the list of affected order_ids.
    """
    cutoff = now or datetime.now(UTC)
    expired_holds = list(
        await session.scalars(
            select(StockHold)
            .where(
                StockHold.status == "held",
                StockHold.expires_at < cutoff,
            )
            .with_for_update(skip_locked=True)
        )
    )
    affected_order_ids: list[uuid.UUID] = []
    b_date = business_date or cutoff.date()
    for hold_rec in expired_holds:
        await _apply(
            session,
            hold_rec.variant_id,
            b_date,
            condition=DailyStock.held >= hold_rec.quantity,
            held=DailyStock.held - hold_rec.quantity,
        )
        hold_rec.status = "expired"
        if hold_rec.order_id is not None:
            affected_order_ids.append(hold_rec.order_id)
    return affected_order_ids


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


async def restock(
    session: AsyncSession,
    *,
    variant_id: uuid.UUID,
    business_date: date,
    quantity: int,
) -> bool:
    """Add extra inventory for an item during the day (e.g. fresh afternoon bake).

    Increments `DailyStock.restocked` by `quantity`. In the daily stock formula:
        available = opening + restocked - held - sold - counter_sales
    this immediately increases available stock for customer orders.

    Args:
        session: Active asynchronous database session.
        variant_id: ID of the product variant being restocked.
        business_date: The merchant's current business date.
        quantity: Number of new units to add to stock (must be > 0).

    Returns:
        True if the stock record was updated.

    Raises:
        ValueError: If quantity <= 0.
        LookupError: If no daily stock record exists for the variant on this business date.
    """
    if quantity <= 0:
        raise ValueError(f"Restock quantity must be positive, got {quantity}")

    updated = await session.scalar(
        update(DailyStock)
        .where(
            DailyStock.variant_id == variant_id,
            DailyStock.business_date == business_date,
        )
        .values(restocked=DailyStock.restocked + quantity)
        .returning(DailyStock.id)
    )
    if updated is not None:
        return True

    # If 0 rows updated, verify whether the record exists
    stock = await session.scalar(
        select(DailyStock.id).where(
            DailyStock.variant_id == variant_id,
            DailyStock.business_date == business_date,
        )
    )
    if stock is None:
        raise LookupError(f"No stock record found for variant {variant_id} on {business_date}")
    return False


async def record_counter_sale(
    session: AsyncSession,
    *,
    variant_id: uuid.UUID,
    business_date: date,
    quantity: int,
) -> int:
    """Record an in-person, walk-in counter sale on the daily stock ledger.

    Atomically increments counter_sales if available >= quantity, returning
    the new remaining available count.

    This reflects the database procedure `record_counter_sale(p_variant_id, p_quantity)`:
    deducts stock from online AI availability so home bakers and boutique shops never double-sell
    items sold over the physical shop counter.

    Args:
        session: Active asynchronous database session.
        variant_id: ID of the product variant sold at the counter.
        business_date: The merchant's current business date.
        quantity: Number of units sold (must be > 0).

    Returns:
        The updated remaining available count.

    Raises:
        ValueError: If quantity <= 0.
        LookupError: If no daily stock record exists for the variant on this business date.
        StockConflict: If requested quantity exceeds currently available units.
    """
    if quantity <= 0:
        raise ValueError(f"Counter sale quantity must be positive, got {quantity}")

    new_available = await session.scalar(
        update(DailyStock)
        .where(
            DailyStock.variant_id == variant_id,
            DailyStock.business_date == business_date,
            DailyStock.available >= quantity,
        )
        .values(counter_sales=DailyStock.counter_sales + quantity)
        .returning(DailyStock.available)
    )
    if new_available is not None:
        return new_available

    # Condition failed or row doesn't exist; inspect state to return clear error
    stock = await session.scalar(
        select(DailyStock).where(
            DailyStock.variant_id == variant_id,
            DailyStock.business_date == business_date,
        )
    )
    if stock is None:
        raise LookupError(f"No stock record found for variant {variant_id} on {business_date}")
    raise StockConflict(
        f"Cannot record counter sale of {quantity}: only {stock.available} available"
    )


async def mark_sold_out(
    session: AsyncSession,
    *,
    variant_id: uuid.UUID,
    business_date: date,
) -> bool:
    """Mark a variant as sold out for the day.

    Absorbs any remaining available stock into counter_sales so available becomes 0,
    leaving held and sold orders untouched.

    Args:
        session: Active asynchronous database session.
        variant_id: ID of the product variant to mark sold out.
        business_date: The merchant's current business date.

    Returns:
        True if the variant is marked sold out (or was already sold out).

    Raises:
        LookupError: If no daily stock record exists for the variant on this business date.
    """
    # Atomically set counter_sales = opening + restocked - held - sold where available > 0
    # In PostgreSQL's generated column, this exactly produces available = 0
    updated = await session.scalar(
        update(DailyStock)
        .where(
            DailyStock.variant_id == variant_id,
            DailyStock.business_date == business_date,
            DailyStock.available > 0,
        )
        .values(
            counter_sales=DailyStock.opening
            + DailyStock.restocked
            - DailyStock.held
            - DailyStock.sold
        )
        .returning(DailyStock.id)
    )
    if updated is not None:
        return True

    # If 0 rows updated, verify whether the record exists or was already 0 available
    stock = await session.scalar(
        select(DailyStock.id).where(
            DailyStock.variant_id == variant_id,
            DailyStock.business_date == business_date,
        )
    )
    if stock is None:
        raise LookupError(f"No stock record found for variant {variant_id} on {business_date}")
    return True


_PATTERN_QTY_FIRST = re.compile(
    r"^(\d+)\s*(?:pcs|nos|qty|x)?\s+(.+?)\s+(?:@\s+|for\s+)?(?:rs\.?|inr|₹|\$|usd|€|eur|£|gbp)?\s*(\d+(?:\.\d{1,2})?)\s*(?:rs\.?|inr|/-)?$",
    re.IGNORECASE,
)
_PATTERN_PROD_FIRST = re.compile(
    r"^(.+?)(?:\s*[:\-,]\s*|\s+)(?:qty\s+|x\s*)?(\d+)\s*(?:pcs|nos|qty)?\s*(?:[:\-,@]\s*|\s+)(?:@\s+|for\s+)?(?:rs\.?|inr|₹|\$|usd|€|eur|£|gbp)?\s*(\d+(?:\.\d{1,2})?)\s*(?:rs\.?|inr|/-)?$",
    re.IGNORECASE,
)
_PATTERN_PRICE_FIRST = re.compile(
    r"^(.+?)(?:\s*[:\-,]\s*|\s+)(?:@\s+|for\s+)?(?:rs\.?|inr|₹|\$|usd|€|eur|£|gbp)\s*(\d+(?:\.\d{1,2})?)\s*(?:rs\.?|inr|/-)?\s*(?:[:\-,]\s*|\s+)(?:qty\s+|x\s*)?(\d+)\s*(?:pcs|nos|qty)?$",
    re.IGNORECASE,
)


def _detect_currency(text_sample: str, default_currency: str = "INR") -> str:
    lower = text_sample.lower()
    if "$" in lower or "usd" in lower:
        return "USD"
    if "€" in lower or "eur" in lower:
        return "EUR"
    if "£" in lower or "gbp" in lower:
        return "GBP"
    if "₹" in lower or "rs" in lower or "inr" in lower:
        return "INR"
    return default_currency.upper()


def _extract_product_variant(raw_name: str) -> tuple[str, str | None]:
    cleaned = raw_name.strip().strip("-:,").strip()
    match_paren = re.match(r"^([^(]+)\s*\(([^)]+)\)$", cleaned)
    if match_paren:
        return match_paren.group(1).strip(), match_paren.group(2).strip()
    if " - " in cleaned:
        parts = cleaned.split(" - ", 1)
        return parts[0].strip(), parts[1].strip()
    return cleaned, None


def parse_stock_text(text: str, default_currency: str = "INR") -> list[OpeningStockLine]:
    """Parse a free-form text stock update into structured OpeningStockLine items.

    Supports multi-line text, comma-separated items, and common merchant typing styles:
      - '10 choc cookies 60rs, 5 brownies 90'
      - '10 Scoop cookie (Chocolate) 60'
      - 'Brownie: 10 @ 90'
      - 'Croissant - 8 pcs - 120 INR'
      - '4 Gift box $12.50'

    Args:
        text: Raw natural language text provided by the merchant.
        default_currency: Fallback 3-letter currency code (defaults to 'INR').

    Returns:
        List of parsed OpeningStockLine items ready for `set_opening_stock`.

    Raises:
        ValueError: If text is empty or any line cannot be parsed.
    """
    stripped_text = text.strip()
    if not stripped_text:
        raise ValueError("Stock text cannot be empty")

    raw_lines = [
        line.strip()
        for line in stripped_text.splitlines()
        if line.strip() and not line.strip().startswith(("#", "//"))
    ]
    if not raw_lines:
        raise ValueError("Stock text contains no valid stock items")

    # Expand lines that contain multiple comma-separated items
    item_strings: list[str] = []
    for line in raw_lines:
        if "," in line:
            parts = [p.strip() for p in line.split(",") if p.strip()]
            # If multiple parts and each part has both digits and alphabetical characters,
            # it's a comma-separated list of items (e.g. "10 choc cookies 60rs, 5 brownies 90")
            if len(parts) > 1 and all(
                re.search(r"\d", p) and re.search(r"[a-zA-Z]", p) for p in parts
            ):
                item_strings.extend(parts)
                continue
        item_strings.append(line)

    results: list[OpeningStockLine] = []
    for idx, item_str in enumerate(item_strings, start=1):
        currency = _detect_currency(item_str, default_currency)

        match_qty = _PATTERN_QTY_FIRST.match(item_str)
        match_prod = _PATTERN_PROD_FIRST.match(item_str)
        match_price = _PATTERN_PRICE_FIRST.match(item_str)

        raw_prod: str
        qty_str: str
        price_str: str

        if match_qty:
            qty_str, raw_prod, price_str = match_qty.groups()
        elif match_prod:
            raw_prod, qty_str, price_str = match_prod.groups()
        elif match_price:
            raw_prod, price_str, qty_str = match_price.groups()
        else:
            raise ValueError(
                f"Could not parse stock line {idx}: '{item_str}'. "
                "Expected format: '<quantity> <product> <price>' or "
                "'<product>: <quantity> @ <price>'"
            )

        try:
            quantity = int(qty_str)
            if quantity < 0:
                raise ValueError("Quantity cannot be negative")
        except ValueError as exc:
            raise ValueError(
                f"Invalid quantity '{qty_str}' on line {idx}: must be non-negative integer"
            ) from exc

        try:
            price_dec = Decimal(price_str)
            if price_dec < 0:
                raise ValueError("Price cannot be negative")
            price_minor = int((price_dec * 100).to_integral_value())
        except (InvalidOperation, ValueError) as exc:
            raise ValueError(f"Invalid price '{price_str}' on line {idx}") from exc

        product, variant = _extract_product_variant(raw_prod)
        if not product:
            raise ValueError(f"Missing product name on line {idx}: '{item_str}'")

        results.append(
            OpeningStockLine(
                product=product,
                variant=variant,
                price_minor=price_minor,
                quantity=quantity,
                currency=currency,
            )
        )

    return results


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


async def get_yesterday_leftovers(
    session: AsyncSession, merchant_id: uuid.UUID, business_date: date
) -> list[YesterdayLeftover]:
    """Retrieve unsold stock from yesterday (available > 0) with stock_mode and shelf life."""
    yesterday = business_date - timedelta(days=1)
    stocks = {
        s.variant_id: s
        for s in await session.scalars(
            select(DailyStock).where(
                DailyStock.merchant_id == merchant_id,
                DailyStock.business_date == yesterday,
                DailyStock.available > 0,
            )
        )
    }
    variants = await catalog.list_variants_by_ids(
        session, merchant_id, stocks.keys(), active_only=True
    )
    return [
        YesterdayLeftover(
            variant_id=v.variant_id,
            product=v.product_name,
            variant=v.variant_name,
            price_minor=v.price_minor,
            currency=v.currency,
            leftover_quantity=stocks[v.variant_id].available,
            stock_mode=v.effective_stock_mode,
            shelf_life_days=v.effective_shelf_life_days,
        )
        for v in variants
    ]


async def apply_rollover_selection(
    session: AsyncSession,
    *,
    merchant_id: uuid.UUID,
    business_date: date,
    selections: list[RolloverItemSelection],
) -> int:
    """Apply customized rollover: add chosen leftover quantities to today's opening stock."""
    yesterday = business_date - timedelta(days=1)
    applied_count = 0

    for item in selections:
        if item.rollover_quantity <= 0:
            continue

        # Validate that leftover actually had at least rollover_quantity available yesterday
        yesterday_stock = await session.scalar(
            select(DailyStock.available).where(
                DailyStock.merchant_id == merchant_id,
                DailyStock.variant_id == item.variant_id,
                DailyStock.business_date == yesterday,
            )
        )
        if yesterday_stock is None or yesterday_stock < item.rollover_quantity:
            available_qty = yesterday_stock or 0
            raise StockConflict(
                f"Cannot roll over {item.rollover_quantity} units: "
                f"yesterday only had {available_qty} available"
            )

        statement = pg_insert(DailyStock).values(
            merchant_id=merchant_id,
            variant_id=item.variant_id,
            business_date=business_date,
            opening=item.rollover_quantity,
        )
        await session.execute(
            statement.on_conflict_do_update(
                index_elements=[DailyStock.variant_id, DailyStock.business_date],
                set_={"opening": DailyStock.opening + statement.excluded.opening},
            )
        )
        applied_count += 1

    return applied_count


async def execute_nightly_rollover(
    session: AsyncSession,
    *,
    merchant_id: uuid.UUID,
    from_date: date,
    to_date: date,
) -> int:
    """Call stored procedure rollover_daily_stock to roll forward perpetual/multi-day stock."""
    result = await session.scalar(
        text("SELECT rollover_daily_stock(:merchant_id, :from_date, :to_date)").bindparams(
            merchant_id=merchant_id,
            from_date=from_date,
            to_date=to_date,
        )
    )
    return int(result or 0)
