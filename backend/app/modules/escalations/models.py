import uuid
from datetime import datetime

from sqlalchemy import func, text
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base


class Escalation(Base):
    __tablename__ = "escalations"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, server_default=text("gen_random_uuid()")
    )
    merchant_id: Mapped[uuid.UUID]
    conversation_id: Mapped[uuid.UUID]
    trigger_message_id: Mapped[uuid.UUID | None]
    question: Mapped[str]
    status: Mapped[str] = mapped_column(server_default="open")
    answer: Mapped[str | None]
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
    answered_at: Mapped[datetime | None]
