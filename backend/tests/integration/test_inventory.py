from datetime import date

import pytest
from sqlalchemy import update

from app.core.db import session_scope
from app.modules.channels.models import ChannelConnection
from app.modules.inventory import service as inventory
from app.modules.inventory.models import DailyStock
from app.modules.inventory.schemas import OpeningStockLine

pytestmark = pytest.mark.anyio

TODAY = date(2026, 10, 25)


async def test_opening_stock_creates_products_and_shows_in_todays_stock(
    shop: ChannelConnection,
) -> None:
    async with session_scope() as session:
        await inventory.set_opening_stock(
            session,
            merchant_id=shop.merchant_id,
            business_date=TODAY,
            lines=[
                OpeningStockLine("Scoop cookie", "Chocolate", 6000, 10),
                OpeningStockLine("Scoop cookie", "Red velvet", 7000, 10),
                OpeningStockLine("Brownie", None, 9000, 15),
            ],
        )
        # A later update for the same day replaces the opening count and the price.
        await inventory.set_opening_stock(
            session,
            merchant_id=shop.merchant_id,
            business_date=TODAY,
            lines=[OpeningStockLine("scoop cookie", "chocolate", 6500, 12)],
        )

    async with session_scope() as session:
        stock = await inventory.today_stock(session, shop.merchant_id, TODAY)

    assert [(item.label, item.price_minor, item.available) for item in stock] == [
        ("Brownie", 9000, 15),
        ("Scoop cookie (Chocolate)", 6500, 12),
        ("Scoop cookie (Red velvet)", 7000, 10),
    ]


async def test_opening_stock_cant_drop_below_what_is_sold_or_held(
    shop: ChannelConnection,
) -> None:
    async with session_scope() as session:
        await inventory.set_opening_stock(
            session,
            merchant_id=shop.merchant_id,
            business_date=TODAY,
            lines=[OpeningStockLine("Brownie", None, 9000, 10)],
        )
        await session.execute(update(DailyStock).values(sold=6, held=2))

    with pytest.raises(inventory.StockConflict):
        async with session_scope() as session:
            await inventory.set_opening_stock(
                session,
                merchant_id=shop.merchant_id,
                business_date=TODAY,
                lines=[OpeningStockLine("Brownie", None, 9000, 4)],
            )
