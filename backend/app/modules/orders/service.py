"""Public interface of the orders module: quotes, placing orders, payment and expiry.

Order states: awaiting_payment -> paid (-> completed / refunded), or awaiting_payment ->
expired / cancelled. Every change is written to order_events.
"""

import uuid
from collections import defaultdict
from datetime import UTC, date, datetime, timedelta
from typing import Literal

from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.catalog import service as catalog
from app.modules.inventory import service as inventory
from app.modules.inventory.schemas import StockItem
from app.modules.orders import matching
from app.modules.orders.models import Order, OrderEvent, OrderItem, SavedQuote
from app.modules.orders.schemas import (
    DaySummary,
    ExpiredOrder,
    OrderItemSummary,
    OrderLineRequest,
    OrderRequest,
    OrderState,
    OrderSummary,
    PaymentOutcome,
    PaymentResult,
    PlacedOrder,
    Quote,
    QuoteLine,
    StoredQuote,
)


class OrderProblem(ValueError):
    """The order can't be placed; `problems` are safe to tell the customer."""

    def __init__(self, problems: tuple[str, ...]) -> None:
        super().__init__("; ".join(problems))
        self.problems = problems


class QuoteAlreadyPlaced(Exception):
    def __init__(self, order_id: uuid.UUID) -> None:
        super().__init__(f"The quote was already placed as order {order_id}")
        self.order_id = order_id


class _StockShortfall(Exception):
    pass


async def quote(
    session: AsyncSession, *, merchant_id: uuid.UUID, business_date: date, request: OrderRequest
) -> Quote:
    stock = await inventory.today_stock(session, merchant_id, business_date)
    aliases = await catalog.aliases(session, merchant_id)
    wanted: dict[uuid.UUID, int] = defaultdict(int)
    items: dict[uuid.UUID, StockItem] = {}
    problems: list[str] = []

    for line in request.lines:
        label = line.label
        if line.quantity < 1:
            problems.append(f"{label}: the quantity must be at least 1")
            continue
        if line.variant_id:
            matches = [item for item in stock if item.variant_id == line.variant_id]
        elif line.ref:
            matches = [item for item in stock if item.ref == line.ref.strip().lower()]
        else:
            matches = list(matching.find(stock, line.product, line.variant, aliases).items)
        if not matches:
            problems.append(f"{label} isn't in today's stock")
        elif len(matches) > 1:
            if len({item.product for item in matches}) == 1:
                variants = ", ".join(item.variant or "plain" for item in matches)
                problems.append(f"{matches[0].product} comes in {variants}: ask which one")
            else:
                options = ", ".join(item.label for item in matches)
                problems.append(f'"{label}" could be {options}: ask which one')
        elif matches[0].variant_id is not None:
            items[matches[0].variant_id] = matches[0]
            wanted[matches[0].variant_id] += line.quantity

    lines: list[QuoteLine] = []
    for variant_id, quantity in wanted.items():
        item = items[variant_id]
        if item.available < quantity:
            problems.append(
                f"{item.label}: only {item.available} left"
                if item.available
                else f"{item.label} is sold out"
            )
            continue
        lines.append(
            QuoteLine(
                variant_id=variant_id,
                label=item.label,
                product=item.product,
                variant=item.variant,
                unit_price_minor=item.price_minor,
                currency=item.currency,
                quantity=quantity,
            )
        )

    currencies = {line.currency for line in lines}
    if len(currencies) > 1:
        problems.append(
            "These items are priced in different currencies, so they need separate orders"
        )
    return Quote(
        lines=tuple(lines),
        currency=next(iter(currencies)) if len(currencies) == 1 else None,
        total_minor=sum(line.subtotal_minor for line in lines),
        problems=tuple(problems),
    )


