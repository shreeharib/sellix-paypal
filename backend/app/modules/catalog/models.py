import uuid
from datetime import datetime

from sqlalchemy import func, text
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base


class Product(Base):
    __tablename__ = "products"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, server_default=text("gen_random_uuid()")
    )
    merchant_id: Mapped[uuid.UUID]
    name: Mapped[str]
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
    name: Mapped[str | None]  # None when the product has no variants
    price_minor: Mapped[int]  # paise for INR
    currency: Mapped[str] = mapped_column(server_default="INR")
    is_active: Mapped[bool] = mapped_column(server_default=text("true"))
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(server_default=func.now())


class ProductAlias(Base):
    """Another name customers use for a product (a nickname, a Tamil or Hindi name)."""

    __tablename__ = "product_aliases"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, server_default=text("gen_random_uuid()")
    )
    product_id: Mapped[uuid.UUID]
    alias_text: Mapped[str]
    confidence_source: Mapped[str] = mapped_column(server_default="merchant_confirmed")
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
