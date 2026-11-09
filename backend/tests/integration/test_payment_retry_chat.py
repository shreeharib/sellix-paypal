"""Payment trouble in the chat: the 'New payment link' button, the cooldown, and the fixed messages
that go out when the model is down.

The model is scripted; the database, orders, payments, the simulator and the outbox are real.
"""

import json
import uuid
from typing import Any

import pytest
from procrastinate.testing import InMemoryConnector
from sqlalchemy import select

from app.core.config import get_settings
from app.core.db import session_scope
from app.modules.agent import llm
from app.modules.agent import service as agent
from app.modules.channels.models import ChannelConnection
from app.modules.channels.schemas import IncomingMessage
from app.modules.conversations import service as conversations
from app.modules.conversations import tasks as conversation_tasks
from app.modules.conversations.models import Message, OutboundMessage
from app.modules.merchants import service as merchants
from app.modules.orders.models import Order, QuoteRecord
from app.modules.payments import service as payments
from app.modules.payments import simulator
from app.modules.payments.models import Payment
from app.modules.shop_profile import service as shop_profile
from app.modules.shop_profile.schemas import OnboardingAnswers
from tests.integration.factories import CUSTOMER_ID, SHOP_ACCOUNT_ID, Instagram, ScriptedModel
from tests.integration.test_agent_v2_memory_and_tools import cookie

pytestmark = pytest.mark.anyio


@pytest.fixture
def simulator_on(monkeypatch: pytest.MonkeyPatch) -> None:
    settings = get_settings()
    monkeypatch.setattr(settings, "payment_provider", "simulator")
    monkeypatch.setattr(settings, "payment_retry_cooldown_seconds", 0)
    monkeypatch.setattr(settings, "payment_max_attempts", 3)


async def customer_says(text: str, mid: str, quick_reply: str | None = None) -> uuid.UUID:
    async with session_scope() as session:
        turn = await conversations.handle_incoming(
            session,
            IncomingMessage(
                channel="instagram",
                shop_account_id=SHOP_ACCOUNT_ID,
                customer_id=CUSTOMER_ID,
                message_id=mid,
                text=text,
                quick_reply_payload=quick_reply,
            ),
        )
    assert turn is not None
    await agent.run_turn(turn.conversation_id)
    return turn.conversation_id


async def unpaid_order(shop: ChannelConnection, model: ScriptedModel) -> Order:
    """An order confirmed by tap, with its simulator payment link sent (the shop has no UPI id)."""
    async with session_scope() as session:
        merchant = await merchants.get_merchant(session, shop.merchant_id)
        await shop_profile.save_onboarding(
            session, shop.merchant_id, shop_name=merchant.name, answers=OnboardingAnswers()
        )
    item = await cookie(shop)
    model.then(
        [
            (
                "update_order_draft",
                {"items": [{"item_id": item, "quantity": 2}], "fulfilment": "pickup"},
            )
        ],
        [("create_quote", {})],
        [("send_reply", {"text": "Confirm?", "language": "en"})],
    )
    await customer_says("2 cookies pickup", "m-1")
    async with session_scope() as session:
        quote = await session.scalar(select(QuoteRecord))
    assert quote is not None
    model.then([("send_reply", {"text": "Thanks!", "language": "en"})])
    await customer_says("Confirm", "m-2", quick_reply=f"CONFIRM:{quote.id}")
    async with session_scope() as session:
        order = await session.scalar(select(Order))
    assert order is not None
    return order


async def simulator_payments(order_id: uuid.UUID) -> list[Payment]:
    async with session_scope() as session:
        return list(
            await session.scalars(
                select(Payment).where(Payment.order_id == order_id).order_by(Payment.created_at)
            )
        )


async def the_customer_declines(order: Order) -> None:
    """The simulator's Reject button, as the webhook job applies it."""
    [payment] = [p for p in await simulator_payments(order.id) if p.status == "created"]
    body = simulator.event_body(
        "rejected",
        payment_id=payment.id,
        amount_minor=payment.amount_minor,
        currency=payment.currency,
    )
    result = await payments.handle_simulator_event(json.loads(body))
    assert isinstance(result, payments.PaymentFailed)
    await conversations.after_payment(result)


