"""Public interface of the orders module: quotes, placing orders, payment and expiry.

Order states: awaiting_payment -> paid (-> completed / refunded), or awaiting_payment ->
expired / cancelled. Every change is written to order_events.
"""

import uuid
from collections import defaultdict
from datetime import UTC, date, datetime, timedelta

from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.inventory import service as inventory
from app.modules.inventory.schemas import StockItem
from app.modules.orders.models import (
    Order,
    OrderEvent,
    OrderItem,
    OrderTimeline,
    QuoteRecord,
    Refund,
    RefundRequest,
)
from app.modules.orders.schemas import (
    DaySummary,
    ExpiredOrder,
    OrderItemSummary,
    OrderLineRequest,
    OrderRequest,
    OrderSummary,
    PaymentOutcome,
    PaymentResult,
    PlacedOrder,
    Quote,
    QuoteLine,
    QuoteRefused,
    RefundStatus,
    RefundTicket,
    SavedQuote,
)

# Per customer per shop (agent-phase-2.md section 14, item 6); more needs the shop owner.
MAX_UNPAID_ORDERS = 2


class OrderProblem(ValueError):
    """The order can't be placed; `problems` are safe to tell the customer."""

    def __init__(self, problems: tuple[str, ...]) -> None:
        super().__init__("; ".join(problems))
        self.problems = problems


class _StockShortfall(Exception):
    pass


