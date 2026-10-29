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


async def test_nightly_rollover_perpetual_and_multi_day(shop: ChannelConnection) -> None:
    from datetime import timedelta

    from app.modules.catalog import service as catalog

    yesterday = TODAY - timedelta(days=1)
    async with session_scope() as session:
        # 1. Dress: perpetual inventory mode
        dress_var = await catalog.upsert_variant(
            session,
            merchant_id=shop.merchant_id,
            product_name="Floral Summer Dress",
            variant_name="Medium",
            price_minor=249900,
            stock_mode="inventory",
        )
        # 2. Cookies: daily mode but shelf_life_days=3
        cookie_var = await catalog.upsert_variant(
            session,
            merchant_id=shop.merchant_id,
            product_name="Matcha Cookie",
            variant_name=None,
            price_minor=8000,
            stock_mode="daily",
            shelf_life_days=3,
        )
        # 3. Cake: daily perishable, shelf_life_days=1
        await catalog.upsert_variant(
            session,
            merchant_id=shop.merchant_id,
            product_name="Fresh Cream Cake",
            variant_name=None,
            price_minor=65000,
            stock_mode="daily",
            shelf_life_days=1,
        )

        # Set yesterday's stock
        await inventory.set_opening_stock(
            session,
            merchant_id=shop.merchant_id,
            business_date=yesterday,
            lines=[
                OpeningStockLine("Floral Summer Dress", "Medium", 249900, 10),
                OpeningStockLine("Matcha Cookie", None, 8000, 20),
                OpeningStockLine("Fresh Cream Cake", None, 65000, 5),
            ],
        )

        # Counter sale yesterday: 2 dresses sold, 8 cookies sold
        await inventory.record_counter_sale(
            session, variant_id=dress_var.id, business_date=yesterday, quantity=2
        )
        await inventory.record_counter_sale(
            session, variant_id=cookie_var.id, business_date=yesterday, quantity=8
        )

        # Nightly rollover executes from yesterday to today
        rolled = await inventory.execute_nightly_rollover(
            session,
            merchant_id=shop.merchant_id,
            from_date=yesterday,
            to_date=TODAY,
        )
        assert rolled == 2  # Dress (inventory) + Cookie (shelf_life=3)

    async with session_scope() as session:
        today_stock = await inventory.today_stock(session, shop.merchant_id, TODAY)
        stock_map = {item.label: item.available for item in today_stock}
        assert stock_map["Floral Summer Dress (Medium)"] == 8
        assert stock_map["Matcha Cookie"] == 12
        assert "Fresh Cream Cake" not in stock_map


async def test_yesterday_leftovers_and_merchant_custom_rollover(
    shop: ChannelConnection,
) -> None:
    from datetime import timedelta

    from app.modules.catalog import service as catalog
    from app.modules.inventory.schemas import RolloverItemSelection

    yesterday = TODAY - timedelta(days=1)
    async with session_scope() as session:
        cookie_var = await catalog.upsert_variant(
            session,
            merchant_id=shop.merchant_id,
            product_name="Choc Chip Cookie",
            variant_name=None,
            price_minor=6000,
            stock_mode="daily",
            shelf_life_days=2,
        )
        cake_var = await catalog.upsert_variant(
            session,
            merchant_id=shop.merchant_id,
            product_name="Pastry Slice",
            variant_name=None,
            price_minor=12000,
            stock_mode="daily",
            shelf_life_days=1,
        )

        await inventory.set_opening_stock(
            session,
            merchant_id=shop.merchant_id,
            business_date=yesterday,
            lines=[
                OpeningStockLine("Choc Chip Cookie", None, 6000, 10),
                OpeningStockLine("Pastry Slice", None, 12000, 6),
            ],
        )

        # Fetch leftovers
        leftovers = await inventory.get_yesterday_leftovers(
            session, merchant_id=shop.merchant_id, business_date=TODAY
        )
        assert len(leftovers) == 2
        leftover_map = {item.product: item.leftover_quantity for item in leftovers}
        assert leftover_map["Choc Chip Cookie"] == 10
        assert leftover_map["Pastry Slice"] == 6

        # Merchant customizes:
        # Out of 10 cookies, only 4 roll over to today's online stock (6 kept for counter/personal)
        # Out of 6 pastry slices, only 2 roll over
        rolled_count = await inventory.apply_rollover_selection(
            session,
            merchant_id=shop.merchant_id,
            business_date=TODAY,
            selections=[
                RolloverItemSelection(variant_id=cookie_var.id, rollover_quantity=4),
                RolloverItemSelection(variant_id=cake_var.id, rollover_quantity=2),
            ],
        )
        assert rolled_count == 2

    async with session_scope() as session:
        today_stock = await inventory.today_stock(session, shop.merchant_id, TODAY)
        stock_map = {item.label: item.available for item in today_stock}
        assert stock_map["Choc Chip Cookie"] == 4
        assert stock_map["Pastry Slice"] == 2


