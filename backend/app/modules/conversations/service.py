"""Public interface of the conversations module: customers, chats, messages and agent turns."""

import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any

import structlog
from sqlalchemy import func, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.db import session_scope
from app.modules.agent import service as agent
from app.modules.agent.schemas import ChatMessage, CustomerReply
from app.modules.channels import service as channels
from app.modules.channels.schemas import IncomingMessage
from app.modules.conversations import actions, outbox
from app.modules.conversations.models import Conversation, Customer, Message
from app.modules.conversations.schemas import ConversationSummary, MessageView
from app.modules.escalations import service as escalations
from app.modules.merchants import service as merchants
from app.modules.orders.schemas import ExpiredOrder, PaymentResult
from app.modules.payments.service import PaymentFailed

log = structlog.get_logger()

# One turn: up to two actions (quote, then place the order) and the reply itself.
MAX_AGENT_STEPS = 3
# The agent answers when the latest message is from the customer or a system note.
REPLY_SENDERS = ("customer", "system")
AGENT_UNAVAILABLE_QUESTION = (
    "The assistant couldn't answer this customer just now. Please reply to them in Instagram."
)


@dataclass(frozen=True)
class TurnRequest:
    """The conversation has something new the agent should answer."""

    conversation_id: uuid.UUID


async def handle_incoming(session: AsyncSession, message: IncomingMessage) -> TurnRequest | None:
    """Store a message from a channel webhook. Returns a turn request if the agent should reply."""
    connection = await channels.get_active_connection(
        session, message.channel, message.shop_account_id
    )
    if connection is None:
        log.warning(
            "conversations.unknown_account",
            channel=message.channel,
            account_id=message.shop_account_id,
        )
        return None

    customer_id = await _upsert_customer(
        session, connection.merchant_id, message.channel, message.customer_id
    )
    conversation = await _get_or_create_conversation(
        session, connection.merchant_id, customer_id, connection.id
    )

    if message.is_echo:
        await _record_echo(session, conversation, message)
        return None

    inserted = await session.scalar(
        pg_insert(Message)
        .values(
            merchant_id=conversation.merchant_id,
            conversation_id=conversation.id,
            direction="inbound",
            sender="customer",
            external_id=message.message_id or None,
            body=message.text,
            details=_inbound_details(message),
            status="received",
        )
        .on_conflict_do_nothing(
            index_elements=[Message.merchant_id, Message.external_id],
            index_where=Message.external_id.is_not(None),
        )
        .returning(Message.id)
    )
    if inserted is None:
        return None  # a webhook retry we've already stored
    conversation.last_customer_message_at = datetime.now(UTC)
    return await _turn_if_agent_active(session, conversation)


async def add_system_note(
    session: AsyncSession, conversation_id: uuid.UUID, note: str
) -> TurnRequest | None:
    """Add a note from the shop's system (e.g. "payment received") for the agent to pass on."""
    conversation = await session.get(Conversation, conversation_id)
    if conversation is None:
        return None
    session.add(
        Message(
            merchant_id=conversation.merchant_id,
            conversation_id=conversation.id,
            direction="internal",
            sender="system",
            body=note,
            details={},
            status="received",
        )
    )
    await session.flush()
    return await _turn_if_agent_active(session, conversation)


async def run_turn(conversation_id: uuid.UUID) -> None:
    """Answer the latest customer messages (or system note), if they still need an answer."""
    loaded = await _load_turn(conversation_id)
    if loaded is None:
        return
    context, history = loaded

    reply: CustomerReply | None = None
    outcomes: list[actions.ActionOutcome] = []
    for _ in range(MAX_AGENT_STEPS):
        try:
            reply = await agent.reply_to_customer(
                merchant_id=context.merchant_id,
                conversation_id=context.conversation_id,
                history=history,
            )
        except agent.AgentUnavailable:
            reply = None
            break
        if reply.action is None:
            break
        outcome = await actions.perform(context, reply.action)
        outcomes.append(outcome)
        history = [*history, ChatMessage("user", agent.system_note(outcome.note))]

    payment_link = next((o.payment_link for o in reversed(outcomes) if o.payment_link), None)
    order_id = next((o.order_id for o in reversed(outcomes) if o.order_id), None)
    details: dict[str, Any] = {"order_id": str(order_id)} if order_id else {}

    if reply is None or reply.action is not None:
        # The model failed or never finished. If an order was placed, still send its essentials.
        await _escalate(context, AGENT_UNAVAILABLE_QUESTION)
        fallback = next((o.fallback_text for o in reversed(outcomes) if o.fallback_text), None)
        if fallback is not None:
            await _send(context, fallback, key="fallback", details=details, owner_question=None)
        return

    await _send(
        context,
        _with_payment_link(reply.reply, payment_link),
        key="reply",
        details={**details, "language": reply.language},
        owner_question=reply.owner_question if reply.needs_owner else None,
    )


