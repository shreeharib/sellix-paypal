"""expire_unpaid_orders: copies that start together (after the laptop slept) must not deadlock.

One copy runs at a time (an advisory lock; a second copy skips), and a batch releases its stock
rows in one order, sorted by (variant, date), so two batches can't lock the same rows crosswise.
"""

import asyncio
import uuid
from datetime import UTC, datetime, timedelta

import pytest
from procrastinate.testing import InMemoryConnector
from sqlalchemy import select, update

from app.core import locks
from app.core.db import session_scope
from app.modules.channels.models import ChannelConnection
from app.modules.conversations.models import Conversation
from app.modules.inventory import service as inventory
from app.modules.inventory.models import DailyStock, StockHold
from app.modules.inventory.schemas import OpeningStockLine
from app.modules.merchants import service as merchants
from app.modules.orders import service as orders
from app.modules.orders import tasks
from app.modules.orders.models import Order
from app.modules.orders.schemas import OrderLineRequest, OrderRequest
from tests.integration.factories import start_conversation

pytestmark = pytest.mark.anyio

PRODUCTS = ("Brownie", "Croissant", "Eclair", "Muffin")


@pytest.fixture
async def due_orders(shop: ChannelConnection) -> list[uuid.UUID]:
    """Twenty unpaid orders past their hold, each for two products in crossing orders."""
    async with session_scope() as session:
        today = merchants.business_date(await merchants.get_merchant(session, shop.merchant_id))
        await inventory.set_opening_stock(
            session,
            merchant_id=shop.merchant_id,
            business_date=today,
            lines=[OpeningStockLine(name, None, 5000, 100) for name in PRODUCTS],
        )
    turn = await start_conversation()
    placed: list[uuid.UUID] = []
    for n in range(20):
        first, second = PRODUCTS[n % 4], PRODUCTS[(n * 3 + 1) % 4]
        if first == second:
            second = PRODUCTS[(n + 2) % 4]
        async with session_scope() as session:
            conversation = await session.get(Conversation, turn.conversation_id)
            assert conversation is not None
            order = await orders.place_order(
                session,
                merchant_id=shop.merchant_id,
                customer_id=conversation.customer_id,
                conversation_id=conversation.id,
                business_date=today,
                request=OrderRequest(
                    lines=(OrderLineRequest(first, None, 1), OrderLineRequest(second, None, 1)),
                    fulfilment="pickup",
                ),
                hold_minutes=15,
            )
            placed.append(order.order_id)
    past = datetime.now(UTC) - timedelta(minutes=1)
    async with session_scope() as session:
        await session.execute(
            update(Order).where(Order.id.in_(placed)).values(hold_expires_at=past)
        )
        await session.execute(
            update(StockHold).where(StockHold.order_id.in_(placed)).values(expires_at=past)
        )
    return placed


async def statuses(order_ids: list[uuid.UUID]) -> list[str]:
    async with session_scope() as session:
        rows = await session.scalars(select(Order.status).where(Order.id.in_(order_ids)))
        return sorted(set(rows))


async def total_held() -> int:
    async with session_scope() as session:
        rows = await session.scalars(select(DailyStock.held))
        return sum(rows)


async def test_a_second_copy_skips_while_one_is_running(
    due_orders: list[uuid.UUID], deferred_jobs: InMemoryConnector
) -> None:
    async with locks.advisory_lock("orders", "expire_unpaid_orders") as held:
        assert held
        await tasks.expire_unpaid_orders(timestamp=0)  # another copy is running: skip
        assert await statuses(due_orders) == ["awaiting_payment"]

    await tasks.expire_unpaid_orders(timestamp=0)

    assert await statuses(due_orders) == ["expired"]
    assert await total_held() == 0


async def test_copies_started_together_expire_everything_once(
    due_orders: list[uuid.UUID], deferred_jobs: InMemoryConnector
) -> None:
    results = await asyncio.gather(
        *(tasks.expire_unpaid_orders(timestamp=n) for n in range(4)), return_exceptions=True
    )

    assert [r for r in results if isinstance(r, BaseException)] == []
    assert await statuses(due_orders) == ["expired"]
    assert await total_held() == 0


async def test_batches_expiring_side_by_side_do_not_deadlock(
    due_orders: list[uuid.UUID],
) -> None:
    async def batch() -> int:
        async with session_scope() as session:
            return len(await orders.expire_due(session))

    results = await asyncio.gather(*(batch() for _ in range(4)), return_exceptions=True)

    assert [r for r in results if isinstance(r, BaseException)] == []
    assert sum(r for r in results if isinstance(r, int)) == len(due_orders)
    assert await statuses(due_orders) == ["expired"]
    assert await total_held() == 0
