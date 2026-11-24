"""Public interface of the inventory module: the daily stock ledger.

Every change is one conditional UPDATE on the variant's row for the day, so concurrent orders
can never take stock below zero (the table's check constraint is the last line of defence).

How an item is counted is its stock mode (shop_types.yaml lists the four):
- `daily`: a fresh count each day (a row per day; leftovers carry only if the merchant says so).
- `inventory`: kept until sold. The first read of a new day carries the latest earlier day's
  remainder forward (`carry_forward`), so a closed day loses nothing.
- `made_to_order` and `unlimited`: no count. Always on sale, up to NO_COUNT_LINE_LIMIT a line,
  with no row needed, no hold and no daily_stock change when ordered.
"""

import re
import uuid
from datetime import UTC, date, datetime, timedelta
from decimal import Decimal, InvalidOperation

from sqlalchemy import ColumnElement, Date, exists, literal, select, text, update
from sqlalchemy.dialects.postgresql import distinct_on
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import aliased

from app.modules.catalog import service as catalog
from app.modules.inventory.models import DailyStock, StockHold
from app.modules.inventory.schemas import (
    LedgerRow,
    OpeningStockLine,
    RolloverItemSelection,
    StockItem,
    YesterdayLeftover,
)
from app.modules.merchants import service as merchants

KEPT_MODE = "inventory"
NO_COUNT_MODES = ("made_to_order", "unlimited")
# The most of a no-count item one order line can take; also its `available` in every list.
NO_COUNT_LINE_LIMIT = 99


class StockConflict(ValueError):
    """The change would make stock negative (more promised than made)."""


def is_counted(stock_mode: str) -> bool:
    """Whether orders hold and sell this mode's stock from the daily ledger."""
    return stock_mode not in NO_COUNT_MODES


async def _rows(
    session: AsyncSession, merchant_id: uuid.UUID, business_date: date
) -> dict[uuid.UUID, DailyStock]:
    return {
        s.variant_id: s
        for s in await session.scalars(
            select(DailyStock).where(
                DailyStock.merchant_id == merchant_id,
                DailyStock.business_date == business_date,
            )
        )
    }


async def carry_forward(session: AsyncSession, merchant_id: uuid.UUID, business_date: date) -> int:
    """Start each kept-until-sold item's day with what its latest earlier day had left.

    Only for the shop's current day (a coming day would count the same units twice), and only
    for items with no row yet that day: the merchant's own count wins, and later reads do
    nothing. Two first reads at once carry once: each item gets one row a day (the unique
    (variant, day) key; the second insert waits for the first, then does nothing).
    Returns how many items were carried.
    """
    merchant = await merchants.get_merchant(session, merchant_id)
    if business_date != merchants.business_date(merchant):
        return 0
    kept = [
        v.variant_id
        for v in await catalog.list_variants_by_ids(
            session, merchant_id, (), active_only=True, also_modes=(KEPT_MODE,)
        )
    ]
    if not kept:
        return 0
    that_day = aliased(DailyStock)
    latest = (
        select(
            DailyStock.merchant_id,
            DailyStock.variant_id,
            literal(business_date, Date),
            DailyStock.available,
        )
        .where(
            DailyStock.merchant_id == merchant_id,
            DailyStock.variant_id.in_(kept),
            DailyStock.business_date < business_date,
            ~exists().where(
                that_day.variant_id == DailyStock.variant_id,
                that_day.business_date == business_date,
            ),
        )
        .ext(distinct_on(DailyStock.variant_id))
        .order_by(DailyStock.variant_id, DailyStock.business_date.desc())
    )
    carried = await session.scalars(
        pg_insert(DailyStock)
        .from_select(["merchant_id", "variant_id", "business_date", "opening"], latest)
        .on_conflict_do_nothing(index_elements=[DailyStock.variant_id, DailyStock.business_date])
        .returning(DailyStock.id)
    )
    return len(list(carried))