async def place_order(
    session: AsyncSession,
    *,
    merchant_id: uuid.UUID,
    customer_id: uuid.UUID,
    conversation_id: uuid.UUID | None,
    business_date: date,
    request: OrderRequest,
    hold_minutes: int,
    expected_total_minor: int | None = None,
) -> PlacedOrder:
    """Hold the stock and create the order, all or nothing (the caller's transaction).

    With `expected_total_minor` (the total the customer was shown), a changed price stops it.
    """
    offer = await quote(
        session, merchant_id=merchant_id, business_date=business_date, request=request
    )
    if not offer.ok or offer.currency is None:
        raise OrderProblem(offer.problems or ("The order has no items",))
    if expected_total_minor is not None and offer.total_minor != expected_total_minor:
        raise OrderProblem(("Prices have changed since the quote, so it needs a new quote",))
    for line in offer.lines:
        held = await inventory.hold(
            session, variant_id=line.variant_id, business_date=business_date, quantity=line.quantity
        )
        if not held:
            raise OrderProblem((f"{line.label} just sold out",))

    order = Order(
        merchant_id=merchant_id,
        customer_id=customer_id,
        conversation_id=conversation_id,
        status="awaiting_payment",
        business_date=business_date,
        currency=offer.currency,
        total_minor=offer.total_minor,
        fulfilment=request.fulfilment,
        delivery_address=request.delivery_address,
        needed_by=request.needed_by,
        notes=request.notes,
        hold_expires_at=datetime.now(UTC) + timedelta(minutes=hold_minutes),
    )
    session.add(order)
    await session.flush()
    session.add_all(
        OrderItem(
            merchant_id=merchant_id,
            order_id=order.id,
            variant_id=line.variant_id,
            product_name=line.product,
            variant_name=line.variant,
            unit_price_minor=line.unit_price_minor,
            quantity=line.quantity,
        )
        for line in offer.lines
    )
    _log(session, order, "placed", None, "awaiting_payment", "agent")
    await session.flush()
    return PlacedOrder(
        order_id=order.id,
        number=order.number,
        currency=order.currency,
        total_minor=order.total_minor,
        hold_minutes=hold_minutes,
    )


async def save_quote(
    session: AsyncSession,
    *,
    merchant_id: uuid.UUID,
    conversation_id: uuid.UUID,
    offer: Quote,
    request: OrderRequest,
) -> StoredQuote:
    """Store a quote the customer will be asked to confirm; earlier open ones are superseded."""
    if not offer.ok or offer.currency is None:
        raise ValueError("Only a quote without problems can be saved")
    await supersede_quotes(session, conversation_id)
    saved = SavedQuote(
        merchant_id=merchant_id,
        conversation_id=conversation_id,
        lines=[
            {
                "variant_id": str(line.variant_id),
                "label": line.label,
                "product": line.product,
                "variant": line.variant,
                "unit_price_minor": line.unit_price_minor,
                "quantity": line.quantity,
            }
            for line in offer.lines
        ],
        currency=offer.currency,
        total_minor=offer.total_minor,
        fulfilment=request.fulfilment,
        delivery_address=request.delivery_address,
        needed_by=request.needed_by,
        notes=request.notes,
    )
    session.add(saved)
    await session.flush()
    await session.refresh(saved)
    return _stored(saved)


async def supersede_quotes(session: AsyncSession, conversation_id: uuid.UUID) -> None:
    """The customer's order changed: no earlier quote can be placed any more."""
    await session.execute(
        update(SavedQuote)
        .where(SavedQuote.conversation_id == conversation_id, SavedQuote.status == "open")
        .values(status="superseded")
    )


async def get_quote(session: AsyncSession, quote_id: uuid.UUID) -> StoredQuote | None:
    saved = await session.get(SavedQuote, quote_id)
    return _stored(saved) if saved else None


