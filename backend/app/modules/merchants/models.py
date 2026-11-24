import uuid
from datetime import datetime
from decimal import Decimal

from sqlalchemy import Text, func, text
from sqlalchemy.dialects.postgresql import ARRAY
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base


class Merchant(Base):
    __tablename__ = "merchants"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, server_default=text("gen_random_uuid()")
    )
    name: Mapped[str]
    timezone: Mapped[str] = mapped_column(server_default="Asia/Kolkata")
    # New shops start off on v2; finishing the onboarding switches the assistant on.
    agent_enabled: Mapped[bool] = mapped_column(server_default=text("false"))
    agent_engine: Mapped[str] = mapped_column(server_default=text("'v2'"))  # v1 | v2
    never_promise: Mapped[list[str]] = mapped_column(ARRAY(Text), server_default=text("'{}'"))
    ai_daily_budget_usd: Mapped[Decimal | None] = mapped_column(nullable=True, default=None)
    menu_image_url: Mapped[str | None] = mapped_column(nullable=True, default=None)
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(server_default=func.now())


class DataDeletionRequest(Base):
    """A finished shop deletion: only its confirmation code, source and outcome (no shop data)."""

    __tablename__ = "data_deletion_requests"

    code: Mapped[str] = mapped_column(primary_key=True)
    source: Mapped[str]  # app | meta
    status: Mapped[str]  # deleted | no_data
    requested_at: Mapped[datetime] = mapped_column(server_default=func.now())
