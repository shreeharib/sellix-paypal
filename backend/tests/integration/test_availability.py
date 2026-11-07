"""A Diwali cake for pickup on one day, orders until a last date the merchant picks."""

import uuid
from collections.abc import AsyncIterator
from datetime import date, timedelta

import httpx2
import pytest

from app.core.db import session_scope
from app.main import create_app
from app.modules.channels.models import ChannelConnection
from app.modules.inventory import service as inventory
from app.modules.merchants import service as merchants
from app.modules.orders import service as orders
from app.modules.orders.schemas import OrderLineRequest, OrderRequest
from tests.integration.test_api import bearer, sign_in_as

pytestmark = pytest.mark.anyio


@pytest.fixture
async def api(db: None) -> AsyncIterator[httpx2.AsyncClient]:
    transport = httpx2.ASGITransport(app=create_app())
    async with httpx2.AsyncClient(transport=transport, base_url="http://test") as client:
        yield client


def cake_order(quantity: int = 1) -> OrderRequest:
    return OrderRequest(
        lines=(OrderLineRequest("Diwali cake", None, quantity),), fulfilment="pickup"
    )


async def today_for(shop: ChannelConnection) -> date:
    async with session_scope() as session:
        return merchants.business_date(await merchants.get_merchant(session, shop.merchant_id))


async def quote_for(shop: ChannelConnection, pickup: date) -> orders.Quote:
    async with session_scope() as session:
        return await orders.quote(
            session, merchant_id=shop.merchant_id, business_date=pickup, request=cake_order()
        )


@pytest.fixture
async def cake(
    api: httpx2.AsyncClient, shop: ChannelConnection
) -> tuple[uuid.UUID, date, date, str]:
    """A cake for pickup in 5 days, 40 in total, orders until 3 days from now."""
    today = await today_for(shop)
    pickup, last_order = today + timedelta(days=5), today + timedelta(days=3)
    token = await sign_in_as(shop.merchant_id)
    put = await api.put(
        "/v1/stock/upcoming",
        headers=bearer(token),
        json={
            "from_date": pickup.isoformat(),
            "to_date": pickup.isoformat(),
            "lines": [{"product": "Diwali cake", "price_minor": 120000, "quantity": 40}],
        },
    )
    assert put.status_code == 200, put.text
    products = (await api.get("/v1/products", headers=bearer(token))).json()
    product_id = uuid.UUID(next(p["id"] for p in products if p["name"] == "Diwali cake"))
    patch = await api.patch(
        f"/v1/products/{product_id}",
        headers=bearer(token),
        json={"available_on": pickup.isoformat(), "order_by_date": last_order.isoformat()},
    )
    assert patch.status_code == 200, patch.text
    assert patch.json()["available_on"] == pickup.isoformat()
    assert patch.json()["order_by_date"] == last_order.isoformat()
    return product_id, pickup, last_order, token


async def test_the_cake_can_be_ordered_for_its_day_before_the_last_order_date(
    shop: ChannelConnection, cake: tuple[uuid.UUID, date, date, str]
) -> None:
    _, pickup, _, _ = cake

    offer = await quote_for(shop, pickup)

    assert offer.ok
    assert offer.total_minor == 120000


async def test_the_cake_cant_be_ordered_for_any_other_day(
    shop: ChannelConnection, cake: tuple[uuid.UUID, date, date, str]
) -> None:
    _, pickup, _, _ = cake
    async with session_scope() as session:
        await inventory.set_opening_stock(
            session,
            merchant_id=shop.merchant_id,
            business_date=pickup + timedelta(days=1),
            lines=[inventory.OpeningStockLine("Diwali cake", None, 120000, 5)],
        )

    offer = await quote_for(shop, pickup + timedelta(days=1))

    assert not offer.ok
    assert offer.problems == (f"Diwali cake is only available on {pickup:%d %b}",)


