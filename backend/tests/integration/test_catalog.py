from collections.abc import AsyncIterator

import httpx2
import pytest

from app.core.db import session_scope
from app.main import create_app
from app.modules.catalog import service as catalog
from app.modules.channels.models import ChannelConnection
from tests.integration.test_api import sign_in_as

pytestmark = pytest.mark.anyio


@pytest.fixture
async def api(db: None) -> AsyncIterator[httpx2.AsyncClient]:
    transport = httpx2.ASGITransport(app=create_app())
    async with httpx2.AsyncClient(transport=transport, base_url="http://test") as client:
        yield client


async def test_upsert_variant_auto_generates_sku_and_seeds_aliases(
    shop: ChannelConnection,
) -> None:
    async with session_scope() as session:
        variant = await catalog.upsert_variant(
            session,
            merchant_id=shop.merchant_id,
            product_name="Walnut Brownie",
            variant_name="Box of 4",
            price_minor=45000,
            compare_at_price_minor=55000,
            cost_price_minor=20000,
            category="bakes",
            attributes={"dietary": "eggless", "allergens": ["walnuts", "dairy"]},
        )
        assert variant.sku == "WALN-BOX"
        assert variant.compare_at_price_minor == 55000
        assert variant.cost_price_minor == 20000
        assert variant.attributes["dietary"] == "eggless"

        # Check seeded aliases
        aliases = await catalog.list_product_aliases(session, variant.product_id)
        alias_texts = {a.alias_text for a in aliases}
        assert "walnut brownie" in alias_texts
        assert "walnut brownie box of 4" in alias_texts


async def test_fuzzy_search_matches_typos_and_aliases(
    shop: ChannelConnection,
) -> None:
    async with session_scope() as session:
        variant = await catalog.upsert_variant(
            session,
            merchant_id=shop.merchant_id,
            product_name="Chocolate Truffle Cake",
            variant_name="500g",
            price_minor=65000,
            category="cakes",
        )
        # Add slang alias
        await catalog.add_product_alias(
            session,
            product_id=variant.product_id,
            alias_text="choc truffle",
        )

        # 1. Exact match on alias
        results = await catalog.search_catalog_fuzzy(
            session, merchant_id=shop.merchant_id, query_text="choc truffle"
        )
        assert len(results) >= 1
        assert results[0]["product_id"] == variant.product_id

        # 2. Typo match on product name ("chocolte trufle")
        typo_results = await catalog.search_catalog_fuzzy(
            session, merchant_id=shop.merchant_id, query_text="chocolte trufle"
        )
        assert len(typo_results) >= 1
        assert typo_results[0]["product_id"] == variant.product_id


async def test_catalog_rest_api_lifecycle(
    shop: ChannelConnection,
    api: httpx2.AsyncClient,
) -> None:
    token = await sign_in_as(shop.merchant_id)
    headers = {"Authorization": f"Bearer {token}"}

    # 1. Create a product through fast-path stock upsert
    async with session_scope() as session:
        variant = await catalog.upsert_variant(
            session,
            merchant_id=shop.merchant_id,
            product_name="Sourdough Loaf",
            variant_name=None,
            price_minor=30000,
            compare_at_price_minor=35000,
        )
        product_id = str(variant.product_id)

    # 2. GET /v1/products
    res = await api.get("/v1/products", headers=headers)
    assert res.status_code == 200
    prods = res.json()
    assert any(p["id"] == product_id for p in prods)

    # 3. PATCH /v1/products/{id} with enterprise metadata
    patch_payload = {
        "title": "Artisanal Country Sourdough",
        "description": "Fermented for 36 hours with wild yeast starter.",
        "category": "breads",
        "attributes": {"vegan": True, "organic_flour": True},
    }
    patch_res = await api.patch(f"/v1/products/{product_id}", json=patch_payload, headers=headers)
    assert patch_res.status_code == 200
    data = patch_res.json()
    assert data["title"] == "Artisanal Country Sourdough"
    assert data["category"] == "breads"
    assert data["attributes"]["vegan"] is True

    # 4. Filter by category
    filter_res = await api.get("/v1/products?category=breads", headers=headers)
    assert filter_res.status_code == 200
    assert len(filter_res.json()) >= 1

    empty_cat_res = await api.get("/v1/products?category=apparel", headers=headers)
    assert empty_cat_res.status_code == 200
    assert len(empty_cat_res.json()) == 0

    # 5. POST /v1/products/{id}/aliases (add customer slang)
    alias_res = await api.post(
        f"/v1/products/{product_id}/aliases",
        json={"alias_text": "sour bread"},
        headers=headers,
    )
    assert alias_res.status_code == 200
    alias_id = alias_res.json()["id"]

    # 6. GET /v1/products/search?q=sour+bread
    search_res = await api.get("/v1/products/search?q=sour bread", headers=headers)
    assert search_res.status_code == 200
    search_data = search_res.json()
    assert search_data["total_results"] >= 1
    assert search_data["items"][0]["product_id"] == product_id

    # 7. DELETE /v1/products/{id}/aliases/{alias_id}
    del_res = await api.delete(f"/v1/products/{product_id}/aliases/{alias_id}", headers=headers)
    assert del_res.status_code == 200
    assert del_res.json() == {"deleted": True}
