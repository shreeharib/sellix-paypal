"""Removing, restoring and renaming a product through PATCH /v1/products/{id}."""

import uuid
from collections.abc import AsyncIterator
from dataclasses import dataclass
from datetime import date

import httpx2
import pytest

from app.core.db import session_scope
from app.main import create_app
from app.modules.channels.models import ChannelConnection
from app.modules.conversations.models import Conversation
from app.modules.inventory import service as inventory
from app.modules.merchants import service as merchants
from app.modules.orders import service as orders
from app.modules.orders.schemas import OrderLineRequest, OrderRequest
from tests.integration.factories import start_conversation
from tests.integration.test_api import bearer, sign_in_as

pytestmark = pytest.mark.anyio


@dataclass
class Shop:
    connection: ChannelConnection
    headers: dict[str, str]
    today: date
    brownie: uuid.UUID
    cake: uuid.UUID
    paid_order: uuid.UUID


@pytest.fixture
async def api(db: None) -> AsyncIterator[httpx2.AsyncClient]:
    transport = httpx2.ASGITransport(app=create_app())
    async with httpx2.AsyncClient(transport=transport, base_url="http://test") as client:
        yield client


@pytest.fixture
async def world(api: httpx2.AsyncClient, shop: ChannelConnection) -> Shop:
    """Brownies (5, 2 of them sold in a paid order) and a made-to-order cake."""
    headers = bearer(await sign_in_as(shop.merchant_id))
    put = await api.put(
        "/v1/today/stock",
        headers=headers,
        json={
            "lines": [
                {"product": "Brownie", "price_minor": 9000, "quantity": 5},
                {
                    "product": "Custom cake",
                    "price_minor": 150000,
                    "quantity": 0,
                    "stock_mode": "made_to_order",
                },
            ]
        },
    )
    assert put.status_code == 200, put.text
    ids = {
        p["name"]: uuid.UUID(p["id"])
        for p in (await api.get("/v1/products", headers=headers)).json()
    }
    turn = await start_conversation()
    async with session_scope() as session:
        today = merchants.business_date(await merchants.get_merchant(session, shop.merchant_id))
        conversation = await session.get(Conversation, turn.conversation_id)
        assert conversation is not None
        placed = await orders.place_order(
            session,
            merchant_id=shop.merchant_id,
            customer_id=conversation.customer_id,
            conversation_id=conversation.id,
            business_date=today,
            request=OrderRequest(
                lines=(OrderLineRequest("Brownie", None, 2),), fulfilment="pickup"
            ),
            hold_minutes=15,
        )
    async with session_scope() as session:
        await orders.record_payment(
            session, placed.order_id, amount_minor=18000, currency="INR", actor="merchant"
        )
    return Shop(shop, headers, today, ids["Brownie"], ids["Custom cake"], placed.order_id)


async def names(api: httpx2.AsyncClient, world: Shop, path: str) -> list[str]:
    response = await api.get(path, headers=world.headers)
    assert response.status_code == 200, response.text
    return sorted(p["name"] for p in response.json())


async def today_products(api: httpx2.AsyncClient, world: Shop) -> dict[str, dict[str, object]]:
    response = await api.get("/v1/today", headers=world.headers)
    assert response.status_code == 200, response.text
    return {row["product"]: row for row in response.json()["stock"]}


async def customer_menu(world: Shop) -> list[str]:
    async with session_scope() as session:
        stock = await inventory.today_stock(
            session, world.connection.merchant_id, world.today, ordering_today=world.today
        )
    return sorted(item.label for item in stock)


async def patch(
    api: httpx2.AsyncClient, world: Shop, product: uuid.UUID, **body: object
) -> httpx2.Response:
    return await api.patch(f"/v1/products/{product}", headers=world.headers, json=body)


