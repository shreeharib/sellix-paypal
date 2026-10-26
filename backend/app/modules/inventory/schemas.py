import uuid
from dataclasses import dataclass


@dataclass(frozen=True)
class StockItem:
    """One sellable variant in today's stock."""

    product: str
    variant: str | None
    price_minor: int
    currency: str
    available: int
    variant_id: uuid.UUID | None = None
    product_id: uuid.UUID | None = None

    @property
    def label(self) -> str:
        return f"{self.product} ({self.variant})" if self.variant else self.product

    @property
    def ref(self) -> str | None:
        """Short, stable ID the agent orders by, so it never has to retype names exactly."""
        return f"p{self.variant_id.hex[:6]}" if self.variant_id else None


@dataclass(frozen=True)
class LedgerRow:
    """One variant's stock for the day, as the merchant's Today screen shows it."""

    variant_id: uuid.UUID
    product: str
    variant: str | None
    price_minor: int
    currency: str
    opening: int
    restocked: int
    held: int
    sold: int
    counter_sales: int
    available: int


@dataclass(frozen=True)
class OpeningStockLine:
    """One line of the merchant's morning stock update."""

    product: str
    variant: str | None
    price_minor: int
    quantity: int
    currency: str = "INR"
