import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import func, text
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base


class Customer(Base):
    __tablename__ = "customers"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, server_default=text("gen_random_uuid()")
    )
    merchant_id: Mapped[uuid.UUID]
    channel: Mapped[str]
    external_id: Mapped[str]
    display_name: Mapped[str | None] = None
    primary_name: Mapped[str | None] = None
    primary_phone: Mapped[str | None] = None
    primary_email: Mapped[str | None] = None
    default_address: Mapped[dict[str, Any] | None] = mapped_column(JSONB, server_default=None)
    lifetime_orders_count: Mapped[int] = mapped_column(server_default=text("0"))
    lifetime_spent_minor: Mapped[int] = mapped_column(server_default=text("0"))
    custom_attributes: Mapped[dict[str, Any]] = mapped_column(JSONB, server_default="{}")
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(server_default=func.now())


class Conversation(Base):
    __tablename__ = "conversations"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, server_default=text("gen_random_uuid()")
    )
    merchant_id: Mapped[uuid.UUID]
    customer_id: Mapped[uuid.UUID]
    channel_connection_id: Mapped[uuid.UUID]
    agent_active: Mapped[bool] = mapped_column(server_default=text("true"))
    agent_paused_reason: Mapped[str | None]
    last_customer_message_at: Mapped[datetime | None]
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(server_default=func.now())


class Message(Base):
    __tablename__ = "messages"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, server_default=text("gen_random_uuid()")
    )
    merchant_id: Mapped[uuid.UUID]
    conversation_id: Mapped[uuid.UUID]
    direction: Mapped[str]  # inbound | outbound
    sender: Mapped[str]  # customer | agent | merchant
    external_id: Mapped[str | None]
    body: Mapped[str] = mapped_column(server_default="")
    # "metadata" is reserved by SQLAlchemy's declarative base, hence the attribute name.
    details: Mapped[dict[str, Any]] = mapped_column("metadata", JSONB, server_default="{}")
    status: Mapped[str]  # received | sending | sent | failed
    error: Mapped[str | None]
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
