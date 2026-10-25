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
    provider: Mapped[str]
    provider_order_id: Mapped[str]
    provider_capture_id: Mapped[str | None]
    status: Mapped[str]  # created | approved | completed | denied | refunded | failed
    currency: Mapped[str]
    amount_minor: Mapped[int]
    approve_url: Mapped[str | None]
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(server_default=func.now())