async def unanswered_conversations(
    session: AsyncSession, *, waiting_longer_than: timedelta, max_age: timedelta
) -> list[uuid.UUID]:
    """Conversations whose latest message still needs the agent's answer."""
    now = datetime.now(UTC)
    latest = (
        select(
            Message.conversation_id,
            Message.sender,
            Message.created_at,
            func.row_number()
            .over(partition_by=Message.conversation_id, order_by=Message.created_at.desc())
            .label("position"),
        )
        .where(Message.created_at > now - max_age)
        .subquery()
    )
    enabled_merchant_ids = await merchants.list_enabled_merchant_ids(session)
    if not enabled_merchant_ids:
        return []
    rows = await session.scalars(
        select(Conversation.id)
        .join(latest, latest.c.conversation_id == Conversation.id)
        .where(
            latest.c.position == 1,
            latest.c.sender.in_(REPLY_SENDERS),
            latest.c.created_at < now - waiting_longer_than,
            Conversation.agent_active,
            Conversation.merchant_id.in_(enabled_merchant_ids),
        )
    )
    return list(rows)


async def set_agent_active(session: AsyncSession, conversation_id: uuid.UUID, active: bool) -> None:
    """Switch the agent on or off for one chat (the merchant's per-chat switch)."""
    conversation = await session.get(Conversation, conversation_id)
    if conversation is None:
        raise LookupError(f"No conversation {conversation_id}")
    conversation.agent_active = active
    conversation.agent_paused_reason = None if active else "merchant_switched_off"


async def _load_turn(
    conversation_id: uuid.UUID,
) -> tuple[actions.TurnContext, list[ChatMessage]] | None:
    async with session_scope() as session:
        conversation = await session.get(Conversation, conversation_id)
        if conversation is None:
            return None
        merchant = await merchants.find_merchant(session, conversation.merchant_id)
        if merchant is None or not merchant.agent_enabled or not conversation.agent_active:
            return None
        recent = await _recent_messages(session, conversation_id, get_settings().history_messages)
        if not recent or recent[-1].sender not in REPLY_SENDERS:
            return None  # already answered, or the merchant replied last
        customer = await session.get(Customer, conversation.customer_id)
        if customer is None:
            return None
        context = actions.TurnContext(
            conversation_id=conversation.id,
            merchant_id=merchant.id,
            shop_name=merchant.name,
            customer_id=customer.id,
            customer_external_id=customer.external_id,
            channel_connection_id=conversation.channel_connection_id,
            business_date=merchants.business_date(merchant),
            trigger_message_id=recent[-1].id,
        )
        return context, [_as_chat_message(message) for message in recent]


async def _send(
    context: actions.TurnContext,
    text: str,
    *,
    key: str,
    details: dict[str, Any],
    owner_question: str | None,
) -> None:
    """Queue the turn's message in the outbox, then deliver it."""
    async with session_scope() as session:
        await outbox.queue_text(
            session,
            conversation_id=context.conversation_id,
            text=text,
            # One reply per customer message: a repeated turn can't send it twice.
            key=f"turn:{context.trigger_message_id}:{key}",
            details=details,
        )
        if owner_question:
            await escalations.open_escalation(
                session,
                merchant_id=context.merchant_id,
                conversation_id=context.conversation_id,
                question=owner_question,
                trigger_message_id=context.trigger_message_id,
            )
    await deliver_outbox(context.conversation_id)
    log.info("conversations.replied", conversation_id=str(context.conversation_id))


async def deliver_outbox(conversation_id: uuid.UUID) -> None:
    """Send what's queued for this chat now; schedule the next retry if one is needed."""
    retry_at = await outbox.deliver(conversation_id)
    if retry_at is not None:
        from app.modules.conversations import tasks

        await tasks.schedule_delivery(conversation_id, retry_at)


