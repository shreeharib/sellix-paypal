import uuid
from datetime import date, datetime

from sqlalchemy import Computed, func, text
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base


class DailyStock(Base):
    __tablename__ = "daily_stock"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, server_default=text("gen_random_uuid()")
    )
    merchant_id: Mapped[uuid.UUID]
    variant_id: Mapped[uuid.UUID]
    business_date: Mapped[date]
    opening: Mapped[int] = mapped_column(server_default=text("0"))
    restocked: Mapped[int] = mapped_column(server_default=text("0"))
    held: Mapped[int] = mapped_column(server_default=text("0"))
    sold: Mapped[int] = mapped_column(server_default=text("0"))
    counter_sales: Mapped[int] = mapped_column(server_default=text("0"))
    available: Mapped[int] = mapped_column(
        Computed("opening + restocked - held - sold - counter_sales", persisted=True)
    )
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(server_default=func.now())


class StockHold(Base):
    __tablename__ = "stock_holds"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, server_default=text("gen_random_uuid()")
    )
    variant_id: Mapped[uuid.UUID]
    conversation_id: Mapped[uuid.UUID | None] = mapped_column(nullable=True)
    order_id: Mapped[uuid.UUID | None] = mapped_column(nullable=True)
    quantity: Mapped[int]
    status: Mapped[str] = mapped_column(server_default=text("'held'"))
    expires_at: Mapped[datetime]
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())