async def quote(
    session: AsyncSession, *, merchant_id: uuid.UUID, business_date: date, request: OrderRequest
) -> Quote:
    stock = await inventory.today_stock(session, merchant_id, business_date)
    wanted: dict[uuid.UUID, int] = defaultdict(int)
    items: dict[uuid.UUID, StockItem] = {}
    problems: list[str] = []

    for line in request.lines:
        label = f"{line.product} ({line.variant})" if line.variant else line.product
        if line.quantity < 1:
            problems.append(f"{label}: the quantity must be at least 1")
            continue
        matches = [
            item
            for item in stock
            if _same(item.product, line.product)
            and (line.variant is None or _same(item.variant or "", line.variant))
        ]
        if not matches:
            problems.append(f"{label} isn't in today's stock")
        elif len(matches) > 1:
            variants = ", ".join(item.variant or "plain" for item in matches)
            problems.append(f"{line.product} comes in {variants}: ask which one")
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
) -> PlacedOrder:
    """Hold the stock and create the order, all or nothing (the caller's transaction)."""
    offer = await quote(
        session, merchant_id=merchant_id, business_date=business_date, request=request
    )
    if not offer.ok or offer.currency is None:
        raise OrderProblem(offer.problems or ("The order has no items",))
    order_id = uuid.uuid4()
    hold_expires = datetime.now(UTC) + timedelta(minutes=hold_minutes)
    fulfilment_method = (
        getattr(request, "fulfilment_method", None)
        or getattr(request, "fulfilment", None)
        or "pickup"
    )
    customer_note = getattr(request, "customer_note", None) or getattr(request, "notes", None)
    channel = getattr(request, "channel", "instagram")
    placed_by = getattr(request, "placed_by", "customer")
    scheduled_date = getattr(request, "scheduled_date", None)
    scheduled_window = getattr(request, "scheduled_window", None)
    if not scheduled_window and getattr(request, "needed_by", None):
        scheduled_window = request.needed_by

    order = Order(
        id=order_id,
        merchant_id=merchant_id,
        customer_id=customer_id,
        conversation_id=conversation_id,
        channel=channel,
        placed_by=placed_by,
        status="awaiting_payment",
        payment_status="unpaid",
        fulfilment_status="unfulfilled",
        fulfilment_method=fulfilment_method,
        delivery_address=request.delivery_address,
        scheduled_date=scheduled_date,
        scheduled_window=scheduled_window,
        customer_note=customer_note,
        business_date=business_date,
        currency=offer.currency,
        total_minor=offer.total_minor,
        subtotal_minor=offer.total_minor,
        hold_expires_at=hold_expires,
    )
    session.add(order)
    await session.flush()

    for line in offer.lines:
        held = await inventory.hold(
            session,
            variant_id=line.variant_id,
            business_date=business_date,
            quantity=line.quantity,
            order_id=order.id,
            conversation_id=conversation_id,
            expires_at=hold_expires,
        )
        if not held:
            raise OrderProblem((f"{line.label} just sold out",))

    session.add_all(
        OrderItem(
            merchant_id=merchant_id,
            order_id=order.id,
            variant_id=line.variant_id,
            product_name=line.product,
            variant_label=line.variant,
            unit_price_minor=line.unit_price_minor,
            line_total_minor=line.unit_price_minor * line.quantity,
            quantity=line.quantity,
            fulfilment_status="unfulfilled",
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
    customer_id: uuid.UUID,
    business_date: date,
    request: OrderRequest,
    expires_at: datetime,
    business_date_override: date | None = None,
) -> SavedQuote | Quote:
    """Price the request and save it as the conversation's open quote (older ones superseded).

    Returns the plain Quote, with its problems, when it can't be offered.
    `business_date_override`: a pre-order for a later day, priced and held on that day's stock.
    """
    business_date = business_date_override or business_date
    offer = await quote(
        session, merchant_id=merchant_id, business_date=business_date, request=request
    )
    if not offer.ok or offer.currency is None:
        return offer
    await supersede_quotes(session, conversation_id)
    record = QuoteRecord(
        merchant_id=merchant_id,
        conversation_id=conversation_id,
        customer_id=customer_id,
        business_date=business_date,
        lines=[
            {
                "variant_id": str(line.variant_id),
                "label": line.label,
                "product": line.product,
                "variant": line.variant,
                "quantity": line.quantity,
                "unit_price_minor": line.unit_price_minor,
            }
            for line in offer.lines
        ],
        currency=offer.currency,
        total_minor=offer.total_minor,
        fulfilment=request.fulfilment,
        delivery_address=request.delivery_address,
        needed_by=request.needed_by,
        notes=request.notes,
        status="open",
        expires_at=expires_at,
    )
    session.add(record)
    await session.flush()
    return _saved_quote(record)


async def supersede_quotes(session: AsyncSession, conversation_id: uuid.UUID) -> None:
    """The order changed: open quotes for this conversation can no longer be confirmed."""
    await session.execute(
        update(QuoteRecord)
        .where(QuoteRecord.conversation_id == conversation_id, QuoteRecord.status == "open")
        .values(status="superseded", updated_at=func.now())
    )


async def get_quote(
    session: AsyncSession, quote_id: uuid.UUID, conversation_id: uuid.UUID
) -> SavedQuote | None:
    record = await session.get(QuoteRecord, quote_id)
    if record is None or record.conversation_id != conversation_id:
        return None
    return _saved_quote(record)


async def open_quote(session: AsyncSession, conversation_id: uuid.UUID) -> SavedQuote | None:
    """The conversation's quote that can still be confirmed, if any."""
    record = await session.scalar(
        select(QuoteRecord)
        .where(QuoteRecord.conversation_id == conversation_id, QuoteRecord.status == "open")
        .order_by(QuoteRecord.created_at.desc())
        .limit(1)
    )
    return _saved_quote(record) if record else None


async def current_quote(session: AsyncSession, conversation_id: uuid.UUID) -> SavedQuote | None:
    """The conversation's latest quote that's still open, or was confirmed."""
    record = await session.scalar(
        select(QuoteRecord)
        .where(
            QuoteRecord.conversation_id == conversation_id,
            QuoteRecord.status.in_(("open", "confirmed")),
        )
        .order_by(QuoteRecord.created_at.desc())
        .limit(1)
    )
    return _saved_quote(record) if record else None


async def latest_order(session: AsyncSession, conversation_id: uuid.UUID) -> PlacedOrder | None:
    """The conversation's most recent order (for the agent's [[order_number]] token)."""
    order = await session.scalar(
        select(Order)
        .where(Order.conversation_id == conversation_id)
        .order_by(Order.created_at.desc())
        .limit(1)
    )
    if order is None:
        return None
    return PlacedOrder(order.id, order.number, order.currency, order.total_minor, 0)


async def customer_orders(
    session: AsyncSession, merchant_id: uuid.UUID, customer_id: uuid.UUID, *, limit: int = 5
) -> list[OrderSummary]:
    """This customer's latest orders at this shop, newest first."""
    ids = list(
        await session.scalars(
            select(Order.id)
            .where(Order.merchant_id == merchant_id, Order.customer_id == customer_id)
            .order_by(Order.created_at.desc())
            .limit(limit)
        )
    )
    found = [await get_order(session, order_id, merchant_id) for order_id in ids]
    return [order for order in found if order is not None]


async def last_order_lines(
    session: AsyncSession, merchant_id: uuid.UUID, customer_id: uuid.UUID
) -> tuple[list[tuple[uuid.UUID, int]], str | None, str | None] | None:
    """The customer's last paid order: (variant, quantity) lines, fulfilment, address."""
    order = await session.scalar(
        select(Order)
        .where(
            Order.merchant_id == merchant_id,
            Order.customer_id == customer_id,
            Order.payment_status.in_(("paid", "partially_refunded")),
        )
        .order_by(Order.created_at.desc())
        .limit(1)
    )
    if order is None:
        return None
    lines = await session.execute(
        select(OrderItem.variant_id, OrderItem.quantity).where(OrderItem.order_id == order.id)
    )
    return (
        [(variant_id, quantity) for variant_id, quantity in lines],
        order.fulfilment_method,
        order.delivery_address,
    )


async def mark_quote_shown(
    session: AsyncSession, quote_id: uuid.UUID, message_id: uuid.UUID
) -> None:
    """The quote card reached the customer: only now can the quote be confirmed."""
    record = await session.get(QuoteRecord, quote_id, with_for_update=True)
    if record is not None and record.shown_message_id is None:
        record.shown_message_id = message_id
        record.shown_at = datetime.now(UTC)
        record.updated_at = datetime.now(UTC)


async def confirm_quote(
    session: AsyncSession,
    *,
    quote_id: uuid.UUID,
    conversation_id: uuid.UUID,
    hold_minutes: int,
    now: datetime | None = None,
) -> PlacedOrder:
    """Turn a delivered, unexpired quote into an order. Confirming twice returns the same order.

    Raises QuoteRefused (placing nothing) if the quote can't be confirmed, and OrderProblem if
    the stock is gone. Raising rolls back the caller's transaction, stock holds included.
    """
    now = now or datetime.now(UTC)
    record = await session.get(QuoteRecord, quote_id, with_for_update=True)
    if record is None or record.conversation_id != conversation_id:
        raise QuoteRefused("unknown_quote", "No such quote in this conversation")
    if record.status == "confirmed" and record.order_id is not None:
        order = await session.get(Order, record.order_id)
        if order is not None:
            return PlacedOrder(
                order.id, order.number, order.currency, order.total_minor, hold_minutes
            )
    if record.status == "superseded":
        raise QuoteRefused("superseded", "The order changed after this quote: make a new quote")
    if record.status == "expired" or record.expires_at <= now:
        record.status = "expired"
        raise QuoteRefused("expired", "This quote has expired: make a new quote")
    if record.shown_message_id is None:
        raise QuoteRefused(
            "not_shown", "The customer hasn't received the quote card, so it can't be confirmed"
        )
    unpaid = await session.scalar(
        select(func.count())
        .select_from(Order)
        .where(
            Order.merchant_id == record.merchant_id,
            Order.customer_id == record.customer_id,
            Order.status == "awaiting_payment",
        )
    )
    if (unpaid or 0) >= MAX_UNPAID_ORDERS:
        raise QuoteRefused(
            "too_many_unpaid_orders",
            f"This customer already has {unpaid} unpaid orders: ask the shop owner first",
        )
    placed = await place_order(
        session,
        merchant_id=record.merchant_id,
        customer_id=record.customer_id,
        conversation_id=record.conversation_id,
        business_date=record.business_date,
        request=OrderRequest(
            lines=tuple(
                OrderLineRequest(line["product"], line["variant"], int(line["quantity"]))
                for line in record.lines
            ),
            fulfilment=record.fulfilment,
            delivery_address=record.delivery_address,
            needed_by=record.needed_by,
            notes=record.notes,
        ),
        hold_minutes=hold_minutes,
    )
    if (placed.total_minor, placed.currency) != (record.total_minor, record.currency):
        raise QuoteRefused("price_changed", "Prices changed since this quote: make a new quote")
    record.status = "confirmed"
    record.order_id = placed.order_id
    record.updated_at = now
    return placed


def _saved_quote(record: QuoteRecord) -> SavedQuote:
    return SavedQuote(
        id=record.id,
        conversation_id=record.conversation_id,
        lines=tuple(
            QuoteLine(
                variant_id=uuid.UUID(line["variant_id"]),
                label=line["label"],
                product=line["product"],
                variant=line["variant"],
                unit_price_minor=int(line["unit_price_minor"]),
                currency=record.currency,
                quantity=int(line["quantity"]),
            )
            for line in record.lines
        ),
        currency=record.currency,
        total_minor=record.total_minor,
        fulfilment=record.fulfilment,
        delivery_address=record.delivery_address,
        needed_by=record.needed_by,
        business_date=record.business_date,
        status=record.status,
        expires_at=record.expires_at,
        shown_message_id=record.shown_message_id,
        shown_at=record.shown_at,
        order_id=record.order_id,
    )


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
                order_id=order.id,
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

    target_status = "paid"
    order.status = target_status
    order.payment_status = "paid"
    order.amount_paid_minor = amount_minor
    order.paid_at = datetime.now(UTC)
    order.hold_expires_at = None
    _log(session, order, outcome, previous, target_status, actor)
    await session.flush()
    return result(outcome)


async def refund_order(
    session: AsyncSession,
    order_id: uuid.UUID,
    *,
    restock: bool = True,
    reason: str | None = None,
    actor: str = "merchant",
) -> None:
    """Refund an order at once, when there's no payment provider to wait for."""
    ticket = await open_refund(session, order_id, restock=restock, reason=reason)
    await settle_refund(session, ticket.id, status="completed", actor=actor)


async def open_refund(
    session: AsyncSession,
    order_id: uuid.UUID,
    *,
    restock: bool = True,
    reason: str | None = None,
) -> RefundTicket:
    """Record a pending refund of the order's total, or return the refund already open for it.

    Commit it before asking the payment provider for the money, so a refund the provider makes
    is always on record.
    """
    order = await session.scalar(select(Order).where(Order.id == order_id).with_for_update())
    if order is None:
        raise LookupError(f"No order {order_id}")
    request = await session.scalar(
        select(RefundRequest).where(
            RefundRequest.order_id == order_id,
            RefundRequest.status.in_(("pending", "completed")),
        )
    )
    if request is None:
        if order.status == "refunded":
            raise RuntimeError(f"Order {order_id} is already refunded")
        request = RefundRequest(
            merchant_id=order.merchant_id,
            order_id=order.id,
            amount_minor=order.total_minor,
            reason=reason,
            is_restocked=restock,
            status="pending",
        )
        session.add(request)
        await session.flush()
    return _refund_ticket(request)


async def settle_refund(
    session: AsyncSession,
    refund_id: uuid.UUID,
    *,
    status: RefundStatus,
    provider_refund_id: str | None = None,
    actor: str = "merchant",
) -> None:
    """Record the provider's answer; a completed refund refunds the order and returns its stock."""
    request = await session.scalar(
        select(RefundRequest).where(RefundRequest.id == refund_id).with_for_update()
    )
    if request is None:
        raise LookupError(f"No refund {refund_id}")
    if request.status != "pending":
        return
    request.status = status
    request.provider_refund_id = provider_refund_id or request.provider_refund_id
    request.updated_at = datetime.now(UTC)
    if status != "completed":
        return

    order = await session.scalar(
        select(Order).where(Order.id == request.order_id).with_for_update()
    )
    if order is None or order.status == "refunded":
        return
    previous = order.status
    if request.is_restocked and previous in ("paid", "completed", "confirmed"):
        items = list(await session.scalars(select(OrderItem).where(OrderItem.order_id == order.id)))
        for item in items:
            await inventory.release(
                session,
                variant_id=item.variant_id,
                business_date=order.business_date,
                quantity=item.quantity,
            )

    order.status = "refunded"
    order.payment_status = "refunded"
    session.add(
        Refund(
            order_id=order.id,
            refund_amount_minor=request.amount_minor,
            reason=request.reason,
            is_restocked=request.is_restocked,
        )
    )
    _log(session, order, "refunded", previous, "refunded", actor, {"reason": request.reason})


async def pending_refunds(
    session: AsyncSession,
    *,
    older_than: timedelta | None = None,
    order_id: uuid.UUID | None = None,
) -> list[RefundTicket]:
    """Refunds still waiting for the payment provider, oldest first."""
    query = (
        select(RefundRequest)
        .where(RefundRequest.status == "pending")
        .order_by(RefundRequest.created_at)
    )
    if older_than is not None:
        query = query.where(RefundRequest.created_at < func.now() - older_than)
    if order_id is not None:
        query = query.where(RefundRequest.order_id == order_id)
    return [_refund_ticket(request) for request in await session.scalars(query)]


def _refund_ticket(request: RefundRequest) -> RefundTicket:
    return RefundTicket(
        id=request.id,
        order_id=request.order_id,
        status=request.status,
        reason=request.reason,
        provider_refund_id=request.provider_refund_id,
    )


async def mark_order_paid(
    session: AsyncSession,
    order_id: uuid.UUID,
    *,
    merchant_id: uuid.UUID,
    actor: str = "merchant",
    method: str = "upi",
    reference_id: str | None = None,
) -> PaymentResult:
    """Owner tap-to-confirm when receiving a UPI payment alert on their phone or counter checkout.

    Delegates to payments.mark_order_paid so the payments->orders relationship remains one-way.
    """
    from app.modules.payments import service as payments

    return await payments.mark_order_paid(
        session,
        order_id,
        merchant_id=merchant_id,
        actor=actor,
        method=method,
        reference_id=reference_id,
    )


ENTERPRISE_ORDER_STATUSES = {
    "draft",
    "pending",
    "confirmed",
    "ready",
    "delivered",
    "completed",
    "awaiting_payment",
    "paid",
    "cancelled",
    "refunded",
    "expired",
}


async def advance_order_status(
    session: AsyncSession,
    order_id: uuid.UUID,
    *,
    merchant_id: uuid.UUID,
    new_status: str,
    actor: str = "merchant",
    comment: str | None = None,
) -> Order:
    """Advance an order through enterprise fulfillment / operational stages."""
    if new_status not in ENTERPRISE_ORDER_STATUSES:
        raise ValueError(
            f"Invalid status '{new_status}'. Allowed statuses: {sorted(ENTERPRISE_ORDER_STATUSES)}"
        )

    order = await session.scalar(
        select(Order)
        .where(Order.id == order_id, Order.merchant_id == merchant_id)
        .with_for_update()
    )
    if order is None:
        raise LookupError(f"No order {order_id}")
    if order.status == new_status:
        return order

    previous = order.status
    order.status = new_status
    if new_status in ("delivered", "completed"):
        order.fulfilment_status = "fulfilled"
    elif new_status == "ready":
        order.fulfilment_status = "ready"
    elif new_status in ("confirmed", "in_production"):
        order.fulfilment_status = "in_production"

    _log(
        session,
        order,
        f"status_changed_to_{new_status}",
        previous,
        new_status,
        actor,
        {"comment": comment} if comment else None,
    )
    await session.flush()
    return order


async def get_order_timeline(
    session: AsyncSession,
    order_id: uuid.UUID,
    merchant_id: uuid.UUID,
) -> list[OrderTimeline]:
    """Fetch order timeline history auto-logged by database triggers."""
    order = await session.scalar(
        select(Order).where(Order.id == order_id, Order.merchant_id == merchant_id)
    )
    if order is None:
        raise LookupError(f"No order {order_id}")
    return list(
        await session.scalars(
            select(OrderTimeline)
            .where(OrderTimeline.order_id == order_id)
            .order_by(OrderTimeline.created_at.asc())
        )
    )


async def complete_order(
    session: AsyncSession,
    order_id: uuid.UUID,
    *,
    merchant_id: uuid.UUID,
    actor: str = "merchant",
) -> Order:
    """Mark an order as completed (picked up or delivered)."""
    order = await session.scalar(
        select(Order)
        .where(Order.id == order_id, Order.merchant_id == merchant_id)
        .with_for_update()
    )
    if order is None:
        raise LookupError(f"No order {order_id}")
    if order.status == "completed":
        return order

    valid_pre_complete = ("paid", "confirmed", "ready", "delivered")
    if order.status not in valid_pre_complete:
        raise ValueError(
            f"Cannot complete order with status '{order.status}'."
            f" Order must be paid first (status in {valid_pre_complete})."
        )

    previous = order.status
    order.status = "completed"
    order.fulfilment_status = "fulfilled"
    _log(session, order, "completed", previous, "completed", actor)
    await session.flush()
    return order


async def cancel_order(
    session: AsyncSession,
    order_id: uuid.UUID,
    *,
    merchant_id: uuid.UUID,
    actor: str = "merchant",
    reason: str | None = None,
) -> Order:
    """Cancel an unpaid order and atomically release its held stock back to today's ledger."""
    order = await session.scalar(
        select(Order)
        .where(Order.id == order_id, Order.merchant_id == merchant_id)
        .with_for_update()
    )
    if order is None:
        raise LookupError(f"No order {order_id}")
    if order.status == "cancelled":
        return order
    if order.status in ("completed", "refunded"):
        raise ValueError(f"Cannot cancel order with status '{order.status}'")

    previous = order.status
    if previous == "awaiting_payment":
        # Release the held stock back to available inventory
        items = list(await session.scalars(select(OrderItem).where(OrderItem.order_id == order.id)))
        for item in items:
            await inventory.release(
                session,
                variant_id=item.variant_id,
                business_date=order.business_date,
                quantity=item.quantity,
                order_id=order.id,
                status="cancelled",
            )

    order.status = "cancelled"
    order.hold_expires_at = None
    _log(
        session,
        order,
        "cancelled",
        previous,
        "cancelled",
        actor,
        {"reason": reason} if reason else None,
    )
    await session.flush()
    return order


async def expire_due(session: AsyncSession, *, now: datetime | None = None) -> list[ExpiredOrder]:
    """Release the stock of unpaid orders whose hold has run out."""
    cutoff = now or datetime.now(UTC)
    due = list(
        await session.scalars(
            select(Order)
            .where(
                Order.status == "awaiting_payment",
                Order.hold_expires_at < cutoff,
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
                order_id=order.id,
                status="expired",
            )
        order.status = "expired"
        order.hold_expires_at = None
        _log(session, order, "expired", "awaiting_payment", "expired", "system")
        expired.append(ExpiredOrder(order.id, order.number, order.conversation_id))

    # Also release any standalone / unlinked holds in stock_holds table
    await inventory.release_expired_holds(session, now=cutoff)
    return expired


def _same(a: str, b: str) -> bool:
    return " ".join(a.lower().split()) == " ".join(b.lower().split())


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
    payment_statuses: tuple[str, ...] | None = None,
    limit: int = 50,
) -> list[OrderSummary]:
    """Newest first, with their items."""
    query = select(Order).where(Order.merchant_id == merchant_id)
    if statuses:
        query = query.where(Order.status.in_(statuses))
    if payment_statuses:
        query = query.where(Order.payment_status.in_(payment_statuses))
    found = list(await session.scalars(query.order_by(Order.created_at.desc()).limit(limit)))
    items: dict[uuid.UUID, list[OrderItemSummary]] = defaultdict(list)
    if found:
        for item in await session.scalars(
            select(OrderItem).where(OrderItem.order_id.in_([order.id for order in found]))
        ):
            items[item.order_id].append(
                OrderItemSummary(
                    product=item.product_name or "",
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
            customer_id=order.customer_id,
            conversation_id=order.conversation_id,
            created_at=order.created_at,
            paid_at=order.paid_at,
            hold_expires_at=order.hold_expires_at,
            items=tuple(items[order.id]),
            order_number=order.order_number,
            payment_status=order.payment_status,
            fulfilment_status=order.fulfilment_status,
            fulfilment_method=order.fulfilment_method,
            channel=order.channel,
            delivery_address=order.delivery_address,
            customer_note=order.customer_note,
            scheduled_date=order.scheduled_date,
            scheduled_window=order.scheduled_window,
            merchant_id=order.merchant_id,
        )
        for order in found
    ]


async def get_order(
    session: AsyncSession,
    order_id: uuid.UUID,
    merchant_id: uuid.UUID | None = None,
) -> OrderSummary | None:
    """Fetch a single order summary with its items, optionally scoped to a merchant."""
    query = select(Order).where(Order.id == order_id)
    if merchant_id is not None:
        query = query.where(Order.merchant_id == merchant_id)
    order = await session.scalar(query)
    if order is None:
        return None
    items = list(await session.scalars(select(OrderItem).where(OrderItem.order_id == order.id)))
    return OrderSummary(
        id=order.id,
        number=order.number,
        status=order.status,
        currency=order.currency,
        total_minor=order.total_minor,
        customer_id=order.customer_id,
        conversation_id=order.conversation_id,
        created_at=order.created_at,
        paid_at=order.paid_at,
        hold_expires_at=order.hold_expires_at,
        items=tuple(
            OrderItemSummary(
                product=item.product_name or "",
                variant=item.variant_name,
                quantity=item.quantity,
                unit_price_minor=item.unit_price_minor,
            )
            for item in items
        ),
        order_number=order.order_number,
        payment_status=order.payment_status,
        fulfilment_status=order.fulfilment_status,
        fulfilment_method=order.fulfilment_method,
        channel=order.channel,
        delivery_address=order.delivery_address,
        customer_note=order.customer_note,
        scheduled_date=order.scheduled_date,
        scheduled_window=order.scheduled_window,
        merchant_id=order.merchant_id,
    )


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
