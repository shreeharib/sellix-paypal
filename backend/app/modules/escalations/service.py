"""Public interface of the escalations module: questions the agent asks the merchant."""

import uuid
from collections.abc import Sequence
from datetime import UTC, datetime

import structlog
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.escalations.models import Escalation
from app.modules.escalations.schemas import AnswerDelivery, EscalationItem

__all__ = [
    "AnswerDelivery",
    "EscalationItem",
    "EscalationNotFound",
    "answer",
    "close",
    "list_escalations",
    "mark_window_warned",
    "open_escalation",
    "pending_answers",
    "set_answer_delivery",
    "unwarned_open_questions",
]

log = structlog.get_logger()


async def open_escalation(
    session: AsyncSession,
    *,
    merchant_id: uuid.UUID,
    conversation_id: uuid.UUID,
    question: str,
    trigger_message_id: uuid.UUID | None = None,
    suggested_answers: Sequence[str] = (),
) -> EscalationItem:
    escalation = Escalation(
        merchant_id=merchant_id,
        conversation_id=conversation_id,
        trigger_message_id=trigger_message_id,
        question=question.strip(),
        suggested_answers=_clean_options(suggested_answers),
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
    return _to_item(escalation)


async def has_open(session: AsyncSession, conversation_id: uuid.UUID, question: str) -> bool:
    """Is this exact question already waiting for the owner in this chat?"""
    found = await session.scalar(
        select(Escalation.id)
        .where(
            Escalation.conversation_id == conversation_id,
            Escalation.status == "open",
            Escalation.question == question.strip(),
        )
        .limit(1)
    )
    return found is not None


class EscalationNotFound(LookupError):
    pass


async def list_escalations(
    session: AsyncSession, merchant_id: uuid.UUID, *, status: str | None = "open", limit: int = 100
) -> list[EscalationItem]:
    query = select(Escalation).where(Escalation.merchant_id == merchant_id)
    if status:
        query = query.where(Escalation.status == status)
    rows = await session.scalars(query.order_by(Escalation.created_at.desc()).limit(limit))
    return [_to_item(e) for e in rows]


async def answer(
    session: AsyncSession, merchant_id: uuid.UUID, escalation_id: uuid.UUID, text: str
) -> EscalationItem:
    """Record the merchant's answer. The caller passes it on to the customer."""
    escalation = await _get(session, merchant_id, escalation_id)
    if escalation.status != "open":
        raise ValueError("This question has already been answered or closed")
    if not text.strip():
        raise ValueError("The answer is empty")
    escalation.answer = text.strip()
    escalation.status = "answered"
    escalation.answered_at = datetime.now(UTC)
    return _to_item(escalation)


async def close(
    session: AsyncSession, merchant_id: uuid.UUID, escalation_id: uuid.UUID
) -> EscalationItem:
    """Dismiss a question without passing anything on (e.g. handled in the chat directly)."""
    escalation = await _get(session, merchant_id, escalation_id)
    escalation.status = "closed"
    return _to_item(escalation)


async def set_answer_delivery(
    session: AsyncSession, escalation_id: uuid.UUID, delivery: AnswerDelivery
) -> None:
    """Record how the merchant's answer reached (or will reach) the customer."""
    escalation = await session.get(Escalation, escalation_id, with_for_update=True)
    if escalation is not None:
        escalation.answer_delivery = delivery


async def pending_answers(
    session: AsyncSession, conversation_id: uuid.UUID
) -> list[EscalationItem]:
    """Answers waiting for the customer to write again (their window had closed)."""
    rows = await session.scalars(
        select(Escalation)
        .where(
            Escalation.conversation_id == conversation_id,
            Escalation.answer_delivery == "pending_window",
        )
        .order_by(Escalation.answered_at)
        .with_for_update()
    )
    return [_to_item(escalation) for escalation in rows]


async def unwarned_open_questions(session: AsyncSession) -> list[EscalationItem]:
    """Open questions the merchant hasn't yet been warned about (window closing)."""
    rows = await session.scalars(
        select(Escalation).where(Escalation.status == "open", Escalation.window_warned_at.is_(None))
    )
    return [_to_item(escalation) for escalation in rows]


async def mark_window_warned(session: AsyncSession, escalation_ids: list[uuid.UUID]) -> None:
    if escalation_ids:
        await session.execute(
            update(Escalation)
            .where(Escalation.id.in_(escalation_ids))
            .values(window_warned_at=datetime.now(UTC))
        )


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


_LEGACY_MARK = "Suggested answers: "


def _split_legacy(question: str) -> tuple[str, list[str]]:
    """Older questions end with a "Suggested answers:" line instead of the column."""
    lines = question.strip().splitlines()
    if len(lines) > 1 and lines[-1].startswith(_LEGACY_MARK):
        options = lines[-1].removeprefix(_LEGACY_MARK).split(" / ")
        return chr(10).join(lines[:-1]).strip(), _clean_options(options)
    return question.strip(), []


def _to_item(escalation: Escalation) -> EscalationItem:
    question, legacy = _split_legacy(escalation.question)
    return EscalationItem(
        id=escalation.id,
        merchant_id=escalation.merchant_id,
        conversation_id=escalation.conversation_id,
        trigger_message_id=escalation.trigger_message_id,
        question=question,
        status=escalation.status,
        answer=escalation.answer,
        created_at=escalation.created_at,
        answered_at=escalation.answered_at,
        answer_delivery=escalation.answer_delivery,
        window_warned_at=escalation.window_warned_at,
        suggested_answers=tuple(escalation.suggested_answers or legacy),
    )


MAX_SUGGESTIONS = 3
MAX_SUGGESTION_CHARS = 120


def _clean_options(options: Sequence[str]) -> list[str]:
    """The suggested answers, trimmed, without blanks or repeats, as many as the app shows."""
    cleaned: list[str] = []
    for option in options:
        text = " ".join(option.split())[:MAX_SUGGESTION_CHARS]
        if text and text.lower() not in (seen.lower() for seen in cleaned):
            cleaned.append(text)
    return cleaned[:MAX_SUGGESTIONS]
