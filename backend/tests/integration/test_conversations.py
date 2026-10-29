import uuid

import pytest
from procrastinate.testing import InMemoryConnector
from sqlalchemy import select, update

from app.core.db import session_scope
from app.modules.channels.models import ChannelConnection
from app.modules.channels.schemas import IncomingMessage
from app.modules.conversations import outbox, service
from app.modules.conversations.models import Conversation, Message, OutboundMessage
from app.modules.merchants.models import Merchant
from app.webhooks.models import WebhookEvent
from app.webhooks.tasks import process_meta_event
from tests.integration.factories import CUSTOMER_ID, SHOP_ACCOUNT_ID

pytestmark = pytest.mark.anyio


def customer_message(mid: str = "m-1", text: str = "rendu cookie venum") -> IncomingMessage:
    return IncomingMessage(
        channel="instagram",
        shop_account_id=SHOP_ACCOUNT_ID,
        customer_id=CUSTOMER_ID,
        message_id=mid,
        text=text,
    )


def echo(mid: str, text: str) -> IncomingMessage:
    return IncomingMessage(
        channel="instagram",
        shop_account_id=SHOP_ACCOUNT_ID,
        customer_id=CUSTOMER_ID,
        message_id=mid,
        text=text,
        is_echo=True,
    )


async def test_customer_message_is_stored_and_asks_for_a_turn(shop: ChannelConnection) -> None:
    async with session_scope() as session:
        turn = await service.handle_incoming(session, customer_message())

    assert turn is not None
    async with session_scope() as session:
        conversation = await session.get(Conversation, turn.conversation_id)
        stored = await session.scalar(select(Message))
    assert conversation is not None and conversation.merchant_id == shop.merchant_id
    assert stored is not None
    assert (stored.sender, stored.direction, stored.body) == (
        "customer",
        "inbound",
        "rendu cookie venum",
    )


async def test_duplicate_message_is_ignored(shop: ChannelConnection) -> None:
    async with session_scope() as session:
        first = await service.handle_incoming(session, customer_message())
    async with session_scope() as session:
        second = await service.handle_incoming(session, customer_message())

    assert first is not None
    assert second is None


async def test_message_for_an_unknown_account_is_ignored(db: None) -> None:
    async with session_scope() as session:
        assert await service.handle_incoming(session, customer_message()) is None


async def test_no_turn_when_the_agent_is_switched_off(shop: ChannelConnection) -> None:
    async with session_scope() as session:
        merchant = await session.get(Merchant, shop.merchant_id)
        assert merchant is not None
        merchant.agent_enabled = False

    async with session_scope() as session:
        assert await service.handle_incoming(session, customer_message()) is None


async def test_echo_of_our_own_reply_is_matched_not_treated_as_the_merchant(
    shop: ChannelConnection,
) -> None:
    async with session_scope() as session:
        turn = await service.handle_incoming(session, customer_message())
        assert turn is not None
        await outbox.queue_text(
            session, conversation_id=turn.conversation_id, text="Chocolate or red velvet?", key="r"
        )
        await session.execute(update(OutboundMessage).values(status="sending"))

    # The echo arrives before Instagram's send API has answered us.
    async with session_scope() as session:
        await service.handle_incoming(session, echo("m-2", "Chocolate or red velvet?"))

    async with session_scope() as session:
        reply = await session.scalar(select(Message).where(Message.sender == "agent"))
        conversation = await session.get(Conversation, turn.conversation_id)
    assert reply is not None and reply.external_id == "m-2"
    assert conversation is not None and conversation.agent_active


async def test_merchant_typing_in_instagram_pauses_the_agent_for_that_chat(
    shop: ChannelConnection,
) -> None:
    async with session_scope() as session:
        turn = await service.handle_incoming(session, customer_message())
    assert turn is not None

    async with session_scope() as session:
        await service.handle_incoming(session, echo("m-3", "I'll handle this one, thanks!"))

    async with session_scope() as session:
        conversation = await session.get(Conversation, turn.conversation_id)
        merchant_message = await session.scalar(select(Message).where(Message.sender == "merchant"))
        next_turn = await service.handle_incoming(session, customer_message("m-4", "ok"))
    assert conversation is not None
    assert (conversation.agent_active, conversation.agent_paused_reason) == (
        False,
        "merchant_replied",
    )
    assert merchant_message is not None and merchant_message.body == "I'll handle this one, thanks!"
    assert next_turn is None


async def test_webhook_event_job_stores_messages_then_queues_one_turn(
    shop: ChannelConnection, deferred_jobs: InMemoryConnector
) -> None:
    payload = {
        "object": "instagram",
        "entry": [
            {
                "id": SHOP_ACCOUNT_ID,
                "messaging": [
                    {
                        "sender": {"id": CUSTOMER_ID},
                        "recipient": {"id": SHOP_ACCOUNT_ID},
                        "message": {"mid": mid, "text": text},
                    }
                    for mid, text in [("m-10", "hi"), ("m-11", "2 brownies"), ("m-12", "today")]
                ],
            }
        ],
    }
    async with session_scope() as session:
        event = WebhookEvent(source="meta", dedupe_key=uuid.uuid4().hex, payload=payload)
        session.add(event)
        await session.flush()
        event_id = event.id

    await process_meta_event(event_id=str(event_id))

    async with session_scope() as session:
        stored_event = await session.get(WebhookEvent, event_id)
        bodies = list(await session.scalars(select(Message.body).order_by(Message.created_at)))
    assert stored_event is not None and stored_event.status == "processed"
    assert bodies == ["hi", "2 brownies", "today"]
    [job] = deferred_jobs.jobs.values()  # three messages, one queued turn
    assert job["task_name"] == "run_agent_turn"
