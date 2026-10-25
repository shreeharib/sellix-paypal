"""A customer turn that quotes and places an order, then the payment and expiry follow-ups.

The model and Instagram are replaced (no model costs, no real DMs); orders, stock, database
and jobs are real. With no PayPal credentials configured, the real "no online payment" path
runs; the PayPal path itself is covered against the sandbox in test_paypal_sandbox.py.
"""

import uuid
from datetime import UTC, date, datetime

import pytest
from procrastinate.testing import InMemoryConnector
from sqlalchemy import select

from app.core.db import session_scope
from app.modules.agent import service as agent
from app.modules.agent.schemas import ChatMessage, CustomerReply
from app.modules.channels import service as channels
from app.modules.channels.models import ChannelConnection
from app.modules.conversations import service
from app.modules.conversations.models import Conversation, Message
from app.modules.conversations.tasks import after_payment
from app.modules.escalations.models import Escalation
from app.modules.inventory import service as inventory
from app.modules.inventory.schemas import OpeningStockLine
from app.modules.merchants import service as merchants
from app.modules.orders import service as orders
from app.modules.orders.models import Order
from app.modules.orders.schemas import OrderLineRequest, OrderRequest, PlacedOrder
from app.modules.orders.tasks import expire_unpaid_orders
from tests.integration.factories import CUSTOMER_ID, start_conversation

pytestmark = pytest.mark.anyio

ORDER = {
    "items": [{"product": "Scoop cookie", "variant": "Chocolate", "quantity": 2}],
    "fulfilment": "pickup",
    "needed_by": "today evening",
}


class ScriptedAgent:
    """Answers each step from a script and records what it was shown."""

    def __init__(self, *steps: dict[str, object]) -> None:
        self.steps = [CustomerReply.model_validate({"language": "ta-en", **s}) for s in steps]
        self.histories: list[list[ChatMessage]] = []

    async def __call__(
        self, *, merchant_id: uuid.UUID, conversation_id: uuid.UUID, history: list[ChatMessage]
    ) -> CustomerReply:
        self.histories.append(history)
        return self.steps.pop(0)


class RecordingChannel:
    def __init__(self) -> None:
        self.sent: list[str] = []

    async def __call__(
        self, credentials: channels.SendCredentials, recipient_id: str, text: str
    ) -> str:
        assert recipient_id == CUSTOMER_ID
        self.sent.append(text)
        return f"out-{len(self.sent)}"


@pytest.fixture
async def stocked(shop: ChannelConnection) -> ChannelConnection:
    async with session_scope() as session:
        merchant = await merchants.get_merchant(session, shop.merchant_id)
        await inventory.set_opening_stock(
            session,
            merchant_id=shop.merchant_id,
            business_date=merchants.business_date(merchant),
            lines=[OpeningStockLine("Scoop cookie", "Chocolate", 6000, 10)],
        )
    return shop


async def test_quote_then_place_holds_stock_and_hands_payment_to_the_shop(
    stocked: ChannelConnection, monkeypatch: pytest.MonkeyPatch
) -> None:
    channel = RecordingChannel()
    monkeypatch.setattr(channels, "send_text", channel)
    quoting = ScriptedAgent(
        {"action": {"type": "quote_order", "order": ORDER}},
        {"reply": "2 chocolate cookie, ₹120. Confirm pannalama?"},
    )
    monkeypatch.setattr(agent, "reply_to_customer", quoting)
    turn = await start_conversation("rendu chocolate cookie, evening pickup")

    await service.run_turn(turn.conversation_id)

    quote_note = quoting.histories[1][-1].content
    assert quote_note.startswith("[Shop system] Quote: 2 x Scoop cookie (Chocolate) at ₹60 = ₹120")
    assert channel.sent == ["2 chocolate cookie, ₹120. Confirm pannalama?"]

    placing = ScriptedAgent(
        {"action": {"type": "place_order", "order": ORDER}},
        {"reply": "Order confirm aachu! Payment details shop share pannuvanga."},
    )
    monkeypatch.setattr(agent, "reply_to_customer", placing)
    await start_conversation("yes confirm", message_id="m-2")

    await service.run_turn(turn.conversation_id)

    async with session_scope() as session:
        order = await session.scalar(select(Order))
        escalation = await session.scalar(select(Escalation))
        reply = await session.scalar(select(Message).where(Message.body.like("Order confirm%")))
    assert order is not None
    async with session_scope() as session:
        stock = await inventory.today_stock(session, stocked.merchant_id, order.business_date)
    assert (order.status, order.total_minor, order.needed_by) == (
        "awaiting_payment",
        12000,
        "today evening",
    )
    assert stock[0].available == 8  # two held
    assert "Online payment isn't available" in placing.histories[1][-1].content
    assert escalation is not None and f"Order #{order.number}" in escalation.question
    assert reply is not None and reply.details["order_id"] == str(order.id)


async def place_for(shop: ChannelConnection, *, hold_minutes: int = 15) -> PlacedOrder:
    """A real order for 2 chocolate cookies from a new conversation."""
    turn = await start_conversation()
    async with session_scope() as session:
        merchant = await merchants.get_merchant(session, shop.merchant_id)
        conversation = await session.get(Conversation, turn.conversation_id)
        assert conversation is not None
        return await orders.place_order(
            session,
            merchant_id=merchant.id,
            customer_id=conversation.customer_id,
            conversation_id=conversation.id,
            business_date=merchants.business_date(merchant),
            request=OrderRequest(lines=(OrderLineRequest("Scoop cookie", "Chocolate", 2),)),
            hold_minutes=hold_minutes,
        )


async def test_payment_confirmation_reaches_the_customer_through_the_agent(
    stocked: ChannelConnection, deferred_jobs: InMemoryConnector
) -> None:
    placed = await place_for(stocked)
    async with session_scope() as session:
        result = await orders.record_payment(
            session, placed.order_id, amount_minor=12000, currency="INR", actor="paypal"
        )

    await after_payment(result)

    async with session_scope() as session:
        note = await session.scalar(select(Message).where(Message.sender == "system"))
    assert note is not None
    assert note.body.startswith(f"Payment of ₹120 received for order #{placed.number}")
    assert [job["task_name"] for job in deferred_jobs.jobs.values()] == ["run_agent_turn"]


async def test_expired_order_is_released_and_the_customer_is_told(
    stocked: ChannelConnection, deferred_jobs: InMemoryConnector
) -> None:
    placed = await place_for(stocked, hold_minutes=-1)  # already past its hold

    await expire_unpaid_orders(timestamp=int(datetime.now(UTC).timestamp()))

    async with session_scope() as session:
        order = await session.get(Order, placed.order_id)
        note = await session.scalar(select(Message).where(Message.sender == "system"))
        stock = await inventory.today_stock(session, stocked.merchant_id, placed_date(order))
    assert order is not None and order.status == "expired"
    assert stock[0].available == 10  # released
    assert note is not None and f"Order #{placed.number} wasn't paid in time" in note.body
    assert [job["task_name"] for job in deferred_jobs.jobs.values()] == ["run_agent_turn"]


def placed_date(order: Order | None) -> date:
    assert order is not None
    return order.business_date