async def place_quote(
    session: AsyncSession,
    *,
    quote_id: uuid.UUID,
    customer_id: uuid.UUID,
    business_date: date,
    hold_minutes: int,
) -> PlacedOrder:
    """Place the order a customer confirmed, exactly as quoted. Once only: a quote that was
    already placed raises QuoteAlreadyPlaced."""
    saved = await session.scalar(
        select(SavedQuote).where(SavedQuote.id == quote_id).with_for_update()
    )
    if saved is None:
        raise LookupError(f"No quote {quote_id}")
    if saved.status == "placed" and saved.order_id is not None:
        raise QuoteAlreadyPlaced(saved.order_id)
    if saved.status != "open":
        raise OrderProblem(("This quote was replaced by a newer one",))
    quoted = _stored(saved)
    placed = await place_order(
        session,
        merchant_id=saved.merchant_id,
        customer_id=customer_id,
        conversation_id=saved.conversation_id,
        business_date=business_date,
        request=OrderRequest(
            lines=tuple(
                OrderLineRequest(
                    line.product, line.variant, line.quantity, variant_id=line.variant_id
                )
                for line in quoted.lines
            ),
            fulfilment=quoted.fulfilment,
            delivery_address=quoted.delivery_address,
            needed_by=quoted.needed_by,
            notes=quoted.notes,
        ),
        hold_minutes=hold_minutes,
        expected_total_minor=quoted.total_minor,
    )
    saved.status = "placed"
    saved.order_id = placed.order_id
    await session.flush()
    return placed


async def order_state(session: AsyncSession, order_id: uuid.UUID) -> OrderState | None:
    order = await session.get(Order, order_id)
    if order is None:
        return None
    return OrderState(
        order_id=order.id,
        number=order.number,
        status=order.status,
        currency=order.currency,
        total_minor=order.total_minor,
    )


def _stored(saved: SavedQuote) -> StoredQuote:
    return StoredQuote(
        id=saved.id,
        lines=tuple(
            QuoteLine(
                variant_id=uuid.UUID(line["variant_id"]),
                label=line["label"],
                product=line["product"],
                variant=line["variant"],
                unit_price_minor=line["unit_price_minor"],
                currency=saved.currency,
                quantity=line["quantity"],
            )
            for line in saved.lines
        ),
        currency=saved.currency,
        total_minor=saved.total_minor,
        fulfilment=_fulfilment(saved.fulfilment),
        delivery_address=saved.delivery_address,
        needed_by=saved.needed_by,
        notes=saved.notes,
        status=saved.status,
        order_id=saved.order_id,
        created_at=saved.created_at,
    )


def _fulfilment(value: str | None) -> Literal["pickup", "delivery"] | None:
    return value if value in ("pickup", "delivery") else None


async def record_payment(
    session: AsyncSession,
    order_id: uuid.UUID,
    *,
    amount_minor: int,
    currency: str,
    actor: str,
) -> PaymentResult:
    """Mark the order paid once the payment provider has confirmed the money."""
    order = await session.scalar(select(Order).where(Order.id == order_id).with_for_update())
    if order is None:
        raise LookupError(f"No order {order_id}")

    def result(outcome: PaymentOutcome) -> PaymentResult:
        return PaymentResult(
            order_id=order.id,
            number=order.number,
            merchant_id=order.merchant_id,
            conversation_id=order.conversation_id,
            currency=order.currency,
            total_minor=order.total_minor,
            outcome=outcome,
        )

    if order.status in ("paid", "completed", "refunded"):
        return result("already_paid")
    if (amount_minor, currency) != (order.total_minor, order.currency):
        _log(
            session,
            order,
            "amount_mismatch",
            order.status,
            order.status,
            actor,
            {"paid_minor": amount_minor, "paid_currency": currency},
        )
        return result("amount_mismatch")

    previous = order.status
    items = list(await session.scalars(select(OrderItem).where(OrderItem.order_id == order.id)))
    outcome: PaymentOutcome = "paid"
    if previous == "awaiting_payment":
        for item in items:
            if not await inventory.confirm_sale(
                session,
                variant_id=item.variant_id,
                business_date=order.business_date,
                quantity=item.quantity,
            ):
                raise RuntimeError(f"Held stock for order {order.id} is missing")
    else:
        # The hold had expired (or the order was cancelled): sell again if the stock is still there.
        try:
            async with session.begin_nested():
                for item in items:
                    if not await inventory.sell_unheld(
                        session,
                        variant_id=item.variant_id,
                        business_date=order.business_date,
                        quantity=item.quantity,
                    ):
                        raise _StockShortfall
        except _StockShortfall:
            outcome = "paid_stock_short"

    order.status = "paid"
    order.paid_at = datetime.now(UTC)
    order.hold_expires_at = None
    _log(session, order, outcome, previous, "paid", actor)
    return result(outcome)


