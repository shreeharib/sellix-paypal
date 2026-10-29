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

    # Omnichannel Origin & Actor
    channel: Mapped[str] = mapped_column(server_default=text("'instagram'"))
    placed_by: Mapped[str] = mapped_column(server_default=text("'customer'"))

    # Orthogonal Triple Status
    status: Mapped[str]
    payment_status: Mapped[str] = mapped_column(server_default=text("'unpaid'"))
    fulfilment_status: Mapped[str] = mapped_column(server_default=text("'unfulfilled'"))

    # Logistics Handover (Canonical fulfilment_method)
    fulfilment_method: Mapped[str | None] = mapped_column(
        nullable=True, server_default=text("'pickup'")
    )
    pickup_location_id: Mapped[uuid.UUID | None] = mapped_column(nullable=True, default=None)
    delivery_address: Mapped[str | None] = mapped_column(nullable=True, default=None)
    scheduled_date: Mapped[date | None] = mapped_column(nullable=True, default=None)
    scheduled_window: Mapped[str | None] = mapped_column(nullable=True, default=None)
    customer_note: Mapped[str | None] = mapped_column(nullable=True, default=None)

    # Financials (All in integer minor units)
    business_date: Mapped[date]
    currency: Mapped[str]
    subtotal_minor: Mapped[int] = mapped_column(server_default=text("0"))
    discount_minor: Mapped[int] = mapped_column(server_default=text("0"))
    shipping_minor: Mapped[int] = mapped_column(server_default=text("0"))
    tax_minor: Mapped[int] = mapped_column(server_default=text("0"))
    total_minor: Mapped[int] = mapped_column(server_default=text("0"))
    amount_paid_minor: Mapped[int] = mapped_column(server_default=text("0"))
    deposit_required_minor: Mapped[int] = mapped_column(server_default=text("0"))
    total_cost_minor: Mapped[int] = mapped_column(server_default=text("0"))

    # Lifecycle & Timestamps
    hold_expires_at: Mapped[datetime | None] = mapped_column(nullable=True, default=None)
    cancelled_reason: Mapped[str | None] = mapped_column(nullable=True, default=None)
    paid_at: Mapped[datetime | None] = mapped_column(nullable=True, default=None)
    custom_attributes: Mapped[dict[str, Any]] = mapped_column(JSONB, server_default="{}")
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(server_default=func.now())

    # Convenience properties for display & backward compatibility
    @property
    def order_number(self) -> str:
        return f"ORD-{self.number}"

    @property
    def fulfilment(self) -> str | None:
        return self.fulfilment_method

    @property
    def delivery_type(self) -> str | None:
        return self.fulfilment_method

    @property
    def source_channel(self) -> str:
        return self.channel

    @property
    def total_amount_minor(self) -> int:
        return self.total_minor

    @property
    def delivery_fee_minor(self) -> int:
        return self.shipping_minor

    @property
    def notes(self) -> str | None:
        return self.customer_note

    @property
    def needed_by(self) -> str | None:
        if self.scheduled_date and self.scheduled_window:
            return f"{self.scheduled_date} {self.scheduled_window}"
        if self.scheduled_date:
            return str(self.scheduled_date)
        return self.scheduled_window


class OrderItem(Base):
    __tablename__ = "order_items"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, server_default=text("gen_random_uuid()")
    )
    merchant_id: Mapped[uuid.UUID | None] = mapped_column(nullable=True, default=None)
    order_id: Mapped[uuid.UUID]
    variant_id: Mapped[uuid.UUID]
    product_name: Mapped[str | None] = mapped_column(nullable=True, default=None)
    variant_label: Mapped[str | None] = mapped_column(nullable=True, default=None)
    quantity: Mapped[int]
    unit_price_minor: Mapped[int] = mapped_column(server_default=text("0"))
    line_total_minor: Mapped[int] = mapped_column(server_default=text("0"))
    fulfilment_status: Mapped[str] = mapped_column(server_default=text("'unfulfilled'"))
    option_values: Mapped[dict[str, Any]] = mapped_column(JSONB, server_default="{}")
    personalization: Mapped[dict[str, Any]] = mapped_column(JSONB, server_default="{}")

    @property
    def variant_name(self) -> str | None:
        return self.variant_label


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


class RefundRequest(Base):
    """A refund asked of the payment provider; a `refunds` row is written once it completes."""

    __tablename__ = "refund_requests"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, server_default=text("gen_random_uuid()")
    )
    merchant_id: Mapped[uuid.UUID]
    order_id: Mapped[uuid.UUID]
    amount_minor: Mapped[int]
    reason: Mapped[str | None] = mapped_column(nullable=True, default=None)
    is_restocked: Mapped[bool] = mapped_column(server_default=text("true"))
    # pending | completed | failed
    status: Mapped[str] = mapped_column(server_default=text("'pending'"))
    provider_refund_id: Mapped[str | None] = mapped_column(nullable=True, default=None)
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(server_default=func.now())


class QuoteRecord(Base):
    """A priced offer sent to the customer as a card (agent-phase-2.md section 6.4)."""

    __tablename__ = "quotes"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, server_default=text("gen_random_uuid()")
    )
    merchant_id: Mapped[uuid.UUID]
    conversation_id: Mapped[uuid.UUID]
    customer_id: Mapped[uuid.UUID]
    business_date: Mapped[date]
    lines: Mapped[list[dict[str, Any]]] = mapped_column(JSONB)
    currency: Mapped[str]
    total_minor: Mapped[int]
    fulfilment: Mapped[str | None] = mapped_column(nullable=True, default=None)
    delivery_address: Mapped[str | None] = mapped_column(nullable=True, default=None)
    needed_by: Mapped[str | None] = mapped_column(nullable=True, default=None)
    notes: Mapped[str | None] = mapped_column(nullable=True, default=None)
    status: Mapped[str] = mapped_column(server_default=text("'open'"))
    expires_at: Mapped[datetime]
    shown_message_id: Mapped[uuid.UUID | None] = mapped_column(nullable=True, default=None)
    shown_at: Mapped[datetime | None] = mapped_column(nullable=True, default=None)
    order_id: Mapped[uuid.UUID | None] = mapped_column(nullable=True, default=None)
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(server_default=func.now())
