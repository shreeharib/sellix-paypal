"""GET /v1/orders/{id}, and paging the orders list with `before`."""

import uuid
from collections.abc import AsyncIterator

import httpx2
import pytest

from app.core.db import session_scope
from app.main import create_app
from app.modules.channels.models import ChannelConnection
from app.modules.conversations.models import Conversation
from app.modules.merchants import service as merchants
from app.modules.orders import service as orders
from app.modules.orders.schemas import OrderLineRequest, OrderRequest
from tests.integration.factories import start_conversation
from tests.integration.test_api import bearer, sign_in_as

pytestmark = pytest.mark.anyio


@pytest.fixture
async def api(db: None) -> AsyncIterator[httpx2.AsyncClient]:
    transport = httpx2.ASGITransport(app=create_app())
    async with httpx2.AsyncClient(transport=transport, base_url="http://test") as client:
        yield client


async def place_orders(shop: ChannelConnection, count: int) -> list[uuid.UUID]:
    """`count` orders of one cookie each, oldest first."""
    turn = await start_conversation()
    placed: list[uuid.UUID] = []
    for _ in range(count):
        async with session_scope() as session:
            merchant = await merchants.get_merchant(session, shop.merchant_id)
            conversation = await session.get(Conversation, turn.conversation_id)
            assert conversation is not None
            order = await orders.place_order(
                session,
                merchant_id=shop.merchant_id,
                customer_id=conversation.customer_id,
                conversation_id=conversation.id,
                business_date=merchants.business_date(merchant),
                request=OrderRequest(
                    lines=(OrderLineRequest("Scoop cookie", "Chocolate", 1),),
                    fulfilment="pickup",
                ),
                hold_minutes=15,
            )
        placed.append(order.order_id)
    return placed


async def test_one_order_by_id_is_the_same_object_as_in_the_list(
    api: httpx2.AsyncClient, v2_shop: ChannelConnection
) -> None:
    [order_id] = await place_orders(v2_shop, 1)
    headers = bearer(await sign_in_as(v2_shop.merchant_id))

    one = await api.get(f"/v1/orders/{order_id}", headers=headers)
    listed = await api.get("/v1/orders", headers=headers)
    missing = await api.get(f"/v1/orders/{uuid.uuid4()}", headers=headers)

    assert one.status_code == 200
    assert one.json() == listed.json()[0]
    assert one.json()["items"][0]["product"] == "Scoop cookie"
    assert missing.status_code == 404


async def test_another_shops_order_is_not_found(
    api: httpx2.AsyncClient, v2_shop: ChannelConnection
) -> None:
    [order_id] = await place_orders(v2_shop, 1)
    async with session_scope() as session:
        other = await merchants.create_merchant(session, name="Other shop")
    intruder = bearer(await sign_in_as(other.id, subject="17841400000009999"))

    response = await api.get(f"/v1/orders/{order_id}", headers=intruder)

    assert response.status_code == 404


async def test_the_orders_list_pages_with_before(
    api: httpx2.AsyncClient, v2_shop: ChannelConnection
) -> None:
    oldest, middle, newest = await place_orders(v2_shop, 3)
    headers = bearer(await sign_in_as(v2_shop.merchant_id))

    first = (await api.get("/v1/orders", headers=headers, params={"limit": 2})).json()
    second = (
        await api.get(
            "/v1/orders", headers=headers, params={"limit": 2, "before": first[-1]["created_at"]}
        )
    ).json()
    filtered = (
        await api.get(
            "/v1/orders",
            headers=headers,
            params={"before": first[0]["created_at"], "status": "paid"},
        )
    ).json()

    assert [row["id"] for row in first] == [str(newest), str(middle)]
    assert [row["id"] for row in second] == [str(oldest)]
    assert filtered == []  # the other filters still apply
