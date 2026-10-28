"""Public interface of the catalog module: Dual-Engine Catalog Architecture.

Supports both fast-path unconstrained morning stock text and rich enterprise relational
attributes (dietary, allergens, categories, MRP, and AI search aliases).
"""

import re
import uuid
from typing import Any

from sqlalchemy import func, select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.catalog.models import Product, ProductAlias, ProductVariant


def _generate_sku(product_name: str, variant_name: str | None) -> str:
    """Generate a readable default SKU like BRN-WAL-01 or DRSS-M-01."""
    p_clean = re.sub(r"[^A-Za-z0-9]", "", product_name).upper()[:4] or "ITEM"
    if variant_name:
        v_clean = re.sub(r"[^A-Za-z0-9]", "", variant_name).upper()[:3] or "VAR"
        return f"{p_clean}-{v_clean}"
    return f"{p_clean}-STD"


async def _seed_auto_aliases(
    session: AsyncSession,
    product_id: uuid.UUID,
    product_name: str,
    variant_name: str | None,
) -> None:
    """Auto-generate default search aliases for conversational customer slang matching."""
    aliases_to_add: set[str] = set()
    p_norm = product_name.strip().lower()
    aliases_to_add.add(p_norm)
    if p_norm.endswith("s"):
        aliases_to_add.add(p_norm[:-1])
    else:
        aliases_to_add.add(p_norm + "s")

    if variant_name:
        v_norm = variant_name.strip().lower()
        aliases_to_add.add(f"{v_norm} {p_norm}")
        aliases_to_add.add(f"{p_norm} {v_norm}")
        aliases_to_add.add(f"{p_norm} ({v_norm})")

    existing = set(
        await session.scalars(
            select(func.lower(ProductAlias.alias_text)).where(ProductAlias.product_id == product_id)
        )
    )
    for alias in aliases_to_add:
        if len(alias) >= 2 and alias.lower() not in existing:
            session.add(
                ProductAlias(
                    product_id=product_id,
                    alias_text=alias,
                    confidence_source="auto_generated",
                )
            )
            existing.add(alias.lower())


async def upsert_variant(
    session: AsyncSession,
    *,
    merchant_id: uuid.UUID,
    product_name: str,
    variant_name: str | None = None,
    price_minor: int = 0,
    currency: str = "INR",
    stock_mode: str | None = None,
    shelf_life_days: int | None = None,
    category: str | None = None,
    description: str | None = None,
    attributes: dict[str, Any] | None = None,
    sku: str | None = None,
    compare_at_price_minor: int | None = None,
    cost_price_minor: int | None = None,
    auto_aliases: bool = True,
) -> ProductVariant:
    """Find or create product and variant; set pricing, attributes, and auto-seed aliases."""
    if price_minor < 0:
        raise ValueError("Price can't be negative")
    product_name = product_name.strip()
    variant_name = variant_name.strip() if variant_name and variant_name.strip() else None

    product = await session.scalar(
        select(Product).where(
            Product.merchant_id == merchant_id, func.lower(Product.name) == product_name.lower()
        )
    )
    if product is None:
        product = Product(
            merchant_id=merchant_id,
            name=product_name,
            stock_mode=stock_mode or "daily",
            shelf_life_days=shelf_life_days,
            category=category,
            description=description,
            attributes=attributes or {},
        )
        session.add(product)
        await session.flush()
    else:
        if stock_mode:
            product.stock_mode = stock_mode
        if shelf_life_days is not None:
            product.shelf_life_days = shelf_life_days
        if category:
            product.category = category
        if description:
            product.description = description
        if attributes:
            merged_attrs = dict(product.attributes or {})
            merged_attrs.update(attributes)
            product.attributes = merged_attrs

    variant = await session.scalar(
        select(ProductVariant).where(
            ProductVariant.product_id == product.id,
            func.lower(func.coalesce(ProductVariant.name, "")) == (variant_name or "").lower(),
        )
    )
    if variant is None:
        effective_sku = sku or _generate_sku(product_name, variant_name)
        variant = ProductVariant(
            merchant_id=merchant_id,
            product_id=product.id,
            name=variant_name,
            sku=effective_sku,
            price_minor=price_minor,
            compare_at_price_minor=compare_at_price_minor or 0,
            cost_price_minor=cost_price_minor or 0,
            currency=currency,
            stock_mode=stock_mode,
            shelf_life_days=shelf_life_days,
            attributes=attributes or {},
        )
        session.add(variant)
        await session.flush()
    else:
        variant.price_minor = price_minor
        variant.currency = currency
        if sku is not None:
            variant.sku = sku
        if compare_at_price_minor is not None:
            variant.compare_at_price_minor = compare_at_price_minor
        if cost_price_minor is not None:
            variant.cost_price_minor = cost_price_minor
        if stock_mode is not None:
            variant.stock_mode = stock_mode
        if shelf_life_days is not None:
            variant.shelf_life_days = shelf_life_days
        if attributes:
            merged_v_attrs = dict(variant.attributes or {})
            merged_v_attrs.update(attributes)
            variant.attributes = merged_v_attrs
        variant.is_active = True

    product.is_active = True

    if auto_aliases:
        await _seed_auto_aliases(session, product.id, product_name, variant_name)

    return variant


