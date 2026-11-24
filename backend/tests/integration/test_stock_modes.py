"""Stock modes on the server: no-count items are always orderable; kept stock carries over.

`made_to_order` and `unlimited` items have no count: they are on every menu, any quantity up to
a per-line limit, with no hold and no daily_stock change. `inventory` items keep their count from
day to day: the first read of a new day carries the latest earlier day's remainder forward.
"""

import asyncio
import uuid
from collections.abc import AsyncIterator
from datetime import UTC, date, datetime, timedelta

import httpx2
import pytest
from sqlalchemy import func, select

from app.core.db import session_scope
from app.main import create_app
from app.modules.catalog import service as catalog
from app.modules.channels.models import ChannelConnection
from app.modules.conversations.models import Conversation
from app.modules.inventory import service as inventory
from app.modules.inventory.models import DailyStock, StockHold
from app.modules.inventory.schemas import (
    LedgerRow,
    OpeningStockLine,
    RolloverItemSelection,
    StockItem,
)
from app.modules.merchants import service as merchants
from app.modules.orders import service as orders
from app.modules.orders.models import Order
from app.modules.orders.schemas import OrderLineRequest, OrderRequest, PlacedOrder
from tests.integration.factories import start_conversation
from tests.integration.test_api import bearer, sign_in_as

pytestmark = pytest.mark.anyio

LIMIT = inventory.NO_COUNT_LINE_LIMIT


@pytest.fixture
async def api(db: None) -> AsyncIterator[httpx2.AsyncClient]:
    transport = httpx2.ASGITransport(app=create_app())
    async with httpx2.AsyncClient(transport=transport, base_url="http://test") as client:
        yield client


async def shop_today(shop: ChannelConnection) -> date:
    async with session_scope() as session:
        return merchants.business_date(await merchants.get_merchant(session, shop.merchant_id))


def request(*lines: tuple[str, int]) -> OrderRequest:
    return OrderRequest(
        lines=tuple(OrderLineRequest(product, None, quantity) for product, quantity in lines),
        fulfilment="pickup",
    )


async def menu(shop: ChannelConnection, day: date) -> dict[str, StockItem]:
    """What customers can order for `day`, as the assistant sees it."""
    today = await shop_today(shop)
    async with session_scope() as session:
        stock = await inventory.today_stock(session, shop.merchant_id, day, ordering_today=today)
    return {item.label: item for item in stock}


async def ledger(shop: ChannelConnection, day: date) -> dict[str, LedgerRow]:
    async with session_scope() as session:
        rows = await inventory.day_ledger(session, shop.merchant_id, day)
    return {
        row.product if row.variant is None else f"{row.product} ({row.variant})": row
        for row in rows
    }


async def quote(shop: ChannelConnection, day: date, *lines: tuple[str, int]) -> orders.Quote:
    async with session_scope() as session:
        return await orders.quote(
            session, merchant_id=shop.merchant_id, business_date=day, request=request(*lines)
        )


async def place(shop: ChannelConnection, day: date, *lines: tuple[str, int]) -> PlacedOrder:
    turn = await start_conversation(message_id=f"m-{uuid.uuid4()}")
    async with session_scope() as session:
        conversation = await session.get(Conversation, turn.conversation_id)
        assert conversation is not None
        return await orders.place_order(
            session,
            merchant_id=shop.merchant_id,
            customer_id=conversation.customer_id,
            conversation_id=conversation.id,
            business_date=day,
            request=request(*lines),
            hold_minutes=15,
        )


async def pay(placed: PlacedOrder) -> str:
    async with session_scope() as session:
        result = await orders.record_payment(
            session,
            placed.order_id,
            amount_minor=placed.total_minor,
            currency=placed.currency,
            actor="merchant",
        )
    return result.outcome


async def status(order_id: uuid.UUID) -> str:
    async with session_scope() as session:
        order = await session.get(Order, order_id)
    assert order is not None
    return order.status


async def held_quantities(order_id: uuid.UUID) -> list[int]:
    async with session_scope() as session:
        rows = await session.scalars(
            select(StockHold.quantity).where(StockHold.order_id == order_id)
        )
        return sorted(rows)


async def rows_on(shop: ChannelConnection, day: date) -> int:
    async with session_scope() as session:
        count = await session.scalar(
            select(func.count())
            .select_from(DailyStock)
            .where(DailyStock.merchant_id == shop.merchant_id, DailyStock.business_date == day)
        )
    return int(count or 0)


async def variant_id(shop: ChannelConnection, day: date, label: str) -> uuid.UUID:
    return (await ledger(shop, day))[label].variant_id


# --- made_to_order and unlimited -------------------------------------------------------------


