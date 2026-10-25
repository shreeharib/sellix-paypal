import uuid
from datetime import timedelta

import pytest
from sqlalchemy import select

from app.core.db import session_scope
from app.modules.agent import service as agent
from app.modules.agent.schemas import ChatMessage, CustomerReply
from app.modules.channels import service as channels
from app.modules.channels.models import ChannelConnection
from app.modules.conversations import service
from app.modules.conversations.models import Message
from app.modules.escalations.models import Escalation
from tests.integration.factories import CUSTOMER_ID, start_conversation

pytestmark = pytest.mark.anyio


class FakeAgent:
    def __init__(self, reply: CustomerReply | Exception) -> None:
        self.reply = reply
        self.histories: list[list[ChatMessage]] = []

    async def __call__(
        self, *, merchant_id: uuid.UUID, conversation_id: uuid.UUID, history: list[ChatMessage]
    ) -> CustomerReply:
        self.histories.append(history)
        if isinstance(self.reply, Exception):
            raise self.reply
        return self.reply


class FakeChannel:
    def __init__(self, error: Exception | None = None) -> None:
        self.error = error
        self.sent: list[tuple[str, str]] = []

    async def __call__(
        self, credentials: channels.SendCredentials, recipient_id: str, text: str
    ) -> str:
        if self.error:
            raise self.error
        self.sent.append((recipient_id, text))
        return f"out-{len(self.sent)}"


def reply(text: str = "Sure! Pickup-aa delivery-aa?", **overrides: object) -> CustomerReply:
    return CustomerReply.model_validate(
        {"reply": text, "language": "ta-en", "needs_owner": False, **overrides}
    )


async def test_turn_replies_in_the_chat_and_records_the_message(
    shop: ChannelConnection, monkeypatch: pytest.MonkeyPatch
) -> None:
    fake_agent, fake_channel = FakeAgent(reply()), FakeChannel()
    monkeypatch.setattr(agent, "reply_to_customer", fake_agent)
    monkeypatch.setattr(channels, "send_text", fake_channel)
    turn = await start_conversation()

    await service.run_turn(turn.conversation_id)

    assert fake_channel.sent == [(CUSTOMER_ID, "Sure! Pickup-aa delivery-aa?")]
    assert fake_agent.histories[0][-1] == ChatMessage("user", "rendu chocolate cookie venum")
    async with session_scope() as session:
        sent = await session.scalar(select(Message).where(Message.sender == "agent"))
    assert sent is not None
    assert (sent.status, sent.external_id, sent.details) == ("sent", "out-1", {"language": "ta-en"})


async def test_turn_does_nothing_when_the_customer_was_already_answered(
    shop: ChannelConnection, monkeypatch: pytest.MonkeyPatch
) -> None:
    fake_channel = FakeChannel()
    monkeypatch.setattr(agent, "reply_to_customer", FakeAgent(reply()))
    monkeypatch.setattr(channels, "send_text", fake_channel)
    turn = await start_conversation()

    await service.run_turn(turn.conversation_id)
    await service.run_turn(turn.conversation_id)  # a duplicate turn

    assert len(fake_channel.sent) == 1


async def test_owner_question_opens_an_escalation(
    shop: ChannelConnection, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(
        agent,
        "reply_to_customer",
        FakeAgent(
            reply(
                "Let me check with the shop and get back to you!",
                needs_owner=True,
                owner_question="Customer wants a custom birthday cake for Saturday.",
            )
        ),
    )
    monkeypatch.setattr(channels, "send_text", FakeChannel())
    turn = await start_conversation("can you make a birthday cake for saturday?")

    await service.run_turn(turn.conversation_id)

    async with session_scope() as session:
        escalation = await session.scalar(select(Escalation))
    assert escalation is not None
    assert escalation.question == "Customer wants a custom birthday cake for Saturday."
    assert escalation.status == "open"


async def test_failed_send_is_recorded_and_escalated(
    shop: ChannelConnection, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(agent, "reply_to_customer", FakeAgent(reply()))
    monkeypatch.setattr(channels, "send_text", FakeChannel(channels.SendFailed("token expired")))
    turn = await start_conversation()

    await service.run_turn(turn.conversation_id)

    async with session_scope() as session:
        failed = await session.scalar(select(Message).where(Message.sender == "agent"))
        escalation = await session.scalar(select(Escalation))
    assert failed is not None and (failed.status, failed.error) == ("failed", "token expired")
    assert escalation is not None and escalation.question == service.SEND_FAILED_QUESTION


async def test_model_outage_escalates_without_messaging_the_customer(
    shop: ChannelConnection, monkeypatch: pytest.MonkeyPatch
) -> None:
    fake_channel = FakeChannel()
    monkeypatch.setattr(agent, "reply_to_customer", FakeAgent(agent.AgentUnavailable("down")))
    monkeypatch.setattr(channels, "send_text", fake_channel)
    turn = await start_conversation()

    await service.run_turn(turn.conversation_id)

    async with session_scope() as session:
        escalation = await session.scalar(select(Escalation))
    assert fake_channel.sent == []
    assert escalation is not None and escalation.question == service.AGENT_UNAVAILABLE_QUESTION


async def test_unanswered_chats_are_found_for_reconciliation(shop: ChannelConnection) -> None:
    turn = await start_conversation()

    async with session_scope() as session:
        waiting = await service.unanswered_conversations(
            session, waiting_longer_than=timedelta(0), max_age=timedelta(hours=1)
        )

    assert waiting == [turn.conversation_id]
