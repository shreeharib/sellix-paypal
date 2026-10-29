import uuid
from datetime import datetime

from sqlalchemy import func, text
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base


class MissedDemand(Base):
    """Something a customer wanted that the shop couldn't sell (for Insights)."""

    __tablename__ = "missed_demands"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, server_default=text("gen_random_uuid()")
    )
    merchant_id: Mapped[uuid.UUID]
    conversation_id: Mapped[uuid.UUID | None]
    requested_item_name: Mapped[str]
    variant_id: Mapped[uuid.UUID | None] = mapped_column(nullable=True, default=None)
    quantity_requested: Mapped[int] = mapped_column(server_default=text("1"))
    reason: Mapped[str]  # sold_out | not_stocked | shop_closed | other
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
