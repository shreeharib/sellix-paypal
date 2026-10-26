import uuid
from datetime import date, datetime
from typing import Any

from sqlalchemy import Identity, func, text
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base


class Order(Base):
    __tablename__ = "orders"
    __mapper_args__ = {"eager_defaults": True}  # fetch the generated order number on insert

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, server_default=text("gen_random_uuid()")
    )
    number: Mapped[int] = mapped_column(Identity(start=1001), unique=True)
    merchant_id: Mapped[uuid.UUID]
    customer_id: Mapped[uuid.UUID]
    conversation_id: Mapped[uuid.UUID | None]
    status: Mapped[str]
    business_date: Mapped[date]
    currency: Mapped[str]
    total_minor: Mapped[int]
    fulfilment: Mapped[str | None]
    delivery_address: Mapped[str | None]
    needed_by: Mapped[str | None]
    notes: Mapped[str | None]
    hold_expires_at: Mapped[datetime | None]
    paid_at: Mapped[datetime | None]
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(server_default=func.now())


class OrderItem(Base):
    __tablename__ = "order_items"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, server_default=text("gen_random_uuid()")
    )
    merchant_id: Mapped[uuid.UUID]
    order_id: Mapped[uuid.UUID]
    variant_id: Mapped[uuid.UUID]
    product_name: Mapped[str]
    variant_name: Mapped[str | None]
    unit_price_minor: Mapped[int]
    quantity: Mapped[int]


class OrderEvent(Base):
    """Audit trail: every change to an order, and who or what made it."""

    __tablename__ = "order_events"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, server_default=text("gen_random_uuid()")
    )
    merchant_id: Mapped[uuid.UUID]
    order_id: Mapped[uuid.UUID]
    event: Mapped[str]
    from_status: Mapped[str | None]
    to_status: Mapped[str | None]
    actor: Mapped[str]  # agent | customer | merchant | system | paypal
    details: Mapped[dict[str, Any]] = mapped_column(JSONB, server_default="{}")
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())


class SavedQuote(Base):
    """Prices and a total code worked out and the agent showed the customer. An order can only
    be placed from one of these, and at most once."""

    __tablename__ = "quotes"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, server_default=text("gen_random_uuid()")
    )
    merchant_id: Mapped[uuid.UUID]
    conversation_id: Mapped[uuid.UUID]
    lines: Mapped[list[dict[str, Any]]] = mapped_column(JSONB)
    currency: Mapped[str]
    total_minor: Mapped[int]
    fulfilment: Mapped[str | None]
    delivery_address: Mapped[str | None]
    needed_by: Mapped[str | None]
    notes: Mapped[str | None]
    status: Mapped[str] = mapped_column(server_default="open")  # open | superseded | placed
    order_id: Mapped[uuid.UUID | None]
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
