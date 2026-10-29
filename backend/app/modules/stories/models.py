import uuid
from datetime import datetime
from decimal import Decimal
from typing import Any

from sqlalchemy import func, text
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base


class StoryRegistry(Base):
    """What one of the shop's stories shows. The media itself is never stored (Meta's rule)."""

    __tablename__ = "story_registry"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, server_default=text("gen_random_uuid()")
    )
    merchant_id: Mapped[uuid.UUID]
    ig_story_id: Mapped[str]
    mapped_variant_id: Mapped[uuid.UUID | None] = mapped_column(nullable=True, default=None)
    expires_at: Mapped[datetime]
    cdn_url: Mapped[str | None] = mapped_column(nullable=True, default=None)
    products: Mapped[list[str]] = mapped_column(JSONB, server_default="[]")
    confidence: Mapped[Decimal | None] = mapped_column(nullable=True, default=None)
    caption: Mapped[str | None] = mapped_column(nullable=True, default=None)
    confirmed_by_merchant: Mapped[bool] = mapped_column(server_default=text("false"))
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())


class MediaResult(Base):
    __tablename__ = "media_results"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, server_default=text("gen_random_uuid()")
    )
    merchant_id: Mapped[uuid.UUID]
    media_key: Mapped[str]
    result: Mapped[dict[str, Any]] = mapped_column(JSONB)
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())


class ProductPost(Base):
    __tablename__ = "product_posts"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, server_default=text("gen_random_uuid()")
    )
    merchant_id: Mapped[uuid.UUID]
    product_id: Mapped[uuid.UUID]
    ig_media_id: Mapped[str]
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
