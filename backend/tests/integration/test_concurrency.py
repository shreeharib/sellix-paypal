"""Many customers at once: stock must never go below zero or be sold twice."""

import asyncio
import uuid
from datetime import UTC, date, datetime, timedelta

import pytest
from sqlalchemy import select

from app.core.db import session_scope
from app.modules.channels.models import ChannelConnection
from app.modules.channels.schemas import IncomingMessage
from app.modules.conversations import service as conversations
from app.modules.inventory import service as inventory
from app.modules.inventory.models import DailyStock
from app.modules.inventory.schemas import OpeningStockLine
from app.modules.orders import service as orders
from app.modules.orders.models import Order
from app.modules.orders.schemas import OrderLineRequest, OrderRequest
from app.modules.orders.service import OrderProblem
from tests.integration.factories import SHOP_ACCOUNT_ID

pytestmark = pytest.mark.anyio

TODAY = date(2026, 10, 25)
PREORDER_DAY = TODAY + timedelta(days=5)


def request(*lines: tuple[str, int]) -> OrderRequest:
    return OrderRequest(
        lines=tuple(OrderLineRequest(product, None, quantity) for product, quantity in lines),
        fulfilment="pickup",
    )


async def stock_row(variant_name: str, day: date) -> DailyStock:
    async with session_scope() as session:
        rows = await session.scalars(select(DailyStock).where(DailyStock.business_date == day))
        for row in rows:
            variants = await inventory.catalog.list_variants_by_ids(
                session, row.merchant_id, [row.variant_id], active_only=False
            )
            if variants[0].product_name == variant_name:
                return row
    raise AssertionError(variant_name)


async def place(
    shop: ChannelConnection, order: OrderRequest, day: date = TODAY, n: int = 0
) -> uuid.UUID | OrderProblem:
    """One customer's order in its own transaction, like one API request."""
    from app.modules.conversations.models import Conversation

    async with session_scope() as session:
        turn = await conversations.handle_incoming(
            session,
            IncomingMessage(
                channel="instagram",
                shop_account_id=SHOP_ACCOUNT_ID,
                customer_id=f"70000{n:08d}{uuid.uuid4().int % 1000}",
                message_id=f"m-{n}-{uuid.uuid4()}",
                text="hi",
            ),
        )
    assert turn is not None
    try:
        async with session_scope() as session:
            conversation = await session.get(Conversation, turn.conversation_id)
            assert conversation is not None
            placed = await orders.place_order(
                session,
                merchant_id=shop.merchant_id,
                customer_id=conversation.customer_id,
                conversation_id=conversation.id,
                business_date=day,
                request=order,
                hold_minutes=15,
            )
            return placed.order_id
    except OrderProblem as problem:
        return problem


@pytest.fixture
async def stocked(shop: ChannelConnection) -> ChannelConnection:
    async with session_scope() as session:
        for day in (TODAY, PREORDER_DAY):
            await inventory.set_opening_stock(
                session,
                merchant_id=shop.merchant_id,
                business_date=day,
                lines=[
                    OpeningStockLine("Brownie", None, 9000, 10),
                    OpeningStockLine("Diwali cake", None, 120000, 4),
                ],
            )
    return shop


async def test_forty_buyers_for_ten_brownies_sell_exactly_ten(stocked: ChannelConnection) -> None:
    results = await asyncio.gather(
        *(place(stocked, request(("Brownie", 1)), n=n) for n in range(40))
    )

    placed = [r for r in results if isinstance(r, uuid.UUID)]
    refused = [r for r in results if isinstance(r, OrderProblem)]
    crashed = [
        r for r in results if isinstance(r, BaseException) and not isinstance(r, OrderProblem)
    ]
    assert not crashed
    assert len(placed) == 10
    assert len(refused) == 30
    row = await stock_row("Brownie", TODAY)
    assert (row.held, row.available) == (10, 0)


async def test_crossed_multi_item_orders_do_not_deadlock(stocked: ChannelConnection) -> None:
    ab = request(("Brownie", 1), ("Diwali cake", 1))
    ba = request(("Diwali cake", 1), ("Brownie", 1))

    results = await asyncio.gather(
        *(place(stocked, ab if n % 2 else ba, n=n) for n in range(20)), return_exceptions=True
    )

    crashed = [
        r for r in results if isinstance(r, BaseException) and not isinstance(r, OrderProblem)
    ]
    assert not crashed, crashed[:1]
    cake = await stock_row("Diwali cake", TODAY)
    assert cake.held == 4  # 4 cakes, 20 buyers: exactly 4 win


async def test_preorders_hold_the_pickup_day_not_today(stocked: ChannelConnection) -> None:
    results = await asyncio.gather(
        *(place(stocked, request(("Diwali cake", 1)), day=PREORDER_DAY, n=n) for n in range(12))
    )

    assert sum(isinstance(r, uuid.UUID) for r in results) == 4
    assert (await stock_row("Diwali cake", PREORDER_DAY)).held == 4
    assert (await stock_row("Diwali cake", TODAY)).held == 0


async def test_a_payment_delivered_twice_at_once_sells_once(stocked: ChannelConnection) -> None:
    order_id = await place(stocked, request(("Diwali cake", 2)))
    assert isinstance(order_id, uuid.UUID)

    async def pay() -> str:
        async with session_scope() as session:
            result = await orders.record_payment(
                session, order_id, amount_minor=240000, currency="INR", actor="paypal"
            )
            return result.outcome

    outcomes = await asyncio.gather(*(pay() for _ in range(5)))

    assert sorted(outcomes) == ["already_paid"] * 4 + ["paid"]
    row = await stock_row("Diwali cake", TODAY)
    assert (row.held, row.sold) == (0, 2)


async def test_cancel_racing_with_payment_never_double_counts(stocked: ChannelConnection) -> None:
    order_id = await place(stocked, request(("Diwali cake", 2)))
    assert isinstance(order_id, uuid.UUID)

    async def pay() -> None:
        async with session_scope() as session:
            await orders.record_payment(
                session, order_id, amount_minor=240000, currency="INR", actor="paypal"
            )

    async def cancel() -> None:
        async with session_scope() as session:
            order = await session.get(Order, order_id)
            assert order is not None
            await orders.cancel_order(session, order_id, merchant_id=order.merchant_id)

    await asyncio.gather(pay(), cancel(), return_exceptions=True)

    row = await stock_row("Diwali cake", TODAY)
    assert row.held == 0
    assert row.available + row.sold + row.counter_sales == row.opening + row.restocked - row.held


async def test_expiring_a_preorder_hold_frees_the_pickup_day(stocked: ChannelConnection) -> None:
    order_id = await place(stocked, request(("Diwali cake", 3)), day=PREORDER_DAY)
    assert isinstance(order_id, uuid.UUID)

    later = datetime.now(UTC) + timedelta(hours=1)
    async with session_scope() as session:
        await orders.expire_due(session, now=later)

    row = await stock_row("Diwali cake", PREORDER_DAY)
    assert (row.held, row.available) == (0, 4)
    assert (await stock_row("Diwali cake", TODAY)).held == 0
