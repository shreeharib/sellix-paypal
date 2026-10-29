"""Instagram's 24-hour window: what waits, what's sent with the Human Agent tag, what expires,
and the late merchant answer of agent-phase-2.md section 10.2.
"""

import uuid
from datetime import UTC, datetime, timedelta

import pytest
from procrastinate.testing import InMemoryConnector
from sqlalchemy import func, select, update

from app.core.config import get_settings
from app.core.db import session_scope
from app.modules.agent import service as agent
from app.modules.agent.schemas import ChatMessage, CustomerReply
from app.modules.channels import service as channels
from app.modules.channels.models import ChannelConnection
from app.modules.channels.schemas import IncomingMessage
from app.modules.conversations import outbox, service
from app.modules.conversations.models import Conversation, Message, OutboundMessage
from app.modules.escalations import service as escalations
from app.modules.escalations.models import Escalation
from tests.integration.factories import CUSTOMER_ID, SHOP_ACCOUNT_ID, start_conversation

pytestmark = pytest.mark.anyio


class Instagram:
    def __init__(self) -> None:
        self.sent: list[tuple[str, str | None]] = []

    async def __call__(
        self,
        credentials: channels.SendCredentials,
        recipient_id: str,
        text: str,
        *,
        tag: str | None = None,
    ) -> str:
        self.sent.append((text, tag))
        return f"ig-{len(self.sent)}"


@pytest.fixture
def instagram(monkeypatch: pytest.MonkeyPatch) -> Instagram:
    fake = Instagram()
    monkeypatch.setattr(channels, "send_text", fake)
    monkeypatch.setattr(outbox, "PACING_SECONDS", 0)
    return fake


