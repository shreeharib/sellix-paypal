import uuid
from datetime import datetime

from sqlalchemy import func, text
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base


class AiUsage(Base):
    """One model call, for the per-merchant cost meter."""

    __tablename__ = "ai_usage"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, server_default=text("gen_random_uuid()")
    )
    merchant_id: Mapped[uuid.UUID | None]
    conversation_id: Mapped[uuid.UUID | None]
    purpose: Mapped[str]
    model: Mapped[str]
    input_tokens: Mapped[int | None]
    output_tokens: Mapped[int | None]
    latency_ms: Mapped[int]
    succeeded: Mapped[bool]
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