async def test_custom_rollover_exceeds_available_raises_conflict(
    shop: ChannelConnection,
) -> None:
    from datetime import timedelta

    from app.modules.catalog import service as catalog
    from app.modules.inventory.schemas import RolloverItemSelection

    yesterday = TODAY - timedelta(days=1)
    async with session_scope() as session:
        cookie_var = await catalog.upsert_variant(
            session,
            merchant_id=shop.merchant_id,
            product_name="Oatmeal Cookie",
            variant_name=None,
            price_minor=5000,
        )
        await inventory.set_opening_stock(
            session,
            merchant_id=shop.merchant_id,
            business_date=yesterday,
            lines=[OpeningStockLine("Oatmeal Cookie", None, 5000, 5)],
        )

        # Merchant requests 10 when yesterday only had 5 available
        with pytest.raises(inventory.StockConflict):
            await inventory.apply_rollover_selection(
                session,
                merchant_id=shop.merchant_id,
                business_date=TODAY,
                selections=[RolloverItemSelection(variant_id=cookie_var.id, rollover_quantity=10)],
            )


async def test_active_daily_inventory_view_reflects_updated_variant_price(
    shop: ChannelConnection,
) -> None:
    from datetime import datetime
    from zoneinfo import ZoneInfo

    from sqlalchemy import text

    ist_today = datetime.now(tz=ZoneInfo("Asia/Kolkata")).date()

    async with session_scope() as session:
        await inventory.set_opening_stock(
            session,
            merchant_id=shop.merchant_id,
            business_date=ist_today,
            lines=[OpeningStockLine("Filter Coffee Cake", None, 6000, 10)],
        )
        # Update price on the same day from 6000 to 7500
        await inventory.set_opening_stock(
            session,
            merchant_id=shop.merchant_id,
            business_date=ist_today,
            lines=[OpeningStockLine("Filter Coffee Cake", None, 7500, 10)],
        )

        view_price = await session.scalar(
            text(
                "SELECT selling_price_minor FROM v_active_daily_inventory "
                "WHERE merchant_id = :mid AND product_name = 'Filter Coffee Cake'"
            ),
            {"mid": shop.merchant_id},
        )
        assert view_price == 7500


async def test_release_expired_holds_uses_stored_business_date_across_days(
    shop: ChannelConnection,
) -> None:
    from datetime import UTC, datetime, timedelta

    async with session_scope() as session:
        await inventory.set_opening_stock(
            session,
            merchant_id=shop.merchant_id,
            business_date=TODAY,
            lines=[OpeningStockLine("Filter Coffee Cake", None, 7500, 10)],
        )
        ledger = await inventory.day_ledger(session, shop.merchant_id, TODAY)
        variant_id = ledger[0].variant_id

        held = await inventory.hold(
            session,
            variant_id=variant_id,
            business_date=TODAY,
            quantity=3,
            expires_at=datetime.now(UTC) - timedelta(minutes=1),
        )
        assert held is True

    async with session_scope() as session:
        await inventory.release_expired_holds(session, now=datetime.now(UTC))
        ledger_after = await inventory.day_ledger(session, shop.merchant_id, TODAY)
        assert ledger_after[0].held == 0
        assert ledger_after[0].available == 10
