"""The outbox: every outbound message is queued, sent once, in order, and retried when it can be.

Instagram is replaced with scripted answers; the database and the queue are real.
"""

import uuid
from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import func, select, update

from app.core.db import session_scope
from app.modules.channels import service as channels
from app.modules.channels.models import ChannelConnection
from app.modules.channels.schemas import IncomingMessage
from app.modules.conversations import outbox, service
from app.modules.conversations.models import Conversation, Message, OutboundMessage
from app.modules.escalations.models import Escalation
from tests.integration.factories import CUSTOMER_ID, SHOP_ACCOUNT_ID, start_conversation

pytestmark = pytest.mark.anyio

SERVER_ERROR = channels.SendFailed("Instagram API error 500: oops", reason="retryable")
WINDOW_CLOSED = channels.SendFailed("outside the allowed window", reason="window_closed")


class ScriptedInstagram:
    """Answers each send with the next scripted error, then succeeds."""

    def __init__(self, *errors: channels.SendFailed) -> None:
        self.errors = list(errors)
        self.attempts: list[str] = []
        self.sent: list[str] = []

    async def __call__(
        self, credentials: channels.SendCredentials, recipient_id: str, text: str
    ) -> str:
        assert recipient_id == CUSTOMER_ID
        self.attempts.append(text)
        if self.errors:
            raise self.errors.pop(0)
        self.sent.append(text)
        return f"ig-{len(self.sent)}"


@pytest.fixture
def instagram(monkeypatch: pytest.MonkeyPatch) -> ScriptedInstagram:
    scripted = ScriptedInstagram()
    monkeypatch.setattr(channels, "send_text", scripted)
    monkeypatch.setattr(outbox, "PACING_SECONDS", 0)
    return scripted


async def queue(conversation_id: uuid.UUID, text: str, key: str) -> uuid.UUID:
    async with session_scope() as session:
        return await outbox.queue_text(session, conversation_id=conversation_id, text=text, key=key)


async def make_retries_due() -> None:
    async with session_scope() as session:
        await session.execute(update(OutboundMessage).values(next_attempt_at=func.now()))


async def statuses() -> list[tuple[str, int]]:
    async with session_scope() as session:
        rows = await session.execute(
            select(OutboundMessage.status, OutboundMessage.attempts).order_by(OutboundMessage.seq)
        )
        return [(status, attempts) for status, attempts in rows]


async def escalation_count() -> int:
    async with session_scope() as session:
        return await session.scalar(select(func.count()).select_from(Escalation)) or 0


async def test_two_server_errors_then_success_delivers_exactly_one_message(
    shop: ChannelConnection, instagram: ScriptedInstagram
) -> None:
    instagram.errors = [SERVER_ERROR, SERVER_ERROR]
    turn = await start_conversation()
    message_id = await queue(turn.conversation_id, "Vanakkam! Order ready.", "turn:1:reply")

    first_retry = await outbox.deliver(turn.conversation_id)
    assert first_retry is not None and first_retry > datetime.now(UTC)
    assert await outbox.deliver(turn.conversation_id) == first_retry  # not due yet: no attempt
    await make_retries_due()
    await outbox.deliver(turn.conversation_id)
    await make_retries_due()
    assert await outbox.deliver(turn.conversation_id) is None

    assert instagram.sent == ["Vanakkam! Order ready."]
    assert len(instagram.attempts) == 3
    assert await statuses() == [("sent", 3)]
    async with session_scope() as session:
        message = await session.get(Message, message_id)
    assert message is not None
    assert (message.status, message.external_id) == ("sent", "ig-1")
    assert await escalation_count() == 0


async def test_queuing_the_same_key_twice_sends_once(
    shop: ChannelConnection, instagram: ScriptedInstagram
) -> None:
    turn = await start_conversation()
    first = await queue(turn.conversation_id, "Your order is confirmed.", "order:7:link")
    second = await queue(turn.conversation_id, "Your order is confirmed.", "order:7:link")

    await outbox.deliver(turn.conversation_id)
    await outbox.deliver(turn.conversation_id)

    assert first == second
    assert instagram.sent == ["Your order is confirmed."]


async def test_messages_to_one_customer_go_out_in_order(
    shop: ChannelConnection, instagram: ScriptedInstagram
) -> None:
    instagram.errors = [SERVER_ERROR]
    turn = await start_conversation()
    await queue(turn.conversation_id, "First", "a")
    await queue(turn.conversation_id, "Second", "b")

    await outbox.deliver(turn.conversation_id)
    assert instagram.sent == []  # "Second" waits behind the retrying "First"

    await make_retries_due()
    await outbox.deliver(turn.conversation_id)

    assert instagram.sent == ["First", "Second"]