@pytest.fixture
async def no_count(shop: ChannelConnection) -> ChannelConnection:
    """As the app saves them: no-count items at quantity 0, next to a counted daily batch."""
    today = await shop_today(shop)
    async with session_scope() as session:
        await inventory.set_opening_stock(
            session,
            merchant_id=shop.merchant_id,
            business_date=today,
            lines=[
                OpeningStockLine("Custom cake", None, 150000, 0, stock_mode="made_to_order"),
                OpeningStockLine("Gift wrap", None, 2000, 0, stock_mode="unlimited"),
                OpeningStockLine("Brownie", None, 9000, 5, stock_mode="daily"),
            ],
        )
    return shop


async def test_no_count_items_are_on_the_menu_today_and_on_days_with_no_stock_set(
    no_count: ChannelConnection,
) -> None:
    today = await shop_today(no_count)

    stock = await menu(no_count, today)
    tomorrow = await menu(no_count, today + timedelta(days=1))

    assert {label: (item.available, item.stock_mode) for label, item in stock.items()} == {
        "Brownie": (5, "daily"),
        "Custom cake": (LIMIT, "made_to_order"),
        "Gift wrap": (LIMIT, "unlimited"),
    }
    assert sorted(tomorrow) == ["Custom cake", "Gift wrap"]  # the batch is for today only


async def test_the_today_screen_shows_no_count_items_as_available(
    api: httpx2.AsyncClient, no_count: ChannelConnection
) -> None:
    async with session_scope() as session:  # added with no stock row at all
        await catalog.upsert_variant(
            session,
            merchant_id=no_count.merchant_id,
            product_name="Mehendi booking",
            price_minor=50000,
            stock_mode="made_to_order",
        )
    token = await sign_in_as(no_count.merchant_id)

    today = await api.get("/v1/today", headers=bearer(token))

    assert today.status_code == 200
    rows = {row["product"]: row for row in today.json()["stock"]}
    assert (rows["Custom cake"]["available"], rows["Custom cake"]["stock_mode"]) == (
        LIMIT,
        "made_to_order",
    )
    assert (rows["Gift wrap"]["available"], rows["Gift wrap"]["stock_mode"]) == (LIMIT, "unlimited")
    assert rows["Mehendi booking"]["available"] == LIMIT
    assert rows["Brownie"]["available"] == 5


async def test_no_count_items_are_ordered_and_paid_without_holding_stock(
    no_count: ChannelConnection,
) -> None:
    today = await shop_today(no_count)
    lines = (("Custom cake", 3), ("Gift wrap", 50), ("Brownie", 2))
    offer = await quote(no_count, today, *lines)
    assert offer.ok, offer.problems

    placed = await place(no_count, today, *lines)

    assert placed.total_minor == 3 * 150000 + 50 * 2000 + 2 * 9000
    assert await held_quantities(placed.order_id) == [2]  # only the brownies are held
    before = await ledger(no_count, today)
    assert (before["Brownie"].held, before["Brownie"].available) == (2, 3)

    assert await pay(placed) == "paid"

    after = await ledger(no_count, today)
    assert await status(placed.order_id) == "paid"
    assert (after["Brownie"].held, after["Brownie"].sold) == (0, 2)
    for label in ("Custom cake", "Gift wrap"):
        row = after[label]
        assert (row.opening, row.held, row.sold, row.available) == (0, 0, 0, LIMIT)


async def test_unpaid_no_count_orders_expire_and_cancel_cleanly(
    no_count: ChannelConnection,
) -> None:
    today = await shop_today(no_count)
    late = await place(no_count, today, ("Custom cake", 1), ("Brownie", 1))
    dropped = await place(no_count, today, ("Gift wrap", 4))

    async with session_scope() as session:
        await orders.cancel_order(session, dropped.order_id, merchant_id=no_count.merchant_id)
    async with session_scope() as session:
        expired = await orders.expire_due(session, now=datetime.now(UTC) + timedelta(minutes=16))

    assert [order.order_id for order in expired] == [late.order_id]
    assert (await status(late.order_id), await status(dropped.order_id)) == ("expired", "cancelled")
    rows = await ledger(no_count, today)
    assert (rows["Brownie"].held, rows["Brownie"].available) == (0, 5)
    assert (rows["Custom cake"].held, rows["Gift wrap"].held) == (0, 0)

    # Paid after its hold ran out: the cake has no count to run short of; the brownie is still
    # there to sell.
    assert await pay(late) == "paid"
    assert (await ledger(no_count, today))["Brownie"].sold == 1