async def test_orders_close_after_the_last_order_date(
    shop: ChannelConnection,
    cake: tuple[uuid.UUID, date, date, str],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _, pickup, last_order, _ = cake
    monkeypatch.setattr(merchants, "business_date", lambda *_a, **_k: last_order)
    assert (await quote_for(shop, pickup)).ok  # the last day itself is still open

    monkeypatch.setattr(merchants, "business_date", lambda *_a, **_k: last_order + timedelta(1))
    offer = await quote_for(shop, pickup)

    assert not offer.ok
    assert offer.problems == (f"Orders for Diwali cake closed on {last_order:%d %b}",)


async def test_customers_menus_hide_closed_items_but_the_merchant_still_sees_them(
    shop: ChannelConnection, cake: tuple[uuid.UUID, date, date, str]
) -> None:
    _, pickup, last_order, _ = cake
    after = last_order + timedelta(days=1)
    today = await today_for(shop)
    async with session_scope() as session:
        open_menu = await inventory.upcoming_stock(
            session, shop.merchant_id, today, 14, ordering_today=today
        )
        closed_menu = await inventory.upcoming_stock(
            session, shop.merchant_id, today, 14, ordering_today=after
        )
        merchant_view = await inventory.upcoming_stock(session, shop.merchant_id, today, 14)

    assert [item.product for item in open_menu[pickup]] == ["Diwali cake"]
    assert pickup not in closed_menu
    assert [item.product for item in merchant_view[pickup]] == ["Diwali cake"]


async def test_the_total_is_the_days_stock_and_cant_be_oversold(
    shop: ChannelConnection, cake: tuple[uuid.UUID, date, date, str]
) -> None:
    _, pickup, _, _ = cake
    async with session_scope() as session:
        offer = await orders.quote(
            session,
            merchant_id=shop.merchant_id,
            business_date=pickup,
            request=cake_order(41),
        )

    assert not offer.ok
    assert offer.problems == ("Diwali cake: only 40 left",)


async def test_dates_are_checked_when_the_merchant_sets_them(
    api: httpx2.AsyncClient, shop: ChannelConnection, cake: tuple[uuid.UUID, date, date, str]
) -> None:
    product_id, pickup, last_order, token = cake
    today = await today_for(shop)
    url = f"/v1/products/{product_id}"

    past = await api.patch(
        url, headers=bearer(token), json={"order_by_date": (today - timedelta(1)).isoformat()}
    )
    late = await api.patch(
        url, headers=bearer(token), json={"order_by_date": (pickup + timedelta(1)).isoformat()}
    )
    earlier_day = await api.patch(
        url, headers=bearer(token), json={"available_on": (last_order - timedelta(1)).isoformat()}
    )

    assert (past.status_code, late.status_code, earlier_day.status_code) == (400, 400, 400)
    assert "after the day it's sold" in late.json()["detail"]


async def test_sending_null_clears_a_date_and_leaving_it_out_keeps_it(
    api: httpx2.AsyncClient, cake: tuple[uuid.UUID, date, date, str]
) -> None:
    product_id, pickup, last_order, token = cake
    url = f"/v1/products/{product_id}"

    renamed = await api.patch(url, headers=bearer(token), json={"description": "Rich and sweet"})
    cleared = await api.patch(url, headers=bearer(token), json={"order_by_date": None})

    assert renamed.json()["available_on"] == pickup.isoformat()
    assert renamed.json()["order_by_date"] == last_order.isoformat()
    assert cleared.json()["available_on"] == pickup.isoformat()
    assert cleared.json()["order_by_date"] is None


async def test_future_stock_for_a_new_item_is_that_days_item_and_not_todays(
    api: httpx2.AsyncClient, shop: ChannelConnection
) -> None:
    today = await today_for(shop)
    pickup, last_order = today + timedelta(days=6), today + timedelta(days=3)
    token = await sign_in_as(shop.merchant_id)
    await api.put(
        "/v1/today/stock",
        headers=bearer(token),
        json={"lines": [{"product": "Brownie", "price_minor": 9000, "quantity": 10}]},
    )

    put = await api.put(
        "/v1/stock/upcoming",
        headers=bearer(token),
        json={
            "from_date": pickup.isoformat(),
            "to_date": pickup.isoformat(),
            "one_day_only": True,
            "last_order_date": last_order.isoformat(),
            "lines": [
                {"product": "Diwali cake", "price_minor": 120000, "quantity": 40},
                {"product": "Brownie", "price_minor": 9000, "quantity": 5},
            ],
        },
    )

    assert put.status_code == 200, put.text
    items = {item["product"]: item for item in put.json()[0]["items"]}
    assert items["Diwali cake"]["opening"] == 40
    assert items["Diwali cake"]["available_on"] == pickup.isoformat()
    assert items["Diwali cake"]["order_by_date"] == last_order.isoformat()
    assert items["Diwali cake"]["variant_id"] is not None
    assert items["Brownie"]["available_on"] is None  # already sold every day: unchanged
    today_view = await api.get("/v1/today", headers=bearer(token))
    assert [row["product"] for row in today_view.json()["stock"]] == ["Brownie"]


async def test_a_one_day_item_cant_be_stocked_on_another_day(
    api: httpx2.AsyncClient, shop: ChannelConnection, cake: tuple[uuid.UUID, date, date, str]
) -> None:
    _, pickup, _, token = cake
    other = pickup + timedelta(days=2)

    response = await api.put(
        "/v1/stock/upcoming",
        headers=bearer(token),
        json={
            "from_date": other.isoformat(),
            "to_date": other.isoformat(),
            "lines": [{"product": "Diwali cake", "price_minor": 120000, "quantity": 3}],
        },
    )

    assert response.status_code == 422
    assert "only sold on" in response.json()["detail"]


async def test_last_order_date_must_fall_between_today_and_the_pickup_day(
    api: httpx2.AsyncClient, shop: ChannelConnection
) -> None:
    today = await today_for(shop)
    pickup = today + timedelta(days=3)
    token = await sign_in_as(shop.merchant_id)

    def body(last: date | None, one_day: bool = True) -> dict[str, object]:
        return {
            "from_date": pickup.isoformat(),
            "to_date": pickup.isoformat(),
            "one_day_only": one_day,
            "last_order_date": last.isoformat() if last else None,
            "lines": [{"product": "Ladoo", "price_minor": 5000, "quantity": 20}],
        }

    late = await api.put(
        "/v1/stock/upcoming", headers=bearer(token), json=body(pickup + timedelta(1))
    )
    past = await api.put(
        "/v1/stock/upcoming", headers=bearer(token), json=body(today - timedelta(1))
    )
    loose = await api.put(
        "/v1/stock/upcoming", headers=bearer(token), json=body(today, one_day=False)
    )

    assert (late.status_code, past.status_code, loose.status_code) == (400, 400, 400)
