import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import func, text
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base


class ShopProfile(Base):
    __tablename__ = "shop_profiles"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, server_default=text("gen_random_uuid()")
    )
    merchant_id: Mapped[uuid.UUID]
    version: Mapped[int]
    content_md: Mapped[str]
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())


class ShopOnboarding(Base):
    __tablename__ = "shop_onboarding"

    merchant_id: Mapped[uuid.UUID] = mapped_column(primary_key=True)
    answers: Mapped[dict[str, Any]] = mapped_column(JSONB, server_default="{}")
    completed_at: Mapped[datetime | None]
    updated_at: Mapped[datetime] = mapped_column(server_default=func.now())
