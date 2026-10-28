import uuid
from datetime import datetime

from sqlalchemy import func, text
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base


class Payment(Base):
    """One payment attempt for an order with a payment provider."""

    __tablename__ = "payments"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, server_default=text("gen_random_uuid()")
    )
    merchant_id: Mapped[uuid.UUID]
    order_id: Mapped[uuid.UUID]
    provider: Mapped[str]  # paypal | razorpay | cashfree | upi_manual | manual | cash | stripe
    # upi | card | paypal_wallet | cash
    method: Mapped[str | None] = mapped_column(nullable=True, default="upi")
    kind: Mapped[str] = mapped_column(server_default=text("'full'"))  # full | deposit | balance
    provider_order_id: Mapped[str | None] = mapped_column(nullable=True, default=None)
    provider_capture_id: Mapped[str | None] = mapped_column(nullable=True, default=None)
    status: Mapped[str]  # created | approved | completed | denied | refunded | failed
    currency: Mapped[str]
    amount_minor: Mapped[int]
    fee_minor: Mapped[int] = mapped_column(server_default=text("0"))
    approve_url: Mapped[str | None] = mapped_column(nullable=True, default=None)
    paid_at: Mapped[datetime | None] = mapped_column(nullable=True, default=None)
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(server_default=func.now())
