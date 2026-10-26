import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import func, text
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base


class Merchant(Base):
    __tablename__ = "merchants"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, server_default=text("gen_random_uuid()")
    )
    name: Mapped[str]
    timezone: Mapped[str] = mapped_column(server_default="Asia/Kolkata")
    agent_enabled: Mapped[bool] = mapped_column(server_default=text("true"))
    # hours.OpeningHours as JSON; None until the merchant sets them.
    opening_hours: Mapped[dict[str, Any] | None] = mapped_column(JSONB)
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(server_default=func.now())