async def messages_of_kind(kind: str) -> list[Message]:
    async with session_scope() as session:
        return list(
            await session.scalars(
                select(Message)
                .where(Message.details["kind"].as_string() == kind)
                .order_by(Message.created_at)
            )
        )


async def test_the_new_payment_link_button_sends_a_fresh_link_without_the_model(
    v2_shop: ChannelConnection,
    model: ScriptedModel,
    instagram: Instagram,
    simulator_on: None,
) -> None:
    order = await unpaid_order(v2_shop, model)
    [first] = await simulator_payments(order.id)
    assert first.provider == "simulator" and first.status == "created"

    await the_customer_declines(order)
    [declined] = await messages_of_kind("payment_declined")
    assert "2 more tries" in declined.body
    async with session_scope() as session:
        sent = await session.scalar(
            select(OutboundMessage.payload).where(OutboundMessage.message_id == declined.id)
        )
    assert sent is not None and sent["quick_replies"][0][1] == f"RETRY:{order.id}"

    model.then([("send_reply", {"text": "Here is your new link.", "language": "en"})])
    first_call = len(model.calls)
    await customer_says("New payment link", "m-3", quick_reply=f"RETRY:{order.id}")

    first_try, second_try = await simulator_payments(order.id)
    assert first_try.status == "denied" and second_try.status == "created"
    assert second_try.approve_url is not None and second_try.approve_url != first_try.approve_url
    tool_messages: list[Any] = [m for m in model.calls[first_call][0] if m.role == "tool"]
    assert [m.name for m in tool_messages] == ["resend_payment_link"]  # code ran it, not the model
    assert any(second_try.approve_url in text for text in instagram.texts())


async def test_tapping_the_button_too_soon_says_how_long_to_wait(
    v2_shop: ChannelConnection,
    model: ScriptedModel,
    instagram: Instagram,
    simulator_on: None,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(get_settings(), "payment_retry_cooldown_seconds", 60)
    order = await unpaid_order(v2_shop, model)
    await the_customer_declines(order)

    model.then([("send_reply", {"text": "One moment.", "language": "en"})])
    await customer_says("New payment link", "m-3", quick_reply=f"RETRY:{order.id}")

    assert len(await simulator_payments(order.id)) == 1  # no second link yet
    [wait] = await messages_of_kind("payment_retry_wait")
    assert "seconds" in wait.body


async def test_a_paid_order_is_confirmed_by_a_fixed_message_when_the_model_is_down(
    v2_shop: ChannelConnection,
    model: ScriptedModel,
    instagram: Instagram,
    deferred_jobs: InMemoryConnector,
    simulator_on: None,
) -> None:
    order = await unpaid_order(v2_shop, model)
    [payment] = await simulator_payments(order.id)
    body = simulator.event_body(
        "accepted",
        payment_id=payment.id,
        amount_minor=payment.amount_minor,
        currency=payment.currency,
    )
    result = await payments.handle_simulator_event(json.loads(body))
    assert result is not None
    await conversations.after_payment(result)

    model.then(*[llm.LLMError("model down")] * 4)  # every attempt fails
    assert order.conversation_id is not None
    await agent.run_turn(order.conversation_id)  # the turn the payment-received note asked for

    [confirmation] = await messages_of_kind("event_payment_received")
    assert f"#{order.number}" in confirmation.body
    assert await messages_of_kind("holding") == []  # not "thanks for your message, I'll check"


async def test_an_expired_order_is_explained_by_a_fixed_message_when_the_model_is_down(
    v2_shop: ChannelConnection,
    model: ScriptedModel,
    instagram: Instagram,
    deferred_jobs: InMemoryConnector,
    simulator_on: None,
) -> None:
    order = await unpaid_order(v2_shop, model)
    assert order.conversation_id is not None
    await conversation_tasks.inform_customer(
        order.conversation_id,
        "Order was not paid in time, so the items were released.",
        event={"event": "hold_expired", "order": f"#{order.number}"},
    )
    model.then(*[llm.LLMError("model down")] * 4)
    await agent.run_turn(order.conversation_id)

    [expired] = await messages_of_kind("event_hold_expired")
    assert f"#{order.number}" in expired.body
    assert await messages_of_kind("holding") == []
