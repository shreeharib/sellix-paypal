import uuid
from datetime import datetime
from decimal import Decimal
from typing import Any

from sqlalchemy import Text, func, text
from sqlalchemy.dialects.postgresql import ARRAY, JSONB
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


class AgentTurn(Base):
    """One v2 agent turn: what it saw and used, what it cost, how it ended."""

    __tablename__ = "agent_turns"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, server_default=text("gen_random_uuid()")
    )
    merchant_id: Mapped[uuid.UUID]
    conversation_id: Mapped[uuid.UUID]
    trigger_message_id: Mapped[uuid.UUID]
    status: Mapped[str] = mapped_column(server_default=text("'running'"))
    mode: Mapped[str] = mapped_column(server_default=text("'live'"))  # live | shadow | draft
    would_send: Mapped[str | None] = mapped_column(nullable=True, default=None)
    stage_before: Mapped[str | None] = mapped_column(nullable=True, default=None)
    stage_after: Mapped[str | None] = mapped_column(nullable=True, default=None)
    playbook: Mapped[str | None] = mapped_column(nullable=True, default=None)
    prompt_refs: Mapped[list[str]] = mapped_column(ARRAY(Text), server_default=text("'{}'"))
    models: Mapped[list[str]] = mapped_column(ARRAY(Text), server_default=text("'{}'"))
    model_calls: Mapped[int] = mapped_column(server_default=text("0"))
    tool_calls: Mapped[int] = mapped_column(server_default=text("0"))
    input_tokens: Mapped[int] = mapped_column(server_default=text("0"))
    output_tokens: Mapped[int] = mapped_column(server_default=text("0"))
    cost_usd: Mapped[Decimal | None] = mapped_column(nullable=True, default=None)
    latency_ms: Mapped[int | None] = mapped_column(nullable=True, default=None)
    error: Mapped[str | None] = mapped_column(nullable=True, default=None)
    started_at: Mapped[datetime] = mapped_column(server_default=func.now())
    finished_at: Mapped[datetime | None] = mapped_column(nullable=True, default=None)


class TurnStep(Base):
    """A model call or tool call of a turn; a resumed turn replays these."""

    __tablename__ = "turn_steps"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, server_default=text("gen_random_uuid()")
    )
    turn_id: Mapped[uuid.UUID]
    step: Mapped[int]
    kind: Mapped[str]  # model | tool
    name: Mapped[str]
    idempotency_key: Mapped[str]
    request: Mapped[dict[str, Any]] = mapped_column(JSONB, server_default="{}")
    result: Mapped[dict[str, Any]] = mapped_column(JSONB, server_default="{}")
    input_tokens: Mapped[int | None] = mapped_column(nullable=True, default=None)
    output_tokens: Mapped[int | None] = mapped_column(nullable=True, default=None)
    latency_ms: Mapped[int | None] = mapped_column(nullable=True, default=None)
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())


class CustomerMemory(Base):
    """A fact a customer told the shop (allow-listed keys only; see the memory migration)."""

    __tablename__ = "customer_memories"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, server_default=text("gen_random_uuid()")
    )
    merchant_id: Mapped[uuid.UUID]
    customer_id: Mapped[uuid.UUID]
    key: Mapped[str]
    value: Mapped[Any] = mapped_column(JSONB)
    source_message_id: Mapped[uuid.UUID | None] = mapped_column(nullable=True, default=None)
    confidence: Mapped[Decimal] = mapped_column(server_default=text("0.9"))
    expires_at: Mapped[datetime | None] = mapped_column(nullable=True, default=None)
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(server_default=func.now())


class ConversationSummary(Base):
    """The older part of a long conversation, summarised without amounts."""

    __tablename__ = "conversation_summaries"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, server_default=text("gen_random_uuid()")
    )
    merchant_id: Mapped[uuid.UUID]
    conversation_id: Mapped[uuid.UUID]
    summary: Mapped[str]
    covers_until_message_id: Mapped[uuid.UUID]
    message_count: Mapped[int]
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())


class GlossaryTerm(Base):
    __tablename__ = "glossary_terms"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, server_default=text("gen_random_uuid()")
    )
    merchant_id: Mapped[uuid.UUID | None]  # None: the global glossary
    term: Mapped[str]
    meaning: Mapped[str]


class MerchantRule(Base):
    """An answer the merchant chose to have the agent always give."""

    __tablename__ = "merchant_rules"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, server_default=text("gen_random_uuid()")
    )
    merchant_id: Mapped[uuid.UUID]
    question: Mapped[str]
    answer: Mapped[str]
    source_escalation_id: Mapped[uuid.UUID | None] = mapped_column(nullable=True, default=None)
    active: Mapped[bool] = mapped_column(server_default=text("true"))
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