async def test_a_no_count_line_has_a_per_order_limit(no_count: ChannelConnection) -> None:
    today = await shop_today(no_count)

    too_many = await quote(no_count, today, ("Custom cake", LIMIT + 1))
    most = await quote(no_count, today, ("Custom cake", LIMIT))

    assert too_many.problems == (f"Custom cake: at most {LIMIT} in one order",)
    assert most.ok


async def test_a_one_day_no_count_item_keeps_its_day_and_last_order_date(
    no_count: ChannelConnection, monkeypatch: pytest.MonkeyPatch
) -> None:
    today = await shop_today(no_count)
    sale_day, last_order = today + timedelta(days=4), today + timedelta(days=2)
    async with session_scope() as session:
        await catalog.set_sold_on(
            session, no_count.merchant_id, ["Custom cake"], day=sale_day, order_by_date=last_order
        )

    assert "Custom cake" not in await menu(no_count, today)
    assert (await quote(no_count, today, ("Custom cake", 1))).problems == (
        f"Custom cake is only available on {sale_day:%d %b}",
    )
    assert (await quote(no_count, sale_day, ("Custom cake", 1))).ok

    monkeypatch.setattr(merchants, "business_date", lambda *_a, **_k: last_order + timedelta(1))
    assert (await quote(no_count, sale_day, ("Custom cake", 1))).problems == (
        f"Orders for Custom cake closed on {last_order:%d %b}",
    )


# --- inventory: kept until sold --------------------------------------------------------------


@pytest.fixture
async def kept(shop: ChannelConnection) -> tuple[ChannelConnection, date]:
    """An anklet counted two days ago (5, 2 sold at the counter), then a closed day with no stock
    set; kurtis counted yesterday (4); and yesterday's daily brownies (6), which don't carry."""
    today = await shop_today(shop)
    two_days_ago, yesterday = today - timedelta(days=2), today - timedelta(days=1)
    async with session_scope() as session:
        await inventory.set_opening_stock(
            session,
            merchant_id=shop.merchant_id,
            business_date=two_days_ago,
            lines=[OpeningStockLine("Silver anklet", None, 120000, 5, stock_mode="inventory")],
        )
        await inventory.set_opening_stock(
            session,
            merchant_id=shop.merchant_id,
            business_date=yesterday,
            lines=[
                OpeningStockLine("Kurti", "M", 89900, 4, stock_mode="inventory"),
                OpeningStockLine("Brownie", None, 9000, 6, stock_mode="daily"),
            ],
        )
    anklet = await variant_id(shop, two_days_ago, "Silver anklet")
    async with session_scope() as session:
        await inventory.record_counter_sale(
            session,
            merchant_id=shop.merchant_id,
            variant_id=anklet,
            business_date=two_days_ago,
            quantity=2,
        )
    return shop, today


async def test_kept_stock_carries_over_a_closed_day_with_what_was_left(
    kept: tuple[ChannelConnection, date],
) -> None:
    shop, today = kept

    stock = await menu(shop, today)
    rows = await ledger(shop, today)

    assert {label: item.available for label, item in stock.items()} == {
        "Kurti (M)": 4,
        "Silver anklet": 3,
    }
    assert (rows["Silver anklet"].opening, rows["Kurti (M)"].opening) == (3, 4)
    assert "Brownie" not in rows  # daily batches start fresh each day


async def test_the_carry_happens_once_a_day(kept: tuple[ChannelConnection, date]) -> None:
    shop, today = kept
    await menu(shop, today)

    placed = await place(shop, today, ("Silver anklet", 1))
    again = await menu(shop, today)

    assert placed.total_minor == 120000
    assert again["Silver anklet"].available == 2
    assert await rows_on(shop, today) == 2  # the anklet and the kurti, once each


async def test_two_first_reads_at_once_carry_only_once(
    kept: tuple[ChannelConnection, date],
) -> None:
    shop, today = kept

    async def read() -> int:
        async with session_scope() as session:
            stock = await inventory.today_stock(session, shop.merchant_id, today)
        return next(item.available for item in stock if item.label == "Silver anklet")

    seen = await asyncio.gather(*(read() for _ in range(8)))

    assert seen == [3] * 8
    assert await rows_on(shop, today) == 2
    assert (await ledger(shop, today))["Silver anklet"].opening == 3


async def test_the_merchants_own_count_and_coming_days_are_not_carried_over(
    kept: tuple[ChannelConnection, date],
) -> None:
    shop, today = kept
    async with session_scope() as session:  # counted again this morning: 6, not yesterday's 4
        await inventory.set_opening_stock(
            session,
            merchant_id=shop.merchant_id,
            business_date=today,
            lines=[OpeningStockLine("Kurti", "M", 89900, 6, stock_mode="inventory")],
        )
        await inventory.today_stock(session, shop.merchant_id, today + timedelta(days=3))

    assert (await menu(shop, today))["Kurti (M)"].available == 6
    assert await rows_on(shop, today + timedelta(days=3)) == 0  # the same units, not new ones


