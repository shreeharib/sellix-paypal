"""Inbound protection (agent-phase-2.md section 12): huge messages, bursts, turn limits and the
shop's AI budget can't run up model calls or cost.
"""

import uuid
from datetime import UTC, datetime, timedelta
from decimal import Decimal

import pytest
from sqlalchemy import func, select

from app.core.db import session_scope
from app.modules.agent import service as agent
from app.modules.agent.models import AgentTurn
from app.modules.channels.models import ChannelConnection
from app.modules.conversations import service as conversations
from app.modules.conversations.models import Conversation, Message
from app.modules.escalations.models import Escalation
from tests.integration.factories import CUSTOMER_ID, SHOP_ACCOUNT_ID, Instagram, ScriptedModel

pytestmark = pytest.mark.anyio


async def receive(text: str, mid: str) -> conversations.TurnRequest | None:
    from app.modules.channels.schemas import IncomingMessage

    async with session_scope() as session:
        return await conversations.handle_incoming(
            session,
            IncomingMessage(
                channel="instagram",
                shop_account_id=SHOP_ACCOUNT_ID,
                customer_id=CUSTOMER_ID,
                message_id=mid,
                text=text,
            ),
        )


async def conversation_id() -> uuid.UUID:
    async with session_scope() as session:
        found = await session.scalar(select(Conversation.id))
    assert found is not None
    return found


def user_texts(model: ScriptedModel) -> list[str]:
    return [m.content for m in model.calls[-1][0] if m.role == "user"]


async def test_a_10000_character_message_costs_no_model_call(
    v2_shop: ChannelConnection, model: ScriptedModel, instagram: Instagram
) -> None:
    await receive("cake " * 2000, "m-1")

    await agent.run_turn(await conversation_id())

    assert model.calls == []
    assert instagram.texts() == [agent.fixed_text("too_long", "en")]
    async with session_scope() as session:
        stored = await session.scalar(select(Message.body).where(Message.sender == "customer"))
        turn = await session.scalar(select(AgentTurn))
    assert stored is not None and len(stored) == 10000  # the merchant still sees all of it
    assert turn is not None and turn.status == "gated"


async def test_a_long_message_reaches_the_model_shortened_and_cleaned(
    v2_shop: ChannelConnection, model: ScriptedModel, instagram: Instagram
) -> None:
    model.then([("send_reply", {"text": "Seri!", "language": "en"})])
    await receive("hel​lo\u0007 " + "x" * 2500, "m-1")

    await agent.run_turn(await conversation_id())

    [text] = user_texts(model)
    assert text.startswith("hello ")
    assert len(text) <= 1000 + len(agent.prompt("inbound.shortened"))
    assert text.endswith(agent.prompt("inbound.shortened"))


async def test_a_100_message_burst_costs_one_model_call(
    v2_shop: ChannelConnection, model: ScriptedModel, instagram: Instagram
) -> None:
    turns = [await receive(f"message {n} " + "y" * 150, f"m-{n}") for n in range(100)]
    model.then([("send_reply", {"text": "Seri!", "language": "en"})])

    await agent.run_turn(await conversation_id())

    assert sum(turn is not None for turn in turns) == 20  # the rest wait for the burst to end
    assert len(model.calls) == 1
    batch = user_texts(model)
    assert batch[-1].startswith("message 99")  # the latest is answered
    assert sum(len(text) for text in batch) <= 2000 + 100  # the oldest were cut


async def test_too_many_turns_in_an_hour_get_one_polite_message_then_silence(
    v2_shop: ChannelConnection, model: ScriptedModel, instagram: Instagram
) -> None:
    await receive("hi", "m-0")
    conversation = await conversation_id()
    async with session_scope() as session:
        trigger = await session.scalar(select(Message.id))
        assert trigger is not None
        for n in range(30):
            message = Message(
                merchant_id=v2_shop.merchant_id,
                conversation_id=conversation,
                direction="inbound",
                sender="customer",
                body=f"old {n}",
                details={},
                status="received",
                created_at=datetime.now(UTC) - timedelta(minutes=50),
            )
            session.add(message)
            await session.flush()
            session.add(
                AgentTurn(
                    merchant_id=v2_shop.merchant_id,
                    conversation_id=conversation,
                    trigger_message_id=message.id,
                    status="replied",
                    started_at=datetime.now(UTC) - timedelta(minutes=50),
                )
            )

    await receive("hello?", "m-1")
    await agent.run_turn(conversation)
    await receive("hello??", "m-2")
    await agent.run_turn(conversation)

    assert model.calls == []
    assert instagram.texts() == [agent.fixed_text("rate_limited", "en")]
    async with session_scope() as session:
        flagged = await session.scalar(
            select(func.count())
            .select_from(Escalation)
            .where(Escalation.question.contains("Unusual activity"))
        )
    assert flagged == 1


async def test_a_shop_over_its_ai_budget_gets_holding_messages_and_the_owner_is_asked(
    v2_shop: ChannelConnection, model: ScriptedModel, instagram: Instagram
) -> None:
    await receive("hi", "m-0")
    conversation = await conversation_id()
    async with session_scope() as session:
        trigger = await session.scalar(select(Message.id))
        assert trigger is not None
        session.add(
            AgentTurn(
                merchant_id=v2_shop.merchant_id,
                conversation_id=conversation,
                trigger_message_id=trigger,
                status="replied",
                cost_usd=Decimal("5.00"),
            )
        )
    await receive("cookie irukka?", "m-1")

    await agent.run_turn(conversation)

    assert model.calls == []
    assert instagram.texts() == [agent.fixed_text("holding", "en")]
