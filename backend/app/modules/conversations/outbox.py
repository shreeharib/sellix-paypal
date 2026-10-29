"""The outbox: every outbound message is queued here before it's sent (agent-phase-2.md 13.2).

- `queue_text` writes the chat message and its outbox rows in the caller's transaction. The
  same idempotency key queued twice does nothing, so a retried job never sends twice.
- `deliver` sends one conversation's due rows in queue order, at least PACING_SECONDS apart.
  A row waiting for a retry holds back the rows behind it: a customer never gets messages
  out of order.
- Retryable failures (network, 5xx, rate limits) are retried with backoff; permanent ones stop
  at once and tell the merchant. A closed 24-hour window parks the conversation's rows as
  `pending_window`.
- `sweep` finds conversations with rows due, and recovers rows stuck in `sending` after a
  crash: sent if Instagram echoed them back, otherwise queued again.
"""

import asyncio
import time
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any, Literal

import structlog
from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import session_scope
from app.modules.channels import service as channels
from app.modules.conversations.models import Conversation, Customer, Message, OutboundMessage
from app.modules.escalations import service as escalations

log = structlog.get_logger()

MAX_ATTEMPTS = 7  # the first try and 6 retries
RETRY_DELAYS = tuple(
    timedelta(seconds=seconds) for seconds in (10, 30, 60, 120, 180, 240)
)  # about 10 minutes in all
PACING_SECONDS = 1.0  # between two messages to the same customer
STUCK_AFTER = timedelta(minutes=2)
MAX_PARTS = 2
ECHO_MATCH_WINDOW = timedelta(minutes=5)

SEND_FAILED_QUESTION = (
    "I couldn't send my reply to this customer. Please reply to them directly in Instagram."
)
WINDOW_CLOSED_QUESTION = (
    "My reply couldn't reach this customer: Instagram only lets the shop reply within 24 hours "
    "of their last message. Please reply to them from the Instagram app."
)

WindowPolicy = Literal["standard", "human_agent", "when_open"]


async def queue_text(
    session: AsyncSession,
    *,
    conversation_id: uuid.UUID,
    text: str,
    key: str,
    details: dict[str, Any] | None = None,
    window_policy: WindowPolicy = "standard",
) -> uuid.UUID:
    """Record an agent message and queue it for sending. Returns the chat message's id."""
    existing = await session.scalar(
        select(OutboundMessage.message_id).where(OutboundMessage.idempotency_key == key).limit(1)
    )
    if existing is not None:
        return existing
    conversation = await session.get(Conversation, conversation_id)
    if conversation is None:
        raise LookupError(f"No conversation {conversation_id}")
    message = Message(
        merchant_id=conversation.merchant_id,
        conversation_id=conversation.id,
        direction="outbound",
        sender="agent",
        body=text,
        details=details or {},
        status="sending",
    )
    session.add(message)
    await session.flush()
    for number, part in enumerate(split_text(text), start=1):
        session.add(
            OutboundMessage(
                merchant_id=conversation.merchant_id,
                conversation_id=conversation.id,
                message_id=message.id,
                idempotency_key=key,
                part=number,
                payload={"text": part},
                window_policy=window_policy,
            )
        )
    await session.flush()
    return message.id


async def deliver(conversation_id: uuid.UUID) -> datetime | None:
    """Send the conversation's due messages in order. Returns when the next retry is due."""
    last_send: float | None = None
    while True:
        claim = await _claim_next(conversation_id)
        if not isinstance(claim, _Claim):
            return claim
        if last_send is not None:
            await asyncio.sleep(max(0.0, PACING_SECONDS - (time.monotonic() - last_send)))
        try:
            async with session_scope() as session:
                credentials = await channels.get_send_credentials(session, claim.connection_id)
            provider_message_id = await channels.send_text(
                credentials, claim.recipient_id, claim.text
            )
        except channels.SendFailed as exc:
            retry_at = await _record_failure(claim.row_id, exc)
            if retry_at is not None:
                return retry_at
            continue
        last_send = time.monotonic()
        async with session_scope() as session:
            row = await session.get(OutboundMessage, claim.row_id, with_for_update=True)
            if row is not None:
                await _mark_sent(session, row, provider_message_id or None)


