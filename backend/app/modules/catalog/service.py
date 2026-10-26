"""Public interface of the catalog module."""

import uuid

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.catalog.models import Product, ProductAlias, ProductVariant


async def upsert_variant(
    session: AsyncSession,
    *,
    merchant_id: uuid.UUID,
    product_name: str,
    variant_name: str | None,
    price_minor: int,
    currency: str = "INR",
) -> ProductVariant:
    """Find or create the product and variant (names match case-insensitively); set the price."""
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
        product = Product(merchant_id=merchant_id, name=product_name)
        session.add(product)
        await session.flush()

    variant = await session.scalar(
        select(ProductVariant).where(
            ProductVariant.product_id == product.id,
            func.lower(func.coalesce(ProductVariant.name, "")) == (variant_name or "").lower(),
        )
    )
    if variant is None:
        variant = ProductVariant(
            merchant_id=merchant_id,
            product_id=product.id,
            name=variant_name,
            price_minor=price_minor,
            currency=currency,
        )
        session.add(variant)
        await session.flush()
    else:
        variant.price_minor = price_minor
        variant.currency = currency
        variant.is_active = True
    product.is_active = True
    return variant


async def add_alias(
    session: AsyncSession, *, merchant_id: uuid.UUID, product_name: str, alias: str
) -> ProductAlias:
    """Teach the agent another name for a product, e.g. its Tamil name or a nickname."""
    alias = " ".join(alias.split())
    if not alias:
        raise ValueError("The alias is empty")
    product = await session.scalar(
        select(Product).where(
            Product.merchant_id == merchant_id,
            func.lower(Product.name) == product_name.strip().lower(),
        )
    )
    if product is None:
        raise LookupError(f"No product called {product_name!r}")
    existing = await session.scalar(
        select(ProductAlias).where(
            ProductAlias.product_id == product.id,
            func.lower(ProductAlias.alias_text) == alias.lower(),
        )
    )
    if existing is not None:
        return existing
    created = ProductAlias(product_id=product.id, alias_text=alias)
    session.add(created)
    await session.flush()
    return created


async def aliases(session: AsyncSession, merchant_id: uuid.UUID) -> dict[uuid.UUID, list[str]]:
    """Every alias of the merchant's products, by product ID."""
    rows = await session.execute(
        select(ProductAlias.product_id, ProductAlias.alias_text)
        .join(Product, Product.id == ProductAlias.product_id)
        .where(Product.merchant_id == merchant_id)
        .order_by(ProductAlias.created_at)
    )
    found: dict[uuid.UUID, list[str]] = {}
    for product_id, alias in rows:
        found.setdefault(product_id, []).append(alias)
    return found