async def day_ledger(
    session: AsyncSession, merchant_id: uuid.UUID, business_date: date
) -> list[LedgerRow]:
    """Every active item's stock for the day: opening, restocked, held, sold, counter, left.

    No-count items are listed every day, `available` NO_COUNT_LINE_LIMIT (their `stock_mode`
    says they aren't counted). Removed products are left out.
    """
    await carry_forward(session, merchant_id, business_date)
    stocks = await _rows(session, merchant_id, business_date)
    variants = await catalog.list_variants_by_ids(
        session, merchant_id, stocks.keys(), active_only=True, also_modes=NO_COUNT_MODES
    )
    ledger: list[LedgerRow] = []
    for v in variants:
        row = stocks.get(v.variant_id)
        counted = is_counted(v.effective_stock_mode)
        ledger.append(
            LedgerRow(
                variant_id=v.variant_id,
                product=v.product_name,
                variant=v.variant_name,
                price_minor=v.price_minor,
                currency=v.currency,
                opening=row.opening if row else 0,
                restocked=row.restocked if row else 0,
                held=row.held if row else 0,
                sold=row.sold if row else 0,
                counter_sales=row.counter_sales if row else 0,
                available=(row.available if row else 0) if counted else NO_COUNT_LINE_LIMIT,
                stock_mode=v.effective_stock_mode,
                shelf_life_days=v.effective_shelf_life_days,
            )
        )
    return ledger


async def today_stock(
    session: AsyncSession,
    merchant_id: uuid.UUID,
    business_date: date,
    *,
    ordering_today: date | None = None,
) -> list[StockItem]:
    """What can be sold on the day: counted items with stock set for it, and every no-count
    item (`available` NO_COUNT_LINE_LIMIT). Kept-until-sold stock is carried forward first.

    `ordering_today`: for customers' menus, the shop's local date now. Items customers can't
    order for `business_date` (sold on another day, or past their last order date) are left out;
    leave it None for the merchant's own views.
    """
    await carry_forward(session, merchant_id, business_date)
    return await _day_items(
        session, merchant_id, business_date, ordering_today=ordering_today, every_no_count=True
    )


async def _day_items(
    session: AsyncSession,
    merchant_id: uuid.UUID,
    business_date: date,
    *,
    ordering_today: date | None,
    every_no_count: bool,
) -> list[StockItem]:
    """The day's items; no-count items only if they have a row that day, or `every_no_count`."""
    stocks = await _rows(session, merchant_id, business_date)
    variants = await catalog.list_variants_by_ids(
        session,
        merchant_id,
        stocks.keys(),
        active_only=True,
        also_modes=NO_COUNT_MODES if every_no_count else (),
    )
    if ordering_today is not None:
        variants = [
            v for v in variants if v.ordering_problem(business_date, ordering_today) is None
        ]
    items: list[StockItem] = []
    for v in variants:
        row = stocks.get(v.variant_id)
        counted = is_counted(v.effective_stock_mode)
        items.append(
            StockItem(
                product=v.product_name,
                variant=v.variant_name,
                price_minor=v.price_minor,
                currency=v.currency,
                available=(row.available if row else 0) if counted else NO_COUNT_LINE_LIMIT,
                variant_id=v.variant_id,
                opening=row.opening if row and counted else 0,
                stock_mode=v.effective_stock_mode,
                shelf_life_days=v.effective_shelf_life_days,
                available_on=v.available_on,
                order_by_date=v.order_by_date,
            )
        )
    return items