async def test_kept_stock_is_not_offered_again_as_yesterdays_leftovers(
    kept: tuple[ChannelConnection, date],
) -> None:
    shop, today = kept
    kurti = await variant_id(shop, today - timedelta(days=1), "Kurti (M)")
    await menu(shop, today)  # carried

    async with session_scope() as session:
        leftovers = await inventory.get_yesterday_leftovers(session, shop.merchant_id, today)
        rolled = await inventory.apply_rollover_selection(
            session,
            merchant_id=shop.merchant_id,
            business_date=today,
            selections=[RolloverItemSelection(variant_id=kurti, rollover_quantity=4)],
        )

    assert [item.product for item in leftovers] == ["Brownie"]
    assert rolled == 0
    assert (await menu(shop, today))["Kurti (M)"].available == 4  # not 8


async def test_a_removed_kept_item_is_not_carried(kept: tuple[ChannelConnection, date]) -> None:
    shop, today = kept
    async with session_scope() as session:
        anklet = (await catalog.products_by_names(session, shop.merchant_id, ["Silver anklet"]))[
            "silver anklet"
        ]
        await catalog.update_product(
            session, merchant_id=shop.merchant_id, product_id=anklet.id, is_active=False
        )

    assert "Silver anklet" not in await menu(shop, today)
    assert await rows_on(shop, today) == 1  # the kurti only


async def _kurti_order(shop: ChannelConnection, day: date) -> PlacedOrder:
    turn = await start_conversation(message_id=f"m-{uuid.uuid4()}")
    async with session_scope() as session:
        conversation = await session.get(Conversation, turn.conversation_id)
        assert conversation is not None
        return await orders.place_order(
            session,
            merchant_id=shop.merchant_id,
            customer_id=conversation.customer_id,
            conversation_id=conversation.id,
            business_date=day,
            request=OrderRequest(lines=(OrderLineRequest("Kurti", "M", 1),), fulfilment="pickup"),
            hold_minutes=15,
        )


async def test_a_kept_item_released_after_the_carry_goes_back_on_todays_shelf(
    kept: tuple[ChannelConnection, date],
) -> None:
    shop, today = kept
    placed = await _kurti_order(shop, today - timedelta(days=1))  # held before midnight
    assert (await menu(shop, today))["Kurti (M)"].available == 3  # carried: 4 less the hold

    async with session_scope() as session:  # the hold runs out after midnight
        await orders.expire_due(session, now=datetime.now(UTC) + timedelta(minutes=16))

    assert await status(placed.order_id) == "expired"
    assert (await menu(shop, today))["Kurti (M)"].available == 4


async def test_a_refunded_kept_item_from_an_earlier_day_is_back_on_sale_today(
    kept: tuple[ChannelConnection, date],
) -> None:
    shop, today = kept
    placed = await _kurti_order(shop, today - timedelta(days=1))
    assert await pay(placed) == "paid"
    assert (await menu(shop, today))["Kurti (M)"].available == 3  # carried: 4 less the sale

    async with session_scope() as session:
        await orders.refund_order(session, placed.order_id, restock=True)

    assert (await menu(shop, today))["Kurti (M)"].available == 4


async def test_a_quote_from_before_midnight_is_not_confirmed_after_it(
    kept: tuple[ChannelConnection, date],
) -> None:
    from app.modules.conversations.models import Message
    from app.modules.orders.schemas import QuoteRefused, SavedQuote

    shop, today = kept
    turn = await start_conversation(message_id=f"m-{uuid.uuid4()}")
    async with session_scope() as session:
        conversation = await session.get(Conversation, turn.conversation_id)
        assert conversation is not None
        saved = await orders.save_quote(
            session,
            merchant_id=shop.merchant_id,
            conversation_id=conversation.id,
            customer_id=conversation.customer_id,
            business_date=today - timedelta(days=1),
            request=OrderRequest(lines=(OrderLineRequest("Kurti", "M", 1),), fulfilment="pickup"),
            expires_at=datetime.now(UTC) + timedelta(hours=1),
        )
        assert isinstance(saved, SavedQuote)
        card = await session.scalar(select(Message.id).limit(1))
        assert card is not None
        await orders.mark_quote_shown(session, saved.id, card)

    with pytest.raises(QuoteRefused) as refused:
        async with session_scope() as session:
            await orders.confirm_quote(
                session, quote_id=saved.id, conversation_id=conversation.id, hold_minutes=15
            )

    assert refused.value.code == "expired"
