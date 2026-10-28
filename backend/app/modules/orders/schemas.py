import uuid
from dataclasses import dataclass, field
from datetime import date, datetime
from typing import Literal


@dataclass(frozen=True)
class OrderLineRequest:
    product: str
    variant: str | None
    quantity: int


@dataclass(frozen=True)
class OrderRequest:
    """What the customer asked for, as the agent understood it."""

    lines: tuple[OrderLineRequest, ...]
    fulfilment_method: str | None = None
    fulfilment: str | None = None  # alias for backwards compatibility
    delivery_address: str | None = None
    scheduled_date: date | None = None
    scheduled_window: str | None = None
    customer_note: str | None = None
    needed_by: str | None = None  # alias for backwards compatibility
    notes: str | None = None  # alias for backwards compatibility
    channel: str = "instagram"
    placed_by: str = "customer"


@dataclass(frozen=True)
class QuoteLine:
    variant_id: uuid.UUID
    label: str
    product: str
    variant: str | None
    unit_price_minor: int
    currency: str
    quantity: int

    @property
    def subtotal_minor(self) -> int:
        return self.unit_price_minor * self.quantity


@dataclass(frozen=True)
class Quote:
    """Exact prices and totals from today's stock; problems explain anything that can't be sold."""

    lines: tuple[QuoteLine, ...]
    currency: str | None
    total_minor: int
    problems: tuple[str, ...] = field(default=())

    @property
    def ok(self) -> bool:
        return bool(self.lines) and not self.problems


@dataclass(frozen=True)
class PlacedOrder:
    order_id: uuid.UUID
    number: int
    currency: str
    total_minor: int
    hold_minutes: int


PaymentOutcome = Literal["paid", "already_paid", "paid_stock_short", "amount_mismatch"]


@dataclass(frozen=True)
class PaymentResult:
    order_id: uuid.UUID
    number: int
    merchant_id: uuid.UUID
    conversation_id: uuid.UUID | None
    currency: str
    total_minor: int
    outcome: PaymentOutcome


@dataclass(frozen=True)
class ExpiredOrder:
    order_id: uuid.UUID
    number: int
    conversation_id: uuid.UUID | None


@dataclass(frozen=True)
class OrderItemSummary:
    product: str
    variant: str | None
    quantity: int
    unit_price_minor: int


@dataclass(frozen=True)
class OrderSummary:
    """An order as the merchant's Orders screen shows it."""

    id: uuid.UUID
    number: int
    status: str
    currency: str
    total_minor: int
    customer_id: uuid.UUID
    conversation_id: uuid.UUID | None
    created_at: datetime
    paid_at: datetime | None
    hold_expires_at: datetime | None
    items: tuple[OrderItemSummary, ...]
    payment_status: str = "unpaid"
    fulfilment_status: str = "unfulfilled"
    fulfilment_method: str | None = "pickup"
    channel: str = "instagram"
    delivery_address: str | None = None
    customer_note: str | None = None
    scheduled_date: date | None = None
    scheduled_window: str | None = None
    order_number: str | None = None
    merchant_id: uuid.UUID | None = None

    # Backward compatibility properties
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
    def notes(self) -> str | None:
        return self.customer_note

    @property
    def needed_by(self) -> str | None:
        if self.scheduled_date and self.scheduled_window:
            return f"{self.scheduled_date} {self.scheduled_window}"
        if self.scheduled_date:
            return str(self.scheduled_date)
        return self.scheduled_window


@dataclass(frozen=True)
class DaySummary:
    awaiting_payment: int
    paid: int
    revenue_minor_by_currency: dict[str, int]