async def expire_due(session: AsyncSession, *, now: datetime | None = None) -> list[ExpiredOrder]:
    """Release the stock of unpaid orders whose hold has run out."""
    due = list(
        await session.scalars(
            select(Order)
            .where(
                Order.status == "awaiting_payment",
                Order.hold_expires_at < (now or datetime.now(UTC)),
            )
            .order_by(Order.hold_expires_at)
            .limit(100)
            .with_for_update(skip_locked=True)
        )
    )
    expired: list[ExpiredOrder] = []
    for order in due:
        for item in await session.scalars(select(OrderItem).where(OrderItem.order_id == order.id)):
            await inventory.release(
                session,
                variant_id=item.variant_id,
                business_date=order.business_date,
                quantity=item.quantity,
            )
        order.status = "expired"
        order.hold_expires_at = None
        _log(session, order, "expired", "awaiting_payment", "expired", "system")
        expired.append(ExpiredOrder(order.id, order.number, order.conversation_id))
    return expired


def _log(
    session: AsyncSession,
    order: Order,
    event: str,
    from_status: str | None,
    to_status: str | None,
    actor: str,
    details: dict[str, object] | None = None,
) -> None:
    session.add(
        OrderEvent(
            merchant_id=order.merchant_id,
            order_id=order.id,
            event=event,
            from_status=from_status,
            to_status=to_status,
            actor=actor,
            details=details or {},
        )
    )


async def list_orders(
    session: AsyncSession,
    merchant_id: uuid.UUID,
    *,
    statuses: tuple[str, ...] | None = None,
    limit: int = 50,
) -> list[OrderSummary]:
    """Newest first, with their items."""
    query = select(Order).where(Order.merchant_id == merchant_id)
    if statuses:
        query = query.where(Order.status.in_(statuses))
    found = list(await session.scalars(query.order_by(Order.created_at.desc()).limit(limit)))
    items: dict[uuid.UUID, list[OrderItemSummary]] = defaultdict(list)
    if found:
        for item in await session.scalars(
            select(OrderItem).where(OrderItem.order_id.in_([order.id for order in found]))
        ):
            items[item.order_id].append(
                OrderItemSummary(
                    product=item.product_name,
                    variant=item.variant_name,
                    quantity=item.quantity,
                    unit_price_minor=item.unit_price_minor,
                )
            )
    return [
        OrderSummary(
            id=order.id,
            number=order.number,
            status=order.status,
            currency=order.currency,
            total_minor=order.total_minor,
            fulfilment=order.fulfilment,
            delivery_address=order.delivery_address,
            needed_by=order.needed_by,
            notes=order.notes,
            customer_id=order.customer_id,
            conversation_id=order.conversation_id,
            created_at=order.created_at,
            paid_at=order.paid_at,
            hold_expires_at=order.hold_expires_at,
            items=tuple(items[order.id]),
        )
        for order in found
    ]


async def day_summary(
    session: AsyncSession, merchant_id: uuid.UUID, business_date: date
) -> DaySummary:
    """Today's numbers for the Today screen: orders waiting for payment, paid, revenue."""
    rows = await session.execute(
        select(Order.status, Order.currency, func.count(), func.sum(Order.total_minor))
        .where(Order.merchant_id == merchant_id, Order.business_date == business_date)
        .group_by(Order.status, Order.currency)
    )
    awaiting = paid = 0
    revenue: dict[str, int] = defaultdict(int)
    for status, currency, count, total in rows:
        if status == "awaiting_payment":
            awaiting += count
        elif status in ("paid", "completed"):
            paid += count
            revenue[currency] += int(total or 0)
    return DaySummary(awaiting_payment=awaiting, paid=paid, revenue_minor_by_currency=dict(revenue))
