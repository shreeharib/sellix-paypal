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
    conversation_id: Mapped[uuid.UUID | None] = mapped_column(nullable=True, default=None)
    order_number: Mapped[str | None] = mapped_column(nullable=True, default=None)
    source_channel: Mapped[str] = mapped_column(server_default=text("'instagram'"))
    placed_by: Mapped[str] = mapped_column(server_default=text("'customer'"))
    fulfilment: Mapped[str | None] = mapped_column(nullable=True, default=None)
    delivery_type: Mapped[str | None] = mapped_column(
        nullable=True, server_default=text("'pickup'")
    )
    delivery_slot: Mapped[datetime | None] = mapped_column(nullable=True, default=None)
    needed_by: Mapped[str | None] = mapped_column(nullable=True, default=None)
    delivery_address: Mapped[str | None] = mapped_column(nullable=True, default=None)
    delivery_notes: Mapped[str | None] = mapped_column(nullable=True, default=None)
    notes: Mapped[str | None] = mapped_column(nullable=True, default=None)
    status: Mapped[str]
    payment_status: Mapped[str] = mapped_column(server_default=text("'pending'"))
    business_date: Mapped[date]
    currency: Mapped[str]
    total_minor: Mapped[int] = mapped_column(server_default=text("0"))
    subtotal_minor: Mapped[int] = mapped_column(server_default=text("0"))
    discount_minor: Mapped[int] = mapped_column(server_default=text("0"))
    delivery_fee_minor: Mapped[int] = mapped_column(server_default=text("0"))
    total_amount_minor: Mapped[int] = mapped_column(server_default=text("0"))
    total_cost_minor: Mapped[int] = mapped_column(server_default=text("0"))
    hold_expires_at: Mapped[datetime | None] = mapped_column(nullable=True, default=None)
    paid_at: Mapped[datetime | None] = mapped_column(nullable=True, default=None)
    custom_attributes: Mapped[dict[str, Any]] = mapped_column(JSONB, server_default="{}")
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(server_default=func.now())


class OrderItem(Base):
    __tablename__ = "order_items"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, server_default=text("gen_random_uuid()")
    )
    merchant_id: Mapped[uuid.UUID | None] = mapped_column(nullable=True, default=None)
    order_id: Mapped[uuid.UUID]
    variant_id: Mapped[uuid.UUID]
    product_name: Mapped[str | None] = mapped_column(nullable=True, default=None)
    variant_name: Mapped[str | None] = mapped_column(nullable=True, default=None)
    quantity: Mapped[int]
    unit_price_minor: Mapped[int] = mapped_column(server_default=text("0"))
    unit_cost_minor: Mapped[int] = mapped_column(server_default=text("0"))


class OrderTimeline(Base):
    """Timeline history auto-populated by trg_order_timeline in enterprise_schema.sql."""

    __tablename__ = "order_timeline"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, server_default=text("gen_random_uuid()")
    )
    order_id: Mapped[uuid.UUID]
    from_status: Mapped[str | None] = mapped_column(nullable=True, default=None)
    to_status: Mapped[str]
    triggered_by: Mapped[str]
    comment: Mapped[str | None] = mapped_column(nullable=True, default=None)
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())


class OrderEvent(Base):
    """Audit trail: every change to an order, and who or what made it."""

    __tablename__ = "order_events"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, server_default=text("gen_random_uuid()")
    )
    merchant_id: Mapped[uuid.UUID]
    order_id: Mapped[uuid.UUID]
    event: Mapped[str]
    from_status: Mapped[str | None] = mapped_column(nullable=True, default=None)
    to_status: Mapped[str | None] = mapped_column(nullable=True, default=None)
    actor: Mapped[str]  # agent | customer | merchant | system | paypal
    details: Mapped[dict[str, Any]] = mapped_column(JSONB, server_default="{}")
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())


class Refund(Base):
    """Refund record mapped to enterprise_schema.sql refunds table."""

    __tablename__ = "refunds"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, server_default=text("gen_random_uuid()")
    )
    order_id: Mapped[uuid.UUID]
    refund_amount_minor: Mapped[int]
    reason: Mapped[str | None] = mapped_column(nullable=True, default=None)
    is_restocked: Mapped[bool] = mapped_column(server_default=text("true"))
    processed_at: Mapped[datetime] = mapped_column(server_default=func.now())
