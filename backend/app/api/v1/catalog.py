"""Catalog API endpoints for multi-category D2C enterprise enrichment and fuzzy AI search."""

import uuid
from typing import Annotated

from fastapi import APIRouter, HTTPException, Query

from app.api.v1 import schemas
from app.api.v1.deps import Shop
from app.core.db import session_scope
from app.modules.catalog import service as catalog

router = APIRouter(prefix="/products", tags=["catalog"])


@router.get("/search", response_model=schemas.CatalogSearchResponse)
async def search_catalog(
    shop: Shop,
    q: Annotated[str, Query(min_length=1, max_length=100)],
    limit: Annotated[int, Query(ge=1, le=50)] = 10,
) -> schemas.CatalogSearchResponse:
    """Fuzzy search catalog matching typos and customer slang via trigrams and aliases."""
    async with session_scope() as session:
        results = await catalog.search_catalog_fuzzy(
            session, merchant_id=shop.merchant_id, query_text=q, limit=limit
        )

    items: list[schemas.CatalogSearchItem] = []
    for r in results:
        items.append(
            schemas.CatalogSearchItem(
                product_id=r["product_id"],
                product_name=r["product_name"],
                category=r["category"],
                attributes=r["attributes"] or {},
                matched_alias=r["matched_alias"],
                similarity=r["similarity"],
                variants=[
                    schemas.ProductVariantDetail(
                        id=v.id,
                        sku=v.sku,
                        name=v.name,
                        price_minor=v.price_minor,
                        compare_at_price_minor=v.compare_at_price_minor,
                        cost_price_minor=v.cost_price_minor,
                        currency=v.currency,
                        stock_mode=v.stock_mode,
                        shelf_life_days=v.shelf_life_days,
                        attributes=v.attributes or {},
                        is_active=v.is_active,
                    )
                    for v in r["variants"]
                ],
            )
        )
    return schemas.CatalogSearchResponse(query=q, total_results=len(items), items=items)


@router.get("", response_model=list[schemas.ProductDetail])
async def list_products(
    shop: Shop,
    category: Annotated[str | None, Query(max_length=100)] = None,
) -> list[schemas.ProductDetail]:
    """List catalog products with optional category filtering."""
    async with session_scope() as session:
        prods = await catalog.list_products(session, shop.merchant_id, category=category)
        details: list[schemas.ProductDetail] = []
        for p in prods:
            item = await catalog.get_product_with_variants(session, shop.merchant_id, p.id)
            if not item:
                continue
            prod, variants, aliases = item
            details.append(
                schemas.ProductDetail(
                    id=prod.id,
                    name=prod.name,
                    title=prod.title,
                    description=prod.description,
                    category=prod.category,
                    base_image_url=prod.base_image_url,
                    stock_mode=prod.stock_mode,
                    shelf_life_days=prod.shelf_life_days,
                    attributes=prod.attributes or {},
                    is_active=prod.is_active,
                    variants=[
                        schemas.ProductVariantDetail(
                            id=v.id,
                            sku=v.sku,
                            name=v.name,
                            price_minor=v.price_minor,
                            compare_at_price_minor=v.compare_at_price_minor,
                            cost_price_minor=v.cost_price_minor,
                            currency=v.currency,
                            stock_mode=v.stock_mode,
                            shelf_life_days=v.shelf_life_days,
                            attributes=v.attributes or {},
                            is_active=v.is_active,
                        )
                        for v in variants
                    ],
                    aliases=[
                        schemas.ProductAliasDetail(
                            id=a.id,
                            alias_text=a.alias_text,
                            confidence_source=a.confidence_source,
                            created_at=a.created_at,
                        )
                        for a in aliases
                    ],
                )
            )
    return details


