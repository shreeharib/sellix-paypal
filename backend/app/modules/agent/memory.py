"""Agent memory (agent-phase-2.md section 8).

- Episodic, per customer per shop: facts the customer told us (allow-listed keys), and
  summaries of older conversation.
- Semantic, per shop: the glossary of code-mixed words (plus a global one).
- Procedural, per shop: the merchant's saved answers ("Always answer this way").
"""

import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any, Literal

import structlog
from sqlalchemy import delete, func, or_, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import session_scope
from app.modules.agent import llm, prompt_store
from app.modules.agent.guardrails import output
from app.modules.agent.models import ConversationSummary, CustomerMemory, GlossaryTerm, MerchantRule
from app.modules.agent.schemas import ChatMessage
from app.modules.conversations import service as conversations

log = structlog.get_logger()

FactKey = Literal[
    "name", "preferred_language", "address", "usual_order", "dietary_note", "occasion"
]
FACT_LIFETIME: dict[str, timedelta] = {"address": timedelta(days=365)}
SUMMARY_AFTER_MESSAGES = 30  # longer conversations get their older part summarised
RECENT_MESSAGES_KEPT = 20  # the part the model sees as messages, not as a summary


@dataclass(frozen=True)
class Fact:
    key: str
    value: Any
    updated_at: datetime


async def remember(
    session: AsyncSession,
    *,
    merchant_id: uuid.UUID,
    customer_id: uuid.UUID,
    key: FactKey,
    value: Any,
    source_message_id: uuid.UUID | None,
) -> None:
    """Save a fact; a newer fact replaces the older one for the same key."""
    lifetime = FACT_LIFETIME.get(key)
    values = {
        "value": value,
        "source_message_id": source_message_id,
        "expires_at": datetime.now(UTC) + lifetime if lifetime else None,
        "updated_at": func.now(),
    }
    await session.execute(
        pg_insert(CustomerMemory)
        .values(merchant_id=merchant_id, customer_id=customer_id, key=key, **values)
        .on_conflict_do_update(index_elements=["merchant_id", "customer_id", "key"], set_=values)
    )


async def facts(
    session: AsyncSession, merchant_id: uuid.UUID, customer_id: uuid.UUID
) -> list[Fact]:
    rows = await session.scalars(
        select(CustomerMemory)
        .where(
            CustomerMemory.merchant_id == merchant_id,
            CustomerMemory.customer_id == customer_id,
            or_(CustomerMemory.expires_at.is_(None), CustomerMemory.expires_at > func.now()),
        )
        .order_by(CustomerMemory.key)
    )
    return [Fact(row.key, row.value, row.updated_at) for row in rows]


async def forget(
    session: AsyncSession, merchant_id: uuid.UUID, customer_id: uuid.UUID, key: str
) -> bool:
    deleted = await session.execute(
        delete(CustomerMemory).where(
            CustomerMemory.merchant_id == merchant_id,
            CustomerMemory.customer_id == customer_id,
            CustomerMemory.key == key,
        )
    )
    return bool(deleted.rowcount)  # pyright: ignore[reportAttributeAccessIssue]


async def glossary(session: AsyncSession, merchant_id: uuid.UUID) -> list[tuple[str, str]]:
    rows = await session.execute(
        select(GlossaryTerm.term, GlossaryTerm.meaning)
        .where(or_(GlossaryTerm.merchant_id.is_(None), GlossaryTerm.merchant_id == merchant_id))
        .order_by(GlossaryTerm.merchant_id.is_(None), GlossaryTerm.term)
        .limit(40)
    )
    return [(term, meaning) for term, meaning in rows]


async def save_rule(
    session: AsyncSession,
    *,
    merchant_id: uuid.UUID,
    question: str,
    answer: str,
    source_escalation_id: uuid.UUID | None,
) -> None:
    session.add(
        MerchantRule(
            merchant_id=merchant_id,
            question=question,
            answer=answer,
            source_escalation_id=source_escalation_id,
        )
    )


async def rules(session: AsyncSession, merchant_id: uuid.UUID) -> list[tuple[str, str]]:
    rows = await session.execute(
        select(MerchantRule.question, MerchantRule.answer)
        .where(MerchantRule.merchant_id == merchant_id, MerchantRule.active)
        .order_by(MerchantRule.created_at.desc())
        .limit(20)
    )
    return [(question, answer) for question, answer in rows]


async def latest_summary(session: AsyncSession, conversation_id: uuid.UUID) -> str | None:
    return await session.scalar(
        select(ConversationSummary.summary)
        .where(ConversationSummary.conversation_id == conversation_id)
        .order_by(ConversationSummary.created_at.desc())
        .limit(1)
    )


async def summarise_long_conversations(limit: int = 20) -> int:
    """Summarise the older part of long conversations (a background job, never in a turn)."""
    async with session_scope() as session:
        candidates = await conversations.long_conversations(
            session, more_than=SUMMARY_AFTER_MESSAGES, limit=limit
        )
    written = 0
    for conversation_id, merchant_id in candidates:
        if await _summarise(conversation_id, merchant_id):
            written += 1
    return written


async def _summarise(conversation_id: uuid.UUID, merchant_id: uuid.UUID) -> bool:
    async with session_scope() as session:
        history = await conversations.chat_history(session, conversation_id, limit=500)
        older = history[:-RECENT_MESSAGES_KEPT]
        if not older:
            return False
        covered = await session.scalar(
            select(ConversationSummary.covers_until_message_id)
            .where(ConversationSummary.conversation_id == conversation_id)
            .order_by(ConversationSummary.created_at.desc())
            .limit(1)
        )
        if covered == older[-1].id:
            return False
    transcript = "\n".join(
        f"{line.sender}: {line.body}" for line in older if line.sender != "system" and line.body
    )
    try:
        completion = await llm.complete(
            [
                ChatMessage("system", prompt_store.render("memory.summarise")),
                ChatMessage("user", transcript[-12000:]),
            ]
        )
    except llm.LLMError:
        log.warning("agent.summary_unavailable", conversation_id=str(conversation_id))
        return False
    summary = completion.content.strip()
    if not summary or output.has_amount(summary):
        log.warning("agent.summary_rejected", conversation_id=str(conversation_id))
        return False  # amounts come from orders, never from a summary
    async with session_scope() as session:
        session.add(
            ConversationSummary(
                merchant_id=merchant_id,
                conversation_id=conversation_id,
                summary=summary[:1500],
                covers_until_message_id=older[-1].id,
                message_count=len(older),
            )
        )
    return True
