"""Public interface of the catalog module."""

import uuid

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.catalog.models import Product, ProductVariant


async def upsert_variant(
    session: AsyncSession,
    *,
    merchant_id: uuid.UUID,
    product_name: str,
    variant_name: str | None,
    price_minor: int,
    currency: str = "INR",
    stock_mode: str | None = None,
    shelf_life_days: int | None = None,
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
        product = Product(
            merchant_id=merchant_id,
            name=product_name,
            stock_mode=stock_mode or "daily",
            shelf_life_days=shelf_life_days,
        )
        session.add(product)
        await session.flush()
    else:
        if stock_mode:
            product.stock_mode = stock_mode
        if shelf_life_days is not None:
            product.shelf_life_days = shelf_life_days

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
            stock_mode=stock_mode,
            shelf_life_days=shelf_life_days,
        )
        session.add(variant)
        await session.flush()
    else:
        variant.price_minor = price_minor
        variant.currency = currency
        if stock_mode is not None:
            variant.stock_mode = stock_mode
        if shelf_life_days is not None:
            variant.shelf_life_days = shelf_life_days
        variant.is_active = True
    product.is_active = True
    return variant