async def _escalate(context: actions.TurnContext, question: str) -> None:
    async with session_scope() as session:
        await escalations.open_escalation(
            session,
            merchant_id=context.merchant_id,
            conversation_id=context.conversation_id,
            question=question,
            trigger_message_id=context.trigger_message_id,
        )


async def _turn_if_agent_active(
    session: AsyncSession, conversation: Conversation
) -> TurnRequest | None:
    merchant = await merchants.find_merchant(session, conversation.merchant_id)
    if merchant is None or not merchant.agent_enabled or not conversation.agent_active:
        return None
    return TurnRequest(conversation.id)


async def _upsert_customer(
    session: AsyncSession, merchant_id: uuid.UUID, channel: str, external_id: str
) -> uuid.UUID:
    statement = pg_insert(Customer).values(
        merchant_id=merchant_id, channel=channel, external_id=external_id
    )
    customer_id = await session.scalar(
        statement.on_conflict_do_update(
            index_elements=[Customer.merchant_id, Customer.channel, Customer.external_id],
            set_={"external_id": statement.excluded.external_id},
        ).returning(Customer.id)
    )
    if customer_id is None:
        raise RuntimeError("Customer upsert returned no row")
    return customer_id


async def _get_or_create_conversation(
    session: AsyncSession,
    merchant_id: uuid.UUID,
    customer_id: uuid.UUID,
    connection_id: uuid.UUID,
) -> Conversation:
    await session.execute(
        pg_insert(Conversation)
        .values(
            merchant_id=merchant_id, customer_id=customer_id, channel_connection_id=connection_id
        )
        .on_conflict_do_nothing(index_elements=[Conversation.customer_id])
    )
    conversation = await session.scalar(
        select(Conversation).where(Conversation.customer_id == customer_id).with_for_update()
    )
    if conversation is None:
        raise RuntimeError("Conversation upsert returned no row")
    return conversation


async def _record_echo(
    session: AsyncSession, conversation: Conversation, message: IncomingMessage
) -> None:
    """Echoes are copies of the shop's own messages: our replies, or the merchant typing."""
    if message.message_id:
        known = await session.scalar(
            select(Message.id).where(
                Message.merchant_id == conversation.merchant_id,
                Message.external_id == message.message_id,
            )
        )
        if known is not None:
            return

    if await outbox.match_echo(session, conversation, message.message_id, message.text):
        return

    # The merchant replied from the Instagram app: record it and step back from this chat.
    await session.execute(
        pg_insert(Message)
        .values(
            merchant_id=conversation.merchant_id,
            conversation_id=conversation.id,
            direction="outbound",
            sender="merchant",
            external_id=message.message_id or None,
            body=message.text,
            details=_inbound_details(message),
            status="sent",
        )
        .on_conflict_do_nothing(
            index_elements=[Message.merchant_id, Message.external_id],
            index_where=Message.external_id.is_not(None),
        )
    )
    if conversation.agent_active:
        conversation.agent_active = False
        conversation.agent_paused_reason = "merchant_replied"
        log.info("conversations.agent_paused", conversation_id=str(conversation.id))


async def _recent_messages(
    session: AsyncSession, conversation_id: uuid.UUID, limit: int
) -> list[Message]:
    rows = await session.scalars(
        select(Message)
        .where(Message.conversation_id == conversation_id, Message.status != "failed")
        .order_by(Message.created_at.desc())
        .limit(limit)
    )
    return list(reversed(list(rows)))


def _with_payment_link(text: str, link: str | None) -> str:
    """Put the real payment link where the agent left the placeholder (or at the end)."""
    placeholder = agent.PAYMENT_LINK_PLACEHOLDER
    if link is None:
        return text.replace(placeholder, "").strip()
    room = channels.MAX_TEXT_LENGTH - len(link) - 1
    if placeholder not in text:
        text = f"{_shorten(text, room)}\n{placeholder}"
    elif len(text) - len(placeholder) > room:
        text = _shorten(text.replace(placeholder, "").strip(), room) + f"\n{placeholder}"
    return text.replace(placeholder, link)


def _shorten(text: str, limit: int) -> str:
    return text if len(text) <= limit else text[: limit - 1].rstrip() + "…"