async def test_a_removed_product_leaves_every_list_but_its_past_orders(
    api: httpx2.AsyncClient, world: Shop
) -> None:
    removed = await patch(api, world, world.brownie, is_active=False)

    assert removed.status_code == 200, removed.text
    assert removed.json()["is_active"] is False
    assert await names(api, world, "/v1/products") == ["Custom cake"]
    assert await names(api, world, "/v1/products?include_inactive=true") == [
        "Brownie",
        "Custom cake",
    ]
    assert "Brownie" not in await today_products(api, world)
    assert await customer_menu(world) == ["Custom cake"]
    search = await api.get("/v1/products/search?q=brownie", headers=world.headers)
    assert search.json()["items"] == []
    async with session_scope() as session:
        offer = await orders.quote(
            session,
            merchant_id=world.connection.merchant_id,
            business_date=world.today,
            request=OrderRequest(
                lines=(OrderLineRequest("Brownie", None, 1),), fulfilment="pickup"
            ),
        )
        past = await orders.get_order(session, world.paid_order, world.connection.merchant_id)
    assert offer.problems == ("Brownie isn't in today's stock",)
    assert past is not None
    assert [(item.product, item.quantity) for item in past.items] == [("Brownie", 2)]


async def test_a_removed_product_comes_back_with_its_stock(
    api: httpx2.AsyncClient, world: Shop
) -> None:
    await patch(api, world, world.brownie, is_active=False)

    restored = await patch(api, world, world.brownie, is_active=True)

    assert restored.status_code == 200, restored.text
    assert restored.json()["is_active"] is True
    assert await names(api, world, "/v1/products") == ["Brownie", "Custom cake"]
    assert (await today_products(api, world))["Brownie"]["available"] == 3
    assert await customer_menu(world) == ["Brownie", "Custom cake"]


async def test_a_removed_made_to_order_item_is_off_the_menu(
    api: httpx2.AsyncClient, world: Shop
) -> None:
    await patch(api, world, world.cake, is_active=False)

    assert await customer_menu(world) == ["Brownie"]
    assert "Custom cake" not in await today_products(api, world)


async def test_renaming_keeps_the_same_product_and_variant(
    api: httpx2.AsyncClient, world: Shop
) -> None:
    before = (await api.get(f"/v1/products/{world.brownie}", headers=world.headers)).json()

    renamed = await patch(api, world, world.brownie, name="Fudge brownie")
    # The app then saves a new price through the stock line, under the new name.
    put = await api.put(
        "/v1/today/stock",
        headers=world.headers,
        json={"lines": [{"product": "Fudge brownie", "price_minor": 9500, "quantity": 5}]},
    )

    assert renamed.status_code == 200, renamed.text
    assert put.status_code == 200, put.text
    products = (await api.get("/v1/products?include_inactive=true", headers=world.headers)).json()
    assert sorted(p["name"] for p in products) == ["Custom cake", "Fudge brownie"]
    after = next(p for p in products if p["name"] == "Fudge brownie")
    assert after["id"] == str(world.brownie)
    assert [(v["id"], v["price_minor"]) for v in after["variants"]] == [
        (before["variants"][0]["id"], 9500)
    ]
    row = (await today_products(api, world))["Fudge brownie"]
    assert (row["variant_id"], row["sold"], row["available"]) == (before["variants"][0]["id"], 2, 3)
    assert await customer_menu(world) == ["Custom cake", "Fudge brownie"]
    async with session_scope() as session:
        past = await orders.get_order(session, world.paid_order, world.connection.merchant_id)
    assert past is not None and [item.product for item in past.items] == ["Brownie"]


async def test_a_rename_to_a_name_in_use_or_a_blank_name_is_refused(
    api: httpx2.AsyncClient, world: Shop
) -> None:
    taken = await patch(api, world, world.brownie, name="custom CAKE")
    blank = await patch(api, world, world.brownie, name="   ")

    assert taken.status_code == 409, taken.text
    assert blank.status_code == 422, blank.text
    assert await names(api, world, "/v1/products") == ["Brownie", "Custom cake"]
