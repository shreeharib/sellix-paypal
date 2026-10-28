"""Public interface of the escalations module: questions the agent asks the merchant."""

import uuid
from datetime import UTC, datetime

import structlog
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.escalations.models import Escalation

__all__ = [
    "Escalation",
    "EscalationNotFound",
    "answer",
    "close",
    "list_escalations",
    "open_escalation",
]

log = structlog.get_logger()


async def open_escalation(
    session: AsyncSession,
    *,
    merchant_id: uuid.UUID,
    conversation_id: uuid.UUID,
    question: str,
    trigger_message_id: uuid.UUID | None = None,
) -> Escalation:
    escalation = Escalation(
        merchant_id=merchant_id,
        conversation_id=conversation_id,
        trigger_message_id=trigger_message_id,
        question=question.strip(),
    )
    session.add(escalation)
    await session.flush()
    # The merchant app's "Ask me" inbox and push notifications read from this table.
    log.info(
        "escalation.opened",
        escalation_id=str(escalation.id),
        merchant_id=str(merchant_id),
        conversation_id=str(conversation_id),
        question=escalation.question,
    )
    return escalation


class EscalationNotFound(LookupError):
    pass


async def list_escalations(
    session: AsyncSession, merchant_id: uuid.UUID, *, status: str | None = "open", limit: int = 100
) -> list[Escalation]:
    query = select(Escalation).where(Escalation.merchant_id == merchant_id)
    if status:
        query = query.where(Escalation.status == status)
    return list(await session.scalars(query.order_by(Escalation.created_at.desc()).limit(limit)))


async def answer(
    session: AsyncSession, merchant_id: uuid.UUID, escalation_id: uuid.UUID, text: str
) -> Escalation:
    """Record the merchant's answer. The caller passes it on to the customer."""
    escalation = await _get(session, merchant_id, escalation_id)
    if escalation.status != "open":
        raise ValueError("This question has already been answered or closed")
    if not text.strip():
        raise ValueError("The answer is empty")
    escalation.answer = text.strip()
    escalation.status = "answered"
    escalation.answered_at = datetime.now(UTC)
    return escalation


async def close(
    session: AsyncSession, merchant_id: uuid.UUID, escalation_id: uuid.UUID
) -> Escalation:
    """Dismiss a question without passing anything on (e.g. handled in the chat directly)."""
    escalation = await _get(session, merchant_id, escalation_id)
    escalation.status = "closed"
    return escalation


async def _get(
    session: AsyncSession, merchant_id: uuid.UUID, escalation_id: uuid.UUID
) -> Escalation:
    escalation = await session.scalar(
        select(Escalation)
        .where(Escalation.id == escalation_id, Escalation.merchant_id == merchant_id)
        .with_for_update()
    )
    if escalation is None:
        raise EscalationNotFound(f"No question {escalation_id}")
    return escalation