async def sweep() -> list[uuid.UUID]:
    """Conversations with messages due now. Recovers sends stuck after a crash first."""
    now = datetime.now(UTC)
    async with session_scope() as session:
        stuck = await session.scalars(
            select(OutboundMessage)
            .where(
                OutboundMessage.status == "sending",
                OutboundMessage.updated_at < now - STUCK_AFTER,
            )
            .with_for_update(skip_locked=True)
        )
        for row in stuck:
            if row.provider_message_id:
                await _mark_sent(session, row, row.provider_message_id)  # Instagram echoed it
            else:
                # It may or may not have reached Instagram; sending again risks a duplicate,
                # not sending risks silence. A customer without a reply is the worse outcome.
                row.status = "queued"
                row.next_attempt_at = now
                row.updated_at = now
                log.warning("outbox.recovered_stuck_send", outbound_id=str(row.id))
        await session.flush()
        due = await session.scalars(
            select(OutboundMessage.conversation_id)
            .where(OutboundMessage.status == "queued", OutboundMessage.next_attempt_at <= now)
            .distinct()
        )
        return list(due)


async def match_echo(
    session: AsyncSession, conversation: Conversation, provider_message_id: str, text: str
) -> bool:
    """Is this echo one of our own sends? Records Instagram's id for it if so."""
    if provider_message_id:
        known = await session.scalar(
            select(OutboundMessage.id).where(
                OutboundMessage.merchant_id == conversation.merchant_id,
                OutboundMessage.provider_message_id == provider_message_id,
            )
        )
        if known is not None:
            return True
    # The echo can arrive before Instagram's send API has answered us.
    row = await session.scalar(
        select(OutboundMessage)
        .where(
            OutboundMessage.conversation_id == conversation.id,
            OutboundMessage.status.in_(("sending", "sent")),
            OutboundMessage.provider_message_id.is_(None),
            OutboundMessage.payload["text"].astext == text,
            OutboundMessage.created_at > datetime.now(UTC) - ECHO_MATCH_WINDOW,
        )
        .order_by(OutboundMessage.seq)
        .limit(1)
        .with_for_update()
    )
    if row is None:
        return False
    row.provider_message_id = provider_message_id or None
    if row.part == 1 and provider_message_id:
        await session.execute(
            update(Message)
            .where(Message.id == row.message_id)
            .values(external_id=func.coalesce(Message.external_id, provider_message_id))
        )
    return True


def split_text(text: str) -> list[str]:
    """Up to MAX_PARTS messages within Instagram's byte limit, split at a sentence if possible."""
    limit = channels.MAX_TEXT_BYTES
    parts: list[str] = []
    rest = text.strip()
    while len(parts) < MAX_PARTS - 1 and len(rest.encode()) > limit:
        cut = _cut_point(rest, limit)
        parts.append(rest[:cut].rstrip())
        rest = rest[cut:].lstrip()
    if rest:
        parts.append(_shorten_to_bytes(rest, limit))
    return parts


@dataclass(frozen=True)
class _Claim:
    row_id: uuid.UUID
    text: str
    connection_id: uuid.UUID
    recipient_id: str


async def _claim_next(conversation_id: uuid.UUID) -> _Claim | datetime | None:
    """Take the conversation's next row for sending, or say when it's due (None: nothing)."""
    now = datetime.now(UTC)
    async with session_scope() as session:
        row = await session.scalar(
            select(OutboundMessage)
            .where(
                OutboundMessage.conversation_id == conversation_id,
                OutboundMessage.status.in_(("queued", "sending")),
            )
            .order_by(OutboundMessage.seq)
            .limit(1)
            .with_for_update()
        )
        if row is None or row.status == "sending":
            return None  # nothing to send, or another worker is sending it (the sweep watches)
        if row.next_attempt_at > now:
            return row.next_attempt_at
        conversation = await session.get(Conversation, conversation_id)
        customer = await session.get(Customer, conversation.customer_id) if conversation else None
        if conversation is None or customer is None:
            return None
        row.status = "sending"
        row.attempts += 1
        row.updated_at = now
        return _Claim(
            row.id,
            str(row.payload["text"]),
            conversation.channel_connection_id,
            customer.external_id,
        )