async def upcoming_stock(
    session: AsyncSession,
    merchant_id: uuid.UUID,
    after: date,
    days: int,
    *,
    ordering_today: date | None = None,
) -> dict[date, list[StockItem]]:
    """Stock the merchant has set for the days after `after` (pre-orders), by day.

    Only what was set for each day: no-count items appear on a day they have a row for (as
    available), not on every coming day. Nothing is carried forward into coming days.
    `ordering_today`: as in `today_stock`; days left with no orderable item are dropped.
    """
    dates = await session.scalars(
        select(DailyStock.business_date)
        .where(
            DailyStock.merchant_id == merchant_id,
            DailyStock.business_date > after,
            DailyStock.business_date <= after + timedelta(days=days),
        )
        .distinct()
        .order_by(DailyStock.business_date)
    )
    by_day = {
        day: await _day_items(
            session, merchant_id, day, ordering_today=ordering_today, every_no_count=False
        )
        for day in list(dates)
    }
    return {day: items for day, items in by_day.items() if items or ordering_today is None}


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
            stock_mode=line.stock_mode,
            shelf_life_days=line.shelf_life_days,
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
    if applied:
        await _onto_todays_shelf(session, variant_id, business_date, quantity)
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
) -> int:
    """Give back expired holds that belong to no order, and mark them 'expired'. Returns how many.

    An order's holds are released with the order (orders.expire_due, cancel, payment), under
    the order's row lock. Sweeping them here as well released them twice when an order was
    locked by a payment, or past expire_due's batch, and locked rows crosswise with another
    copy of the expiry job (a deadlock). Rows are taken in variant order.
    """
    cutoff = now or datetime.now(UTC)
    expired_holds = list(
        await session.scalars(
            select(StockHold)
            .where(
                StockHold.status == "held",
                StockHold.expires_at < cutoff,
                StockHold.order_id.is_(None),
            )
            .order_by(StockHold.variant_id, StockHold.id)
            .with_for_update(skip_locked=True)
        )
    )
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
    return len(expired_holds)


async def unsell(
    session: AsyncSession, *, variant_id: uuid.UUID, business_date: date, quantity: int
) -> bool:
    """Put sold stock back on sale (a paid order was refunded with its items restocked)."""
    applied = await _apply(
        session,
        variant_id,
        business_date,
        condition=DailyStock.sold >= quantity,
        sold=DailyStock.sold - quantity,
    )
    if applied:
        await _onto_todays_shelf(session, variant_id, business_date, quantity)
    return applied