async def test_a_closed_window_is_not_retried_and_waits_for_the_customer(
    shop: ChannelConnection, instagram: ScriptedInstagram
) -> None:
    instagram.errors = [WINDOW_CLOSED]
    turn = await start_conversation()
    await queue(turn.conversation_id, "The shop says yes!", "a")
    await queue(turn.conversation_id, "Anything else?", "b")

    assert await outbox.deliver(turn.conversation_id) is None
    await make_retries_due()
    await outbox.deliver(turn.conversation_id)

    assert len(instagram.attempts) == 1
    assert await statuses() == [("pending_window", 1), ("pending_window", 0)]
    assert await escalation_count() == 1


async def test_a_message_that_keeps_failing_is_given_up_and_the_merchant_told(
    shop: ChannelConnection, instagram: ScriptedInstagram
) -> None:
    instagram.errors = [SERVER_ERROR] * outbox.MAX_ATTEMPTS
    turn = await start_conversation()
    message_id = await queue(turn.conversation_id, "Hello", "a")

    for _ in range(outbox.MAX_ATTEMPTS):
        await make_retries_due()
        await outbox.deliver(turn.conversation_id)

    assert len(instagram.attempts) == outbox.MAX_ATTEMPTS
    assert await statuses() == [("failed", outbox.MAX_ATTEMPTS)]
    async with session_scope() as session:
        message = await session.get(Message, message_id)
    assert message is not None and message.status == "failed"
    assert await escalation_count() == 1


async def test_a_permanent_error_fails_at_once(
    shop: ChannelConnection, instagram: ScriptedInstagram
) -> None:
    instagram.errors = [channels.SendFailed("token expired")]
    turn = await start_conversation()
    await queue(turn.conversation_id, "Hello", "a")

    assert await outbox.deliver(turn.conversation_id) is None

    assert await statuses() == [("failed", 1)]
    assert await escalation_count() == 1


async def test_a_long_tamil_reply_is_split_into_two_messages_within_instagrams_byte_limit(
    shop: ChannelConnection, instagram: ScriptedInstagram
) -> None:
    sentence = "உங்கள் ஆர்டர் தயாராக உள்ளது, மாலை ஆறு மணிக்கு வந்து எடுத்துக்கொள்ளுங்கள். "
    text = (sentence * 8).strip()
    assert len(text.encode()) > channels.MAX_TEXT_BYTES
    turn = await start_conversation()
    await queue(turn.conversation_id, text, "a")

    await outbox.deliver(turn.conversation_id)

    assert len(instagram.sent) == 2
    assert all(len(part.encode()) <= channels.MAX_TEXT_BYTES for part in instagram.sent)
    assert " ".join(instagram.sent) == text


async def test_a_send_stuck_after_a_crash_is_sent_again_by_the_sweep(
    shop: ChannelConnection, instagram: ScriptedInstagram
) -> None:
    turn = await start_conversation()
    await queue(turn.conversation_id, "Hello", "a")
    async with session_scope() as session:
        await session.execute(
            update(OutboundMessage).values(
                status="sending", updated_at=datetime.now(UTC) - timedelta(minutes=5)
            )
        )

    assert await outbox.sweep() == [turn.conversation_id]
    await outbox.deliver(turn.conversation_id)

    assert instagram.sent == ["Hello"]


async def test_a_stuck_send_that_instagram_echoed_is_not_sent_twice(
    shop: ChannelConnection, instagram: ScriptedInstagram
) -> None:
    turn = await start_conversation()
    await queue(turn.conversation_id, "Hello", "a")
    async with session_scope() as session:
        await session.execute(update(OutboundMessage).values(status="sending"))
        await service.handle_incoming(session, echo("ig-echo-1", "Hello"))
        await session.execute(
            update(OutboundMessage).values(updated_at=datetime.now(UTC) - timedelta(minutes=5))
        )

    await outbox.sweep()
    await outbox.deliver(turn.conversation_id)

    assert instagram.sent == []
    assert await statuses() == [("sent", 0)]


async def test_the_echo_of_one_part_of_a_split_reply_does_not_pause_the_agent(
    shop: ChannelConnection, instagram: ScriptedInstagram
) -> None:
    sentence = "உங்கள் ஆர்டர் தயாராக உள்ளது, மாலை ஆறு மணிக்கு வந்து எடுத்துக்கொள்ளுங்கள். "
    turn = await start_conversation()
    await queue(turn.conversation_id, (sentence * 8).strip(), "a")
    await outbox.deliver(turn.conversation_id)

    async with session_scope() as session:
        for number, part in enumerate(instagram.sent, start=1):
            await service.handle_incoming(session, echo(f"ig-{number}", part))

    async with session_scope() as session:
        conversation = await session.get(Conversation, turn.conversation_id)
        merchant_messages = await session.scalar(
            select(func.count()).select_from(Message).where(Message.sender == "merchant")
        )
    assert conversation is not None and conversation.agent_active
    assert merchant_messages == 0


def echo(mid: str, text: str) -> IncomingMessage:
    return IncomingMessage(
        channel="instagram",
        shop_account_id=SHOP_ACCOUNT_ID,
        customer_id=CUSTOMER_ID,
        message_id=mid,
        text=text,
        is_echo=True,
    )
