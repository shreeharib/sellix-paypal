"""Public interface of the inventory module: the daily stock ledger.

Every change is one conditional UPDATE on the variant's row for the day, so concurrent orders
can never take stock below zero (the table's check constraint is the last line of defence).
"""

import re
import uuid
from datetime import date
from decimal import Decimal, InvalidOperation

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
