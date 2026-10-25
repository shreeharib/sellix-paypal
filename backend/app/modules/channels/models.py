import uuid
from datetime import datetime

from sqlalchemy import func, text
from sqlalchemy.dialects.postgresql import ARRAY
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.types import Text

from app.core.db import Base


class ChannelConnection(Base):
    """A merchant's connected Instagram (later WhatsApp) account."""

    __tablename__ = "channel_connections"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, server_default=text("gen_random_uuid()")
    )
    merchant_id: Mapped[uuid.UUID]
    channel: Mapped[str]
    external_account_id: Mapped[str]
    username: Mapped[str | None]
    access_token_encrypted: Mapped[str]
    token_expires_at: Mapped[datetime | None]
    token_refreshed_at: Mapped[datetime] = mapped_column(server_default=func.now())
    scopes: Mapped[list[str]] = mapped_column(ARRAY(Text), server_default="{}")
    status: Mapped[str] = mapped_column(server_default="active")
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(server_default=func.now())
