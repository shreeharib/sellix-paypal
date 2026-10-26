import uuid
from dataclasses import dataclass, field
from datetime import datetime
from typing import Literal


@dataclass(frozen=True)
class OrderLineRequest:
    product: str
    variant: str | None
    quantity: int
    # The item's ID from today's stock (StockItem.ref). When given, it decides the item and
    # the names are only for messages.
    ref: str | None = None

    @property
    def label(self) -> str:
        name = f"{self.product} ({self.variant})" if self.variant else self.product
        return name or self.ref or "an item"


@dataclass(frozen=True)
class OrderRequest:
    """What the customer asked for, as the agent understood it."""

    lines: tuple[OrderLineRequest, ...]
    fulfilment: Literal["pickup", "delivery"] | None = None
    delivery_address: str | None = None
    needed_by: str | None = None
    notes: str | None = None


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
    fulfilment: str | None
    delivery_address: str | None
    needed_by: str | None
    notes: str | None
    customer_id: uuid.UUID
    conversation_id: uuid.UUID | None
    created_at: datetime
    paid_at: datetime | None
    hold_expires_at: datetime | None
    items: tuple[OrderItemSummary, ...]


@dataclass(frozen=True)
class DaySummary:
    awaiting_payment: int
    paid: int
    revenue_minor_by_currency: dict[str, int]
