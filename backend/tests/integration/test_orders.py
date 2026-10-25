from datetime import UTC, date, datetime, timedelta

import pytest
from sqlalchemy import select

from app.core.db import session_scope
from app.modules.channels.models import ChannelConnection
from app.modules.conversations.models import Conversation
from app.modules.inventory import service as inventory
from app.modules.inventory.schemas import OpeningStockLine
from app.modules.orders import service as orders
from app.modules.orders.models import Order, OrderEvent
from app.modules.orders.schemas import OrderLineRequest, OrderRequest, PlacedOrder
from tests.integration.factories import start_conversation

pytestmark = pytest.mark.anyio

TODAY = date(2026, 10, 25)


def request(*lines: tuple[str, str | None, int]) -> OrderRequest:
    return OrderRequest(
        lines=tuple(
            OrderLineRequest(product, variant, quantity) for product, variant, quantity in lines
        ),
        fulfilment="pickup",
    )


@pytest.fixture
async def stocked(shop: ChannelConnection) -> ChannelConnection:
    async with session_scope() as session:
        await inventory.set_opening_stock(
            session,
            merchant_id=shop.merchant_id,
            business_date=TODAY,
            lines=[
                OpeningStockLine("Scoop cookie", "Chocolate", 6000, 3),
                OpeningStockLine("Scoop cookie", "Red velvet", 7000, 0),
                OpeningStockLine("Brownie", None, 9000, 15),
            ],
        )
    return shop


async def available(shop: ChannelConnection, label: str) -> int:
    async with session_scope() as session:
        stock = await inventory.today_stock(session, shop.merchant_id, TODAY)
    return next(item.available for item in stock if item.label == label)


async def place(shop: ChannelConnection, order: OrderRequest) -> PlacedOrder:
    turn = await start_conversation(message_id=f"m-{datetime.now(UTC).timestamp()}")
    async with session_scope() as session:
        conversation = await session.get(Conversation, turn.conversation_id)
        assert conversation is not None
        return await orders.place_order(
            session,
            merchant_id=shop.merchant_id,
            customer_id=conversation.customer_id,
            conversation_id=conversation.id,
            business_date=TODAY,
            request=order,
            hold_minutes=15,
        )


async def test_quote_has_exact_totals(stocked: ChannelConnection) -> None:
    async with session_scope() as session:
        offer = await orders.quote(
            session,
            merchant_id=stocked.merchant_id,
            business_date=TODAY,
            request=request(("scoop cookie", "chocolate", 2), ("Brownie", None, 1)),
        )

    assert offer.ok
    assert (offer.total_minor, offer.currency) == (2 * 6000 + 9000, "INR")


async def test_quote_explains_what_cant_be_sold(stocked: ChannelConnection) -> None:
    async with session_scope() as session:
        offer = await orders.quote(
            session,
            merchant_id=stocked.merchant_id,
            business_date=TODAY,
            request=request(
                ("Scoop cookie", "Chocolate", 5),
                ("Scoop cookie", "Red velvet", 1),
                ("Scoop cookie", None, 1),
                ("Plum cake", None, 1),
            ),
        )

    assert not offer.ok
    assert offer.problems == (
        "Scoop cookie comes in Chocolate, Red velvet: ask which one",
        "Plum cake isn't in today's stock",
        "Scoop cookie (Chocolate): only 3 left",
        "Scoop cookie (Red velvet) is sold out",
    )


async def test_placing_holds_stock_and_the_last_items_cant_be_sold_twice(
    stocked: ChannelConnection,
) -> None:
    first = await place(stocked, request(("Scoop cookie", "Chocolate", 3)))

    with pytest.raises(orders.OrderProblem):
        await place(stocked, request(("Scoop cookie", "Chocolate", 1)))

    assert first.number >= 1001
    assert first.total_minor == 18000
    assert await available(stocked, "Scoop cookie (Chocolate)") == 0


async def test_a_failed_order_holds_nothing(stocked: ChannelConnection) -> None:
    with pytest.raises(orders.OrderProblem):
        await place(stocked, request(("Brownie", None, 2), ("Scoop cookie", "Chocolate", 9)))

    assert await available(stocked, "Brownie") == 15


async def test_payment_turns_held_stock_into_a_sale(stocked: ChannelConnection) -> None:
    placed = await place(stocked, request(("Brownie", None, 2)))

    async with session_scope() as session:
        paid = await orders.record_payment(
            session, placed.order_id, amount_minor=18000, currency="INR", actor="paypal"
        )
    async with session_scope() as session:
        again = await orders.record_payment(
            session, placed.order_id, amount_minor=18000, currency="INR", actor="paypal"
        )
        order = await session.get(Order, placed.order_id)
        events = list(
            await session.scalars(select(OrderEvent.event).order_by(OrderEvent.created_at))
        )

    assert (paid.outcome, again.outcome) == ("paid", "already_paid")
    assert order is not None and order.status == "paid" and order.paid_at is not None
    assert events == ["placed", "paid"]
    assert await available(stocked, "Brownie") == 13


async def test_payment_for_the_wrong_amount_does_not_mark_the_order_paid(
    stocked: ChannelConnection,
) -> None:
    placed = await place(stocked, request(("Brownie", None, 1)))

    async with session_scope() as session:
        result = await orders.record_payment(
            session, placed.order_id, amount_minor=100, currency="INR", actor="paypal"
        )
        order = await session.get(Order, placed.order_id)

    assert result.outcome == "amount_mismatch"
    assert order is not None and order.status == "awaiting_payment"


async def test_unpaid_orders_expire_and_release_their_stock(stocked: ChannelConnection) -> None:
    placed = await place(stocked, request(("Brownie", None, 4)))

    async with session_scope() as session:
        expired = await orders.expire_due(session, now=datetime.now(UTC) + timedelta(minutes=16))

    assert [order.order_id for order in expired] == [placed.order_id]
    assert await available(stocked, "Brownie") == 15


async def test_payment_after_expiry_sells_if_stock_is_still_there(
    stocked: ChannelConnection,
) -> None:
    placed = await place(stocked, request(("Brownie", None, 4)))
    async with session_scope() as session:
        await orders.expire_due(session, now=datetime.now(UTC) + timedelta(minutes=16))

    async with session_scope() as session:
        result = await orders.record_payment(
            session, placed.order_id, amount_minor=36000, currency="INR", actor="paypal"
        )

    assert result.outcome == "paid"
    assert await available(stocked, "Brownie") == 11


async def test_payment_after_expiry_flags_a_shortfall_when_stock_is_gone(
    stocked: ChannelConnection,
) -> None:
    late = await place(stocked, request(("Scoop cookie", "Chocolate", 3)))
    async with session_scope() as session:
        await orders.expire_due(session, now=datetime.now(UTC) + timedelta(minutes=16))
    await place(stocked, request(("Scoop cookie", "Chocolate", 3)))  # someone else buys them

    async with session_scope() as session:
        result = await orders.record_payment(
            session, late.order_id, amount_minor=18000, currency="INR", actor="paypal"
        )

    assert result.outcome == "paid_stock_short"
    assert await available(stocked, "Scoop cookie (Chocolate)") == 0  # never negative
