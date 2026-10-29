"""Orders for another day: per-day stock set ahead; customers pre-order and pay now."""

import uuid
from datetime import date, timedelta

import httpx2
import pytest
from sqlalchemy import select

from app.core.db import session_scope
from app.main import create_app
from app.modules.agent import items
from app.modules.agent import service as agent
from app.modules.channels.models import ChannelConnection
from app.modules.channels.schemas import IncomingMessage
from app.modules.conversations import service as conversations
from app.modules.inventory import service as inventory
from app.modules.merchants import service as merchants
from app.modules.orders.models import Order, QuoteRecord
from tests.integration.factories import CUSTOMER_ID, SHOP_ACCOUNT_ID, Instagram, ScriptedModel
from tests.integration.test_api import bearer, sign_in_as

pytestmark = pytest.mark.anyio


async def today(shop: ChannelConnection) -> date:
    async with session_scope() as session:
        return merchants.business_date(await merchants.get_merchant(session, shop.merchant_id))


async def set_upcoming(shop: ChannelConnection, start: date, end: date) -> httpx2.Response:
    token = await sign_in_as(shop.merchant_id)
    async with httpx2.AsyncClient(
        transport=httpx2.ASGITransport(app=create_app()), base_url="http://test"
    ) as api:
        return await api.put(
            "/v1/stock/upcoming",
            headers=bearer(token),
            json={
                "from_date": start.isoformat(),
                "to_date": end.isoformat(),
                "lines": [{"product": "Banana bread", "price_minor": 25000, "quantity": 20}],
            },
        )


async def banana_bread(shop: ChannelConnection, day: date) -> tuple[str, int]:
    async with session_scope() as session:
        stock = await inventory.today_stock(session, shop.merchant_id, day)
    [item] = [s for s in stock if s.product == "Banana bread"]
    assert item.variant_id is not None
    return items.ref(item.variant_id), item.available


async def customer_says(text: str, mid: str, quick_reply: str | None = None) -> uuid.UUID:
    async with session_scope() as session:
        turn = await conversations.handle_incoming(
            session,
            IncomingMessage(
                channel="instagram",
                shop_account_id=SHOP_ACCOUNT_ID,
                customer_id=CUSTOMER_ID,
                message_id=mid,
                text=text,
                quick_reply_payload=quick_reply,
            ),
        )
    assert turn is not None
    await agent.run_turn(turn.conversation_id)
    return turn.conversation_id


async def test_the_merchant_sets_stock_for_the_next_days(v2_shop: ChannelConnection) -> None:
    start = await today(v2_shop) + timedelta(days=1)

    response = await set_upcoming(v2_shop, start, start + timedelta(days=4))

    assert response.status_code == 200
    assert [day["date"] for day in response.json()] == [
        (start + timedelta(days=n)).isoformat() for n in range(5)
    ]
    assert response.json()[0]["items"][0]["available"] == 20


async def test_dates_in_the_past_or_too_far_ahead_are_refused(v2_shop: ChannelConnection) -> None:
    now = await today(v2_shop)

    past = await set_upcoming(v2_shop, now - timedelta(days=1), now + timedelta(days=1))
    far = await set_upcoming(v2_shop, now + timedelta(days=1), now + timedelta(days=40))

    assert (past.status_code, far.status_code) == (400, 400)


async def test_a_customer_pre_orders_for_a_later_day_and_pays_now(
    v2_shop: ChannelConnection, model: ScriptedModel, instagram: Instagram
) -> None:
    now = await today(v2_shop)
    pickup = now + timedelta(days=2)
    await set_upcoming(v2_shop, now + timedelta(days=1), now + timedelta(days=5))
    bread, _ = await banana_bread(v2_shop, pickup)
    model.then(
        [
            (
                "update_order_draft",
                {
                    "items": [{"item_id": bread, "quantity": 2}],
                    "fulfilment": "pickup",
                    "date": pickup.isoformat(),
                },
            )
        ],
        [("create_quote", {})],
        [("send_reply", {"text": "Confirm with the button!", "language": "en"})],
    )

    await customer_says("2 banana breads for pickup day after tomorrow", "m-1")

    system = model.calls[0][0][0].content
    assert "Coming up" in system and bread in system
    card = instagram.texts()[0]
    assert f"{pickup:%a} {pickup.day} {pickup:%b}" in card  # e.g. "Sat 1 Nov"
    assert "₹500" in card

    async with session_scope() as session:
        quote = await session.scalar(select(QuoteRecord))
    assert quote is not None and quote.business_date == pickup
    model.then([("send_reply", {"text": "Thank you!", "language": "en"})])
    await customer_says("Confirm", "m-2", quick_reply=f"CONFIRM:{quote.id}")

    async with session_scope() as session:
        order = await session.scalar(select(Order))
    assert order is not None and order.business_date == pickup
    assert any("upi://pay" in text for text in instagram.texts())  # pay now
    assert (await banana_bread(v2_shop, pickup))[1] == 18  # held on that day
    assert (await banana_bread(v2_shop, pickup + timedelta(days=1)))[1] == 20


@pytest.mark.parametrize(
    ("days_ahead", "code"),
    [(-1, "invalid_date"), (30, "too_far_ahead")],
)
async def test_order_dates_are_checked_by_code(
    v2_shop: ChannelConnection,
    model: ScriptedModel,
    instagram: Instagram,
    days_ahead: int,
    code: str,
) -> None:
    now = await today(v2_shop)
    await set_upcoming(v2_shop, now + timedelta(days=1), now + timedelta(days=3))
    bread, _ = await banana_bread(v2_shop, now + timedelta(days=1))
    model.then(
        [
            (
                "update_order_draft",
                {
                    "items": [{"item_id": bread, "quantity": 1}],
                    "date": (now + timedelta(days=days_ahead)).isoformat(),
                },
            )
        ],
        [("send_reply", {"text": "Which day?", "language": "en"})],
    )

    await customer_says("banana bread", "m-1")

    result = [m.content for m in model.calls[-1][0] if m.role == "tool"][-1]
    assert code in result


async def test_an_item_not_stocked_on_the_chosen_day_is_a_stock_problem(
    v2_shop: ChannelConnection, model: ScriptedModel, instagram: Instagram
) -> None:
    now = await today(v2_shop)
    await set_upcoming(v2_shop, now + timedelta(days=1), now + timedelta(days=2))
    bread, _ = await banana_bread(v2_shop, now + timedelta(days=1))
    model.then(
        [
            (
                "update_order_draft",
                {
                    "items": [{"item_id": bread, "quantity": 1}],
                    "fulfilment": "pickup",
                    "date": (now + timedelta(days=5)).isoformat(),
                },
            )
        ],
        [("send_reply", {"text": "Not that day, sorry.", "language": "en"})],
    )

    await customer_says("banana bread on friday", "m-1")

    result = [m.content for m in model.calls[-1][0] if m.role == "tool"][-1]
    assert "isn't available on" in result