async def _onto_todays_shelf(
    session: AsyncSession, variant_id: uuid.UUID, business_date: date, quantity: int
) -> None:
    """Kept-until-sold units given back on an earlier day's row belong on today's shelf.

    Today's row was carried from the earlier day's remainder when it was first read, so units
    released there afterwards (a hold that ran out after midnight, a refund days later) would
    never be on sale again. They are added to today's row as restocked. If today has no row yet,
    the carry will count them, so nothing is moved. (The earlier day's row keeps them too; no
    carry reads it again once a later row exists.)
    """
    old = await session.scalar(
        select(DailyStock).where(
            DailyStock.variant_id == variant_id, DailyStock.business_date == business_date
        )
    )
    if old is None:
        return
    merchant = await merchants.get_merchant(session, old.merchant_id)
    today = merchants.business_date(merchant)
    if business_date >= today:
        return
    found = await catalog.list_variants_by_ids(session, old.merchant_id, (variant_id,))
    if not found or found[0].effective_stock_mode != KEPT_MODE:
        return
    await session.execute(
        update(DailyStock)
        .where(DailyStock.variant_id == variant_id, DailyStock.business_date == today)
        .values(restocked=DailyStock.restocked + quantity)
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


async def _row_or_missing(
    session: AsyncSession, merchant_id: uuid.UUID, variant_id: uuid.UUID, business_date: date
) -> DailyStock:
    """The shop's row for the item and day; LookupError if it has none (or the id is another
    shop's: every merchant write is scoped to the merchant, never to the id alone)."""
    stock = await session.scalar(
        select(DailyStock).where(
            DailyStock.merchant_id == merchant_id,
            DailyStock.variant_id == variant_id,
            DailyStock.business_date == business_date,
        )
    )
    if stock is None:
        raise LookupError(f"No stock record found for variant {variant_id} on {business_date}")
    return stock


async def restock(
    session: AsyncSession,
    *,
    merchant_id: uuid.UUID,
    variant_id: uuid.UUID,
    business_date: date,
    quantity: int,
) -> bool:
    """Add extra stock for one of the shop's items during the day (a fresh afternoon batch).

    Raises ValueError if `quantity` isn't positive, LookupError if the shop has no stock row
    for the item that day (another shop's item counts as missing).
    """
    if quantity <= 0:
        raise ValueError(f"Restock quantity must be positive, got {quantity}")
    await carry_forward(session, merchant_id, business_date)
    updated = await session.scalar(
        update(DailyStock)
        .where(
            DailyStock.merchant_id == merchant_id,
            DailyStock.variant_id == variant_id,
            DailyStock.business_date == business_date,
        )
        .values(restocked=DailyStock.restocked + quantity)
        .returning(DailyStock.id)
    )
    if updated is not None:
        return True
    await _row_or_missing(session, merchant_id, variant_id, business_date)
    return False


async def record_counter_sale(
    session: AsyncSession,
    *,
    merchant_id: uuid.UUID,
    variant_id: uuid.UUID,
    business_date: date,
    quantity: int,
) -> int:
    """Record a walk-in sale of one of the shop's items, so it isn't sold online twice.

    Returns what is left. Raises ValueError if `quantity` isn't positive, LookupError if the
    shop has no stock row for the item that day, StockConflict if fewer are left.
    """
    if quantity <= 0:
        raise ValueError(f"Counter sale quantity must be positive, got {quantity}")
    await carry_forward(session, merchant_id, business_date)
    new_available = await session.scalar(
        update(DailyStock)
        .where(
            DailyStock.merchant_id == merchant_id,
            DailyStock.variant_id == variant_id,
            DailyStock.business_date == business_date,
            DailyStock.available >= quantity,
        )
        .values(counter_sales=DailyStock.counter_sales + quantity)
        .returning(DailyStock.available)
    )
    if new_available is not None:
        return new_available
    stock = await _row_or_missing(session, merchant_id, variant_id, business_date)
    raise StockConflict(
        f"Cannot record counter sale of {quantity}: only {stock.available} available"
    )


async def mark_sold_out(
    session: AsyncSession,
    *,
    merchant_id: uuid.UUID,
    variant_id: uuid.UUID,
    business_date: date,
) -> bool:
    """Mark one of the shop's items sold out for the day: what's left moves into counter sales
    (held and sold stay as they are). True also when it was already sold out.

    Raises LookupError if the shop has no stock row for the item that day.
    """
    await carry_forward(session, merchant_id, business_date)
    # counter_sales = opening + restocked - held - sold makes the generated `available` 0.
    updated = await session.scalar(
        update(DailyStock)
        .where(
            DailyStock.merchant_id == merchant_id,
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
    if updated is None:
        await _row_or_missing(session, merchant_id, variant_id, business_date)
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
    """Yesterday's unsold daily batches (available > 0), with stock mode and shelf life.

    Kept-until-sold items aren't offered: they carry over by themselves (`carry_forward`), and
    carrying them again would count them twice. No-count items have nothing to carry.
    """
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
        if v.effective_stock_mode not in (KEPT_MODE, *NO_COUNT_MODES)
    ]


async def apply_rollover_selection(
    session: AsyncSession,
    *,
    merchant_id: uuid.UUID,
    business_date: date,
    selections: list[RolloverItemSelection],
) -> int:
    """Add the merchant's chosen leftovers of yesterday's daily batches to today's opening stock.

    Raises LookupError for an item that isn't this shop's. Kept-until-sold and no-count items
    are skipped (they carry by themselves, or have no count), so an older app can't count them
    twice.
    """
    yesterday = business_date - timedelta(days=1)
    applied_count = 0
    modes = {
        v.variant_id: v.effective_stock_mode
        for v in await catalog.list_variants_by_ids(
            session, merchant_id, [item.variant_id for item in selections]
        )
    }
    for item in selections:
        if item.variant_id not in modes:
            raise LookupError(f"No product {item.variant_id} in this shop")

    for item in selections:
        if item.rollover_quantity <= 0 or modes[item.variant_id] in (KEPT_MODE, *NO_COUNT_MODES):
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