def _inbound_details(message: IncomingMessage) -> dict[str, Any]:
    details: dict[str, Any] = {}
    if message.attachment_types:
        details["attachments"] = list(message.attachment_types)
    if message.story_reply_url:
        details["story_reply_url"] = message.story_reply_url
    return details


def _as_chat_message(message: Message) -> ChatMessage:
    if message.sender == "customer":
        notes = []
        if message.details.get("story_reply_url"):
            notes.append("[The customer replied to one of the shop's stories]")
        if message.details.get("attachments"):
            notes.append(f"[The customer sent: {', '.join(message.details['attachments'])}]")
        return ChatMessage("user", " ".join([*notes, message.body]).strip())
    if message.sender == "system":
        return ChatMessage("user", agent.system_note(message.body))
    if message.sender == "merchant":
        return ChatMessage("assistant", f"(Shop owner) {message.body}")
    return ChatMessage("assistant", message.body)


async def list_conversations(
    session: AsyncSession, merchant_id: uuid.UUID, *, limit: int = 100
) -> list[ConversationSummary]:
    """The merchant's chats, most recent activity first."""
    latest = (
        select(
            Message.conversation_id,
            Message.sender,
            Message.body,
            Message.created_at,
            func.row_number()
            .over(partition_by=Message.conversation_id, order_by=Message.created_at.desc())
            .label("position"),
        )
        .where(Message.merchant_id == merchant_id, Message.direction != "internal")
        .subquery()
    )
    rows = await session.execute(
        select(Conversation, Customer, latest.c.sender, latest.c.body, latest.c.created_at)
        .join(Customer, Customer.id == Conversation.customer_id)
        .outerjoin(latest, (latest.c.conversation_id == Conversation.id) & (latest.c.position == 1))
        .where(Conversation.merchant_id == merchant_id)
        .order_by(func.coalesce(latest.c.created_at, Conversation.created_at).desc())
        .limit(limit)
    )
    return [
        ConversationSummary(
            id=conversation.id,
            channel=customer.channel,
            customer_id=customer.id,
            customer_handle=customer.display_name or customer.external_id,
            agent_active=conversation.agent_active,
            agent_paused_reason=conversation.agent_paused_reason,
            last_message_sender=sender,
            last_message_body=body,
            last_message_at=created_at,
        )
        for conversation, customer, sender, body, created_at in rows
    ]


async def list_messages(
    session: AsyncSession, merchant_id: uuid.UUID, conversation_id: uuid.UUID, *, limit: int = 100
) -> list[MessageView]:
    """A chat's messages, oldest first (system notes stay internal)."""
    rows = await session.scalars(
        select(Message)
        .where(
            Message.merchant_id == merchant_id,
            Message.conversation_id == conversation_id,
            Message.direction != "internal",
        )
        .order_by(Message.created_at.desc())
        .limit(limit)
    )
    return [
        MessageView(
            id=message.id,
            direction=message.direction,
            sender=message.sender,
            body=message.body,
            status=message.status,
            created_at=message.created_at,
        )
        for message in reversed(list(rows))
    ]


async def get_conversation(
    session: AsyncSession, merchant_id: uuid.UUID, conversation_id: uuid.UUID
) -> Conversation:
    conversation = await session.get(Conversation, conversation_id)
    if conversation is None or conversation.merchant_id != merchant_id:
        raise LookupError(f"No conversation {conversation_id}")
    return conversation


async def get_customer_display_name(session: AsyncSession, customer_id: uuid.UUID) -> str | None:
    """Return the customer's display name if known."""
    customer = await session.get(Customer, customer_id)
    return customer.display_name if customer else None


async def request_turn(turn: TurnRequest) -> None:
    """Queue an agent reply turn for a conversation."""
    from app.modules.conversations import tasks

    await tasks.request_turn(turn)


async def inform_customer(conversation_id: uuid.UUID | None, note: str) -> None:
    """Have the agent tell the customer something, in their language, in their chat."""
    from app.modules.conversations import tasks

    await tasks.inform_customer(conversation_id, note)


async def after_payment(result: PaymentResult | PaymentFailed) -> None:
    """Tell the customer (and, if needed, the merchant) what a payment event means."""
    from app.modules.conversations import tasks

    await tasks.after_payment(result)


async def after_expiry(order: ExpiredOrder) -> None:
    """Notify the customer in chat when their unpaid order hold expires."""
    from app.modules.conversations import tasks

    await tasks.after_expiry(order)
