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


async def test_restock_increases_available_stock(shop: ChannelConnection) -> None:
    async with session_scope() as session:
        await inventory.set_opening_stock(
            session,
            merchant_id=shop.merchant_id,
            business_date=TODAY,
            lines=[OpeningStockLine("Croissant", None, 12000, 10)],
        )
        ledger = await inventory.day_ledger(session, shop.merchant_id, TODAY)
        variant_id = ledger[0].variant_id

        # Restock 5 additional croissants baked in afternoon
        success = await inventory.restock(
            session,
            variant_id=variant_id,
            business_date=TODAY,
            quantity=5,
        )
        assert success is True

    async with session_scope() as session:
        updated_ledger = await inventory.day_ledger(session, shop.merchant_id, TODAY)
        row = updated_ledger[0]
        assert row.opening == 10
        assert row.restocked == 5
        assert row.available == 15


async def test_record_counter_sale_deducts_available_and_prevents_overselling(
    shop: ChannelConnection,
) -> None:
    async with session_scope() as session:
        await inventory.set_opening_stock(
            session,
            merchant_id=shop.merchant_id,
            business_date=TODAY,
            lines=[OpeningStockLine("Sourdough Bread", None, 15000, 8)],
        )
        ledger = await inventory.day_ledger(session, shop.merchant_id, TODAY)
        variant_id = ledger[0].variant_id

        # Walk-in customer buys 3 loaves at counter
        remaining = await inventory.record_counter_sale(
            session,
            variant_id=variant_id,
            business_date=TODAY,
            quantity=3,
        )
        assert remaining == 5

    async with session_scope() as session:
        ledger = await inventory.day_ledger(session, shop.merchant_id, TODAY)
        row = ledger[0]
        assert row.counter_sales == 3
        assert row.available == 5

        # Attempt to sell 6 over counter when only 5 remain -> raises StockConflict
        with pytest.raises(inventory.StockConflict):
            await inventory.record_counter_sale(
                session,
                variant_id=variant_id,
                business_date=TODAY,
                quantity=6,
            )


async def test_mark_sold_out_brings_available_to_zero(shop: ChannelConnection) -> None:
    async with session_scope() as session:
        await inventory.set_opening_stock(
            session,
            merchant_id=shop.merchant_id,
            business_date=TODAY,
            lines=[OpeningStockLine("Cupcake", "Vanilla", 4000, 10)],
        )
        ledger = await inventory.day_ledger(session, shop.merchant_id, TODAY)
        variant_id = ledger[0].variant_id

        # Hold 2 for an online customer
        held = await inventory.hold(session, variant_id=variant_id, business_date=TODAY, quantity=2)
        assert held is True

        # Merchant marks remaining cupcakes sold out
        sold_out = await inventory.mark_sold_out(
            session, variant_id=variant_id, business_date=TODAY
        )
        assert sold_out is True

    async with session_scope() as session:
        ledger = await inventory.day_ledger(session, shop.merchant_id, TODAY)
        row = ledger[0]
        assert row.held == 2
        assert row.available == 0
        # Counter sales absorbed the 8 remaining unheld units
        assert row.counter_sales == 8

        # Calling mark_sold_out again is an idempotent no-op
        assert (
            await inventory.mark_sold_out(session, variant_id=variant_id, business_date=TODAY)
            is True
        )


async def test_inventory_operations_reject_invalid_inputs_and_missing_variants(
    shop: ChannelConnection,
) -> None:
    import uuid

    fake_variant_id = uuid.uuid4()

    async with session_scope() as session:
        with pytest.raises(ValueError):
            await inventory.restock(
                session, variant_id=fake_variant_id, business_date=TODAY, quantity=0
            )

        with pytest.raises(ValueError):
            await inventory.record_counter_sale(
                session, variant_id=fake_variant_id, business_date=TODAY, quantity=-1
            )

        with pytest.raises(LookupError):
            await inventory.restock(
                session, variant_id=fake_variant_id, business_date=TODAY, quantity=5
            )

        with pytest.raises(LookupError):
            await inventory.record_counter_sale(
                session, variant_id=fake_variant_id, business_date=TODAY, quantity=5
            )

        with pytest.raises(LookupError):
            await inventory.mark_sold_out(session, variant_id=fake_variant_id, business_date=TODAY)
