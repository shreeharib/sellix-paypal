import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import func, text
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base


class Product(Base):
    __tablename__ = "products"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, server_default=text("gen_random_uuid()")
    )
    merchant_id: Mapped[uuid.UUID]
    name: Mapped[str]
    title: Mapped[str | None] = mapped_column(nullable=True, server_default=text("''"))
    description: Mapped[str | None] = mapped_column(nullable=True)
    category: Mapped[str | None] = mapped_column(nullable=True)
    base_image_url: Mapped[str | None] = mapped_column(nullable=True)
    attributes: Mapped[dict[str, Any]] = mapped_column(
        JSONB, server_default=text("'{}'::jsonb"), default=dict
    )
    stock_mode: Mapped[str] = mapped_column(server_default=text("'daily'"))
    shelf_life_days: Mapped[int | None] = mapped_column(nullable=True, server_default=text("null"))
    is_active: Mapped[bool] = mapped_column(server_default=text("true"))
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(server_default=func.now())


class ProductVariant(Base):
    __tablename__ = "product_variants"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, server_default=text("gen_random_uuid()")
    )
    merchant_id: Mapped[uuid.UUID]
    product_id: Mapped[uuid.UUID]
    sku: Mapped[str | None] = mapped_column(nullable=True)
    name: Mapped[str | None]  # None when the product has no variants
    variant_name: Mapped[str | None] = mapped_column(nullable=True)
    price_minor: Mapped[int]  # paise for INR
    compare_at_price_minor: Mapped[int | None] = mapped_column(
        nullable=True, server_default=text("0")
    )
    cost_price_minor: Mapped[int | None] = mapped_column(nullable=True, server_default=text("0"))
    currency: Mapped[str] = mapped_column(server_default="INR")
    attributes: Mapped[dict[str, Any]] = mapped_column(
        JSONB, server_default=text("'{}'::jsonb"), default=dict
    )
    stock_mode: Mapped[str | None] = mapped_column(nullable=True, server_default=text("null"))
    shelf_life_days: Mapped[int | None] = mapped_column(nullable=True, server_default=text("null"))
    is_active: Mapped[bool] = mapped_column(server_default=text("true"))
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(server_default=func.now())


class ProductAlias(Base):
    __tablename__ = "product_aliases"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, server_default=text("gen_random_uuid()")
    )
    product_id: Mapped[uuid.UUID]
    alias_text: Mapped[str]
    confidence_source: Mapped[str] = mapped_column(server_default=text("'merchant_confirmed'"))
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