@pytest.fixture
def human_agent(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(get_settings(), "instagram_human_agent_enabled", True)


async def customer_last_wrote(conversation_id: uuid.UUID, ago: timedelta) -> None:
    async with session_scope() as session:
        await session.execute(
            update(Conversation)
            .where(Conversation.id == conversation_id)
            .values(last_customer_message_at=datetime.now(UTC) - ago)
        )


async def customer_writes(text: str, mid: str) -> service.TurnRequest | None:
    async with session_scope() as session:
        return await service.handle_incoming(
            session,
            IncomingMessage(
                channel="instagram",
                shop_account_id=SHOP_ACCOUNT_ID,
                customer_id=CUSTOMER_ID,
                message_id=mid,
                text=text,
            ),
        )


async def queue(conversation_id: uuid.UUID, text: str, key: str, **options: object) -> None:
    async with session_scope() as session:
        await outbox.queue_text(
            session,
            conversation_id=conversation_id,
            text=text,
            key=key,
            **options,  # pyright: ignore[reportArgumentType]
        )


async def outbox_statuses() -> list[str]:
    async with session_scope() as session:
        return list(
            await session.scalars(select(OutboundMessage.status).order_by(OutboundMessage.seq))
        )


async def open_question(conversation_id: uuid.UUID, merchant_id: uuid.UUID) -> uuid.UUID:
    async with session_scope() as session:
        question = await escalations.open_escalation(
            session,
            merchant_id=merchant_id,
            conversation_id=conversation_id,
            question="Can you make an eggless cake for Saturday?",
        )
    return question.id


async def answer(merchant_id: uuid.UUID, question_id: uuid.UUID, text: str) -> str:
    async with session_scope() as session:
        answered = await escalations.answer(session, merchant_id, question_id, text)
    return await service.relay_owner_answer(answered)


async def test_a_reply_outside_the_window_waits_and_goes_first_when_the_customer_writes(
    shop: ChannelConnection, instagram: Instagram
) -> None:
    turn = await start_conversation()
    await customer_last_wrote(turn.conversation_id, timedelta(hours=30))
    await queue(turn.conversation_id, "Your cake is ready!", "a")

    await outbox.deliver(turn.conversation_id)
    assert instagram.sent == []  # Instagram isn't even asked
    assert await outbox_statuses() == ["pending_window"]

    await customer_writes("hello?", "m-2")
    await queue(turn.conversation_id, "Hi again!", "b")
    await outbox.deliver(turn.conversation_id)

    assert instagram.sent == [("Your cake is ready!", None), ("Hi again!", None)]


async def test_a_persons_reply_after_24_hours_goes_with_the_human_agent_tag(
    shop: ChannelConnection, instagram: Instagram, human_agent: None
) -> None:
    turn = await start_conversation()
    await customer_last_wrote(turn.conversation_id, timedelta(hours=30))
    await queue(
        turn.conversation_id,
        "Yes, Saturday works.",
        "a",
        sender="merchant",
        window_policy="human_agent",
    )

    await outbox.deliver(turn.conversation_id)

    assert instagram.sent == [("Yes, Saturday works.", "HUMAN_AGENT")]


async def test_nothing_is_sent_after_7_days(shop: ChannelConnection, instagram: Instagram) -> None:
    turn = await start_conversation()
    await customer_last_wrote(turn.conversation_id, timedelta(days=8))
    await queue(turn.conversation_id, "Hello", "a")

    await outbox.deliver(turn.conversation_id)

    assert instagram.sent == []
    assert await outbox_statuses() == ["expired"]


async def test_waiting_messages_expire_once_7_days_pass(
    shop: ChannelConnection, instagram: Instagram
) -> None:
    turn = await start_conversation()
    await customer_last_wrote(turn.conversation_id, timedelta(hours=30))
    await queue(turn.conversation_id, "Hello", "a")
    await outbox.deliver(turn.conversation_id)
    await customer_last_wrote(turn.conversation_id, timedelta(days=8))

    await outbox.sweep()

    assert await outbox_statuses() == ["expired"]


async def test_a_late_answer_reaches_the_customer_when_they_write_again(
    shop: ChannelConnection, instagram: Instagram, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Scenario 10.2: the merchant answers 25 hours after the question."""
    turn = await start_conversation("eggless cake for Saturday?")
    question_id = await open_question(turn.conversation_id, shop.merchant_id)

    # 22.5 hours in: the merchant is warned, once.
    await customer_last_wrote(turn.conversation_id, timedelta(hours=22, minutes=30))
    assert await service.warn_closing_windows() == 1
    assert await service.warn_closing_windows() == 0

    # 25 hours in: the answer can't be sent, and no Human Agent tag is allowed.
    await customer_last_wrote(turn.conversation_id, timedelta(hours=25))
    assert await answer(shop.merchant_id, question_id, "Yes, eggless is fine.") == "pending_window"
    assert instagram.sent == []

    # The customer writes again: the turn sees the answer first, then the new message.
    histories: list[list[ChatMessage]] = []

    async def reply_to_customer(**kwargs: object) -> CustomerReply:
        histories.append(kwargs["history"])  # pyright: ignore[reportArgumentType]
        return CustomerReply(reply="Good news: eggless is fine!", language="en")

    monkeypatch.setattr(agent, "reply_to_customer", reply_to_customer)
    next_turn = await customer_writes("any update?", "m-2")
    assert next_turn is not None
    await service.run_turn(next_turn.conversation_id)

    assert [message.content for message in histories[0][-2:]] == [
        agent.system_note(
            agent.prompt(
                "v1.note.owner_answered",
                question="Can you make an eggless cake for Saturday?",
                answer="Yes, eggless is fine.",
            )
        ),
        "any update?",
    ]
    assert instagram.sent == [("Good news: eggless is fine!", None)]
    async with session_scope() as session:
        question = await session.get(Escalation, question_id)
    assert question is not None and question.answer_delivery == "sent"


async def test_a_late_answer_goes_as_written_with_the_human_agent_tag_when_allowed(
    shop: ChannelConnection, instagram: Instagram, human_agent: None
) -> None:
    turn = await start_conversation()
    question_id = await open_question(turn.conversation_id, shop.merchant_id)
    await customer_last_wrote(turn.conversation_id, timedelta(hours=30))

    delivery = await answer(shop.merchant_id, question_id, "Yes, eggless is fine.")

    assert delivery == "human_agent"
    assert instagram.sent == [("Yes, eggless is fine.", "HUMAN_AGENT")]
    async with session_scope() as session:
        sent = await session.scalar(select(Message).where(Message.direction == "outbound"))
    assert sent is not None and sent.sender == "merchant"


async def test_an_answer_inside_the_window_is_passed_on_by_the_agent(
    shop: ChannelConnection, instagram: Instagram, deferred_jobs: InMemoryConnector
) -> None:
    turn = await start_conversation()
    question_id = await open_question(turn.conversation_id, shop.merchant_id)

    assert await answer(shop.merchant_id, question_id, "Yes.") == "sent"

    async with session_scope() as session:
        notes = await session.scalar(
            select(func.count()).select_from(Message).where(Message.sender == "system")
        )
    assert notes == 1
    assert instagram.sent == []  # the agent's turn sends it, in the customer's language


async def test_an_answer_after_7_days_expires(
    shop: ChannelConnection, instagram: Instagram, human_agent: None
) -> None:
    turn = await start_conversation()
    question_id = await open_question(turn.conversation_id, shop.merchant_id)
    await customer_last_wrote(turn.conversation_id, timedelta(days=8))

    assert await answer(shop.merchant_id, question_id, "Yes.") == "expired"
    assert instagram.sent == []