@router.get("/{product_id}", response_model=schemas.ProductDetail)
async def get_product(
    shop: Shop,
    product_id: uuid.UUID,
) -> schemas.ProductDetail:
    """Retrieve detailed product information, including variants and aliases."""
    async with session_scope() as session:
        item = await catalog.get_product_with_variants(session, shop.merchant_id, product_id)
        if not item:
            raise HTTPException(status_code=404, detail="Product not found")
        prod, variants, aliases = item
        return schemas.ProductDetail(
            id=prod.id,
            name=prod.name,
            title=prod.title,
            description=prod.description,
            category=prod.category,
            base_image_url=prod.base_image_url,
            stock_mode=prod.stock_mode,
            shelf_life_days=prod.shelf_life_days,
            attributes=prod.attributes or {},
            is_active=prod.is_active,
            variants=[
                schemas.ProductVariantDetail(
                    id=v.id,
                    sku=v.sku,
                    name=v.name,
                    price_minor=v.price_minor,
                    compare_at_price_minor=v.compare_at_price_minor,
                    cost_price_minor=v.cost_price_minor,
                    currency=v.currency,
                    stock_mode=v.stock_mode,
                    shelf_life_days=v.shelf_life_days,
                    attributes=v.attributes or {},
                    is_active=v.is_active,
                )
                for v in variants
            ],
            aliases=[
                schemas.ProductAliasDetail(
                    id=a.id,
                    alias_text=a.alias_text,
                    confidence_source=a.confidence_source,
                    created_at=a.created_at,
                )
                for a in aliases
            ],
        )


@router.patch("/{product_id}", response_model=schemas.ProductDetail)
async def update_product(
    shop: Shop,
    product_id: uuid.UUID,
    payload: schemas.ProductUpdate,
) -> schemas.ProductDetail:
    """Update product metadata, description, category, and dietary/size attributes."""
    async with session_scope() as session:
        updated = await catalog.update_product(
            session,
            merchant_id=shop.merchant_id,
            product_id=product_id,
            name=payload.name,
            title=payload.title,
            description=payload.description,
            category=payload.category,
            base_image_url=payload.base_image_url,
            attributes=payload.attributes,
        )
        if not updated:
            raise HTTPException(status_code=404, detail="Product not found")

        item = await catalog.get_product_with_variants(session, shop.merchant_id, product_id)
        assert item is not None
        prod, variants, aliases = item
        return schemas.ProductDetail(
            id=prod.id,
            name=prod.name,
            title=prod.title,
            description=prod.description,
            category=prod.category,
            base_image_url=prod.base_image_url,
            stock_mode=prod.stock_mode,
            shelf_life_days=prod.shelf_life_days,
            attributes=prod.attributes or {},
            is_active=prod.is_active,
            variants=[
                schemas.ProductVariantDetail(
                    id=v.id,
                    sku=v.sku,
                    name=v.name,
                    price_minor=v.price_minor,
                    compare_at_price_minor=v.compare_at_price_minor,
                    cost_price_minor=v.cost_price_minor,
                    currency=v.currency,
                    stock_mode=v.stock_mode,
                    shelf_life_days=v.shelf_life_days,
                    attributes=v.attributes or {},
                    is_active=v.is_active,
                )
                for v in variants
            ],
            aliases=[
                schemas.ProductAliasDetail(
                    id=a.id,
                    alias_text=a.alias_text,
                    confidence_source=a.confidence_source,
                    created_at=a.created_at,
                )
                for a in aliases
            ],
        )


@router.post("/{product_id}/aliases", response_model=schemas.ProductAliasDetail)
async def create_alias(
    shop: Shop,
    product_id: uuid.UUID,
    payload: schemas.CreateAliasRequest,
) -> schemas.ProductAliasDetail:
    """Add a customer slang or search synonym to the product."""
    async with session_scope() as session:
        item = await catalog.get_product_with_variants(session, shop.merchant_id, product_id)
        if not item:
            raise HTTPException(status_code=404, detail="Product not found")
        try:
            alias = await catalog.add_product_alias(
                session,
                product_id=product_id,
                alias_text=payload.alias_text,
                source="merchant_confirmed",
            )
        except ValueError as exc:
            raise HTTPException(status_code=422, detail=str(exc)) from exc

        return schemas.ProductAliasDetail(
            id=alias.id,
            alias_text=alias.alias_text,
            confidence_source=alias.confidence_source,
            created_at=alias.created_at,
        )


@router.delete("/{product_id}/aliases/{alias_id}")
async def delete_alias(
    shop: Shop,
    product_id: uuid.UUID,
    alias_id: uuid.UUID,
) -> dict[str, bool]:
    """Remove a search alias."""
    async with session_scope() as session:
        item = await catalog.get_product_with_variants(session, shop.merchant_id, product_id)
        if not item:
            raise HTTPException(status_code=404, detail="Product not found")
        deleted = await catalog.delete_product_alias(session, product_id, alias_id)
        if not deleted:
            raise HTTPException(status_code=404, detail="Alias not found")
    return {"deleted": True}