async def _mark_sent(
    session: AsyncSession, row: OutboundMessage, provider_message_id: str | None
) -> None:
    now = datetime.now(UTC)
    row.status = "sent"
    row.provider_message_id = provider_message_id or row.provider_message_id
    row.sent_at = now
    row.updated_at = now
    await session.flush()
    unsent = await session.scalar(
        select(func.count())
        .select_from(OutboundMessage)
        .where(OutboundMessage.message_id == row.message_id, OutboundMessage.status != "sent")
    )
    values: dict[str, Any] = {}
    if row.part == 1 and row.provider_message_id:
        values["external_id"] = func.coalesce(Message.external_id, row.provider_message_id)
    if not unsent:
        values["status"] = "sent"
    if values:
        await session.execute(update(Message).where(Message.id == row.message_id).values(values))


async def _record_failure(row_id: uuid.UUID, exc: channels.SendFailed) -> datetime | None:
    """Schedule a retry (returns when), or give up and tell the merchant (returns None)."""
    now = datetime.now(UTC)
    async with session_scope() as session:
        row = await session.get(OutboundMessage, row_id, with_for_update=True)
        if row is None:
            return None
        row.last_error = str(exc)[:500]
        row.updated_at = now
        if exc.retryable and row.attempts < MAX_ATTEMPTS:
            row.status = "queued"
            row.next_attempt_at = now + RETRY_DELAYS[min(row.attempts, len(RETRY_DELAYS)) - 1]
            log.warning("outbox.send_retry", outbound_id=str(row.id), attempts=row.attempts)
            return row.next_attempt_at

        if exc.reason == "window_closed":
            # Nothing else will get through either until the customer writes again.
            row.status = "pending_window"
            await session.execute(
                update(OutboundMessage)
                .where(
                    OutboundMessage.conversation_id == row.conversation_id,
                    OutboundMessage.status == "queued",
                )
                .values(status="pending_window", updated_at=now)
            )
            question = WINDOW_CLOSED_QUESTION
        else:
            # The rest of this message can't go out without this part.
            row.status = "failed"
            await session.execute(
                update(OutboundMessage)
                .where(
                    OutboundMessage.message_id == row.message_id,
                    OutboundMessage.status == "queued",
                )
                .values(status="failed", updated_at=now)
            )
            await session.execute(
                update(Message)
                .where(Message.id == row.message_id)
                .values(status="failed", error=str(exc)[:500])
            )
            question = SEND_FAILED_QUESTION
        await escalations.open_escalation(
            session,
            merchant_id=row.merchant_id,
            conversation_id=row.conversation_id,
            question=question,
        )
        log.error(
            "outbox.send_failed",
            outbound_id=str(row.id),
            conversation_id=str(row.conversation_id),
            reason=exc.reason,
            error=str(exc),
        )
        return None


def _cut_point(text: str, limit: int) -> int:
    """Where to end the first part: after the last sentence that fits, else the last space."""
    fits = text.encode()[:limit].decode("utf-8", errors="ignore")
    for end in range(len(fits) - 1, 0, -1):
        if fits[end - 1] in ".!?।" and fits[end].isspace():
            return end
    space = fits.rfind(" ")
    return space if space > 0 else len(fits)


def _shorten_to_bytes(text: str, limit: int) -> str:
    if len(text.encode()) <= limit:
        return text
    ellipsis = "…"
    room = limit - len(ellipsis.encode())
    return text.encode()[:room].decode("utf-8", errors="ignore").rstrip() + ellipsis