async def add_product_alias(
    session: AsyncSession,
    *,
    product_id: uuid.UUID,
    alias_text: str,
    source: str = "merchant_confirmed",
) -> ProductAlias:
    """Manually add customer slang or synonym to a product."""
    alias_clean = alias_text.strip().lower()
    if not alias_clean:
        raise ValueError("Alias text cannot be empty")

    existing = await session.scalar(
        select(ProductAlias).where(
            ProductAlias.product_id == product_id,
            func.lower(ProductAlias.alias_text) == alias_clean,
        )
    )
    if existing:
        return existing

    alias = ProductAlias(
        product_id=product_id,
        alias_text=alias_clean,
        confidence_source=source,
    )
    session.add(alias)
    await session.flush()
    return alias


async def list_product_aliases(session: AsyncSession, product_id: uuid.UUID) -> list[ProductAlias]:
    """Retrieve all search aliases associated with a product."""
    rows = await session.scalars(
        select(ProductAlias)
        .where(ProductAlias.product_id == product_id)
        .order_by(ProductAlias.alias_text)
    )
    return list(rows)


async def delete_product_alias(
    session: AsyncSession, product_id: uuid.UUID, alias_id: uuid.UUID
) -> bool:
    """Remove a search alias."""
    alias = await session.scalar(
        select(ProductAlias).where(
            ProductAlias.id == alias_id, ProductAlias.product_id == product_id
        )
    )
    if alias:
        await session.delete(alias)
        return True
    return False


async def search_catalog_fuzzy(
    session: AsyncSession,
    *,
    merchant_id: uuid.UUID,
    query_text: str,
    limit: int = 10,
) -> list[dict[str, Any]]:
    """Fuzzy search catalog matching customer slang or typos using pg_trgm and aliases."""
    q = query_text.strip().lower()
    if not q:
        return []

    sql = text("""
        SELECT *
        FROM (
            SELECT DISTINCT ON (p.id)
                p.id AS product_id,
                p.name AS product_name,
                p.category AS category,
                p.attributes AS attributes,
                COALESCE(pa.alias_text, p.name) AS matched_alias,
                similarity(COALESCE(pa.alias_text, p.name), :query) AS sim
            FROM products p
            LEFT JOIN product_aliases pa ON pa.product_id = p.id
            WHERE p.merchant_id = :merchant_id
              AND p.is_active = TRUE
              AND (
                  p.name ILIKE '%' || :query || '%'
                  OR pa.alias_text ILIKE '%' || :query || '%'
                  OR similarity(COALESCE(pa.alias_text, p.name), :query) > 0.2
              )
            ORDER BY p.id, sim DESC
        ) sub
        ORDER BY sim DESC
        LIMIT :limit
    """)
    res = await session.execute(sql, {"merchant_id": merchant_id, "query": q, "limit": limit})
    rows = res.all()

    results: list[dict[str, Any]] = []
    for r in rows:
        variants = list(
            await session.scalars(
                select(ProductVariant)
                .where(
                    ProductVariant.product_id == r.product_id,
                    ProductVariant.is_active.is_(True),
                )
                .order_by(ProductVariant.price_minor)
            )
        )
        results.append(
            {
                "product_id": r.product_id,
                "product_name": r.product_name,
                "category": r.category,
                "attributes": r.attributes,
                "matched_alias": r.matched_alias,
                "similarity": float(r.sim) if r.sim is not None else 0.0,
                "variants": variants,
            }
        )
    return results


async def list_products(
    session: AsyncSession,
    merchant_id: uuid.UUID,
    *,
    category: str | None = None,
    is_active: bool = True,
) -> list[Product]:
    """List all products for a merchant with optional category filtering."""
    query = select(Product).where(
        Product.merchant_id == merchant_id,
        Product.is_active == is_active,
    )
    if category:
        query = query.where(func.lower(Product.category) == category.strip().lower())
    query = query.order_by(Product.name)
    return list(await session.scalars(query))


async def get_product_with_variants(
    session: AsyncSession, merchant_id: uuid.UUID, product_id: uuid.UUID
) -> tuple[Product, list[ProductVariant], list[ProductAlias]] | None:
    """Get product details along with its variants and aliases."""
    prod = await session.scalar(
        select(Product).where(Product.merchant_id == merchant_id, Product.id == product_id)
    )
    if not prod:
        return None
    variants = list(
        await session.scalars(
            select(ProductVariant)
            .where(ProductVariant.product_id == product_id)
            .order_by(ProductVariant.name)
        )
    )
    aliases = list(
        await session.scalars(
            select(ProductAlias)
            .where(ProductAlias.product_id == product_id)
            .order_by(ProductAlias.alias_text)
        )
    )
    return prod, variants, aliases


async def update_product(
    session: AsyncSession,
    *,
    merchant_id: uuid.UUID,
    product_id: uuid.UUID,
    name: str | None = None,
    title: str | None = None,
    description: str | None = None,
    category: str | None = None,
    base_image_url: str | None = None,
    attributes: dict[str, Any] | None = None,
) -> Product | None:
    """Update a product's details and attributes."""
    prod = await session.scalar(
        select(Product).where(Product.merchant_id == merchant_id, Product.id == product_id)
    )
    if not prod:
        return None
    if name is not None:
        prod.name = name.strip()
    if title is not None:
        prod.title = title.strip()
    if description is not None:
        prod.description = description
    if category is not None:
        prod.category = category.strip()
    if base_image_url is not None:
        prod.base_image_url = base_image_url
    if attributes is not None:
        merged = dict(prod.attributes or {})
        merged.update(attributes)
        prod.attributes = merged
    prod.updated_at = func.now()
    await session.flush()
    return prod
