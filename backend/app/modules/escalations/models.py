import uuid
from datetime import datetime

from sqlalchemy import Text, func, text
from sqlalchemy.dialects.postgresql import ARRAY
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
    # The agent's suggested answers, shown to the merchant as one-tap replies.
    suggested_answers: Mapped[list[str]] = mapped_column(
        ARRAY(Text), server_default=text("'{}'"), default=list
    )
    status: Mapped[str] = mapped_column(server_default="open")
    answer: Mapped[str | None]
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
    answered_at: Mapped[datetime | None]
    # sent | pending_window | human_agent | expired (see the window_and_pending migration)
    answer_delivery: Mapped[str | None] = mapped_column(nullable=True, default=None)
    window_warned_at: Mapped[datetime | None] = mapped_column(nullable=True, default=None)
