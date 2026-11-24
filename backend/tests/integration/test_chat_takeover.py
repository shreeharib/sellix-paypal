"""The owner takes over a chat: a reply (typed in Instagram, or sent from the app) pauses the
assistant for AGENT_RESUME_AFTER_MERCHANT_HOURS; it answers again from the customer's next
message after that. "I'll reply myself" stays off. Plus paging of the chat list."""

import uuid
from collections.abc import AsyncIterator
from datetime import UTC, datetime, timedelta

import httpx2
import pytest
from procrastinate.testing import InMemoryConnector
from sqlalchemy import func, select, update

from app.core.db import session_scope
from app.main import create_app
from app.modules.channels.models import ChannelConnection
from app.modules.channels.schemas import IncomingMessage
from app.modules.conversations import service as conversations
from app.modules.conversations.models import Conversation, Message, OutboundMessage
from tests.integration.factories import CUSTOMER_ID, SHOP_ACCOUNT_ID, Instagram
from tests.integration.test_api import bearer, sign_in_as

pytestmark = pytest.mark.anyio


@pytest.fixture
async def api(db: None) -> AsyncIterator[httpx2.AsyncClient]:
    transport = httpx2.ASGITransport(app=create_app())
    async with httpx2.AsyncClient(transport=transport, base_url="http://test") as client:
        yield client


def incoming(
    mid: str, text: str, *, echo: bool = False, customer: str = CUSTOMER_ID
) -> IncomingMessage:
    return IncomingMessage(
        channel="instagram",
        shop_account_id=SHOP_ACCOUNT_ID,
        customer_id=customer,
        message_id=mid,
        text=text,
        is_echo=echo,
    )


async def receive(message: IncomingMessage) -> conversations.TurnRequest | None:
    async with session_scope() as session:
        return await conversations.handle_incoming(session, message)


async def chat(conversation_id: uuid.UUID) -> Conversation:
    async with session_scope() as session:
        found = await session.get(Conversation, conversation_id)
    assert found is not None
    return found


async def pause_ended() -> None:
    async with session_scope() as session:
        await session.execute(
            update(Conversation).values(agent_paused_until=func.now() - timedelta(minutes=1))
        )


async def test_a_reply_typed_in_instagram_pauses_the_chat_for_twelve_hours(
    api: httpx2.AsyncClient, shop: ChannelConnection
) -> None:
    turn = await receive(incoming("m-1", "rendu cookie venum"))
    assert turn is not None

    await receive(incoming("m-2", "I'll take this one", echo=True))
    paused = await chat(turn.conversation_id)
    listed = await api.get("/v1/chats", headers=bearer(await sign_in_as(shop.merchant_id)))
    still_paused = await receive(incoming("m-3", "ok thanks"))

    assert (paused.agent_active, paused.agent_paused_reason) == (False, "merchant_replied")
    assert paused.agent_paused_until is not None
    hours = (paused.agent_paused_until - datetime.now(UTC)).total_seconds() / 3600
    assert 11.9 < hours <= 12
    row = listed.json()[0]
    assert row["agent_active"] is False and row["agent_paused_reason"] == "merchant_replied"
    assert datetime.fromisoformat(row["agent_paused_until"]) == paused.agent_paused_until
    assert still_paused is None  # inside the 12 hours the owner is answering


async def test_the_assistant_answers_again_after_the_pause(shop: ChannelConnection) -> None:
    await receive(incoming("m-1", "rendu cookie venum"))
    await receive(incoming("m-2", "Sure, coming up", echo=True))
    await pause_ended()

    turn = await receive(incoming("m-3", "and one brownie?"))

    assert turn is not None
    resumed = await chat(turn.conversation_id)
    assert (resumed.agent_active, resumed.agent_paused_reason) == (True, None)
    assert resumed.agent_paused_until is None


async def test_a_switch_off_in_the_app_stays_off(
    api: httpx2.AsyncClient, shop: ChannelConnection
) -> None:
    turn = await receive(incoming("m-1", "rendu cookie venum"))
    assert turn is not None
    token = await sign_in_as(shop.merchant_id)

    off = await api.put(
        f"/v1/chats/{turn.conversation_id}/agent", headers=bearer(token), json={"active": False}
    )
    await receive(incoming("m-2", "I'll handle it", echo=True))
    await pause_ended()  # nothing to end: a switch-off has no end time
    later = await receive(incoming("m-3", "hello?"))

    switched_off = await chat(turn.conversation_id)
    assert off.status_code == 200
    assert later is None
    assert (switched_off.agent_active, switched_off.agent_paused_reason) == (
        False,
        "merchant_switched_off",
    )


async def test_switching_the_assistant_back_on_ends_the_pause_at_once(
    api: httpx2.AsyncClient, shop: ChannelConnection
) -> None:
    turn = await receive(incoming("m-1", "rendu cookie venum"))
    assert turn is not None
    await receive(incoming("m-2", "One moment", echo=True))

    on = await api.put(
        f"/v1/chats/{turn.conversation_id}/agent",
        headers=bearer(await sign_in_as(shop.merchant_id)),
        json={"active": True},
    )
    next_turn = await receive(incoming("m-3", "two please"))

    resumed = await chat(turn.conversation_id)
    assert on.status_code == 200 and on.json() == {"active": True}
    assert (resumed.agent_active, resumed.agent_paused_until) == (True, None)
    assert next_turn is not None


async def test_the_owner_sends_from_the_app_through_the_outbox(
    api: httpx2.AsyncClient,
    shop: ChannelConnection,
    instagram: Instagram,
    deferred_jobs: InMemoryConnector,
) -> None:
    turn = await receive(incoming("m-1", "is the red velvet fresh?"))
    assert turn is not None
    token = await sign_in_as(shop.merchant_id)

    sent = await api.post(
        f"/v1/chats/{turn.conversation_id}/messages",
        headers=bearer(token),
        json={"text": "  Baked this morning! Meena here.  "},
    )
    queued_jobs = [job["task_name"] for job in deferred_jobs.jobs.values()]
    await conversations.deliver_outbox(turn.conversation_id)  # what that job does
    # Instagram echoes the message back: it is recognised as ours, not a second owner reply.
    await receive(incoming("ig-1", "Baked this morning! Meena here.", echo=True))

    assert sent.status_code == 201
    body = sent.json()
    assert set(body) == {"id", "text", "status", "created_at"}
    assert (body["text"], body["status"]) == ("Baked this morning! Meena here.", "queued")
    assert queued_jobs == ["send_outbound"]
    assert [m["text"] for m in instagram.sent] == ["Baked this morning! Meena here."]
    async with session_scope() as session:
        owner_messages = list(
            await session.scalars(select(Message).where(Message.sender == "merchant"))
        )
        row = await session.scalar(select(OutboundMessage))
    assert [(m.id, m.status, m.external_id) for m in owner_messages] == [
        (uuid.UUID(body["id"]), "sent", "ig-1")
    ]
    assert row is not None and row.window_policy == "human_agent"
    paused = await chat(turn.conversation_id)
    assert (paused.agent_active, paused.agent_paused_reason) == (False, "merchant_replied")
    assert paused.agent_paused_until is not None
    messages = await api.get(f"/v1/chats/{turn.conversation_id}/messages", headers=bearer(token))
    assert [(m["sender"], m["body"]) for m in messages.json()][-1] == (
        "merchant",
        "Baked this morning! Meena here.",
    )


async def test_sending_after_instagrams_24_hours_is_refused(
    api: httpx2.AsyncClient, shop: ChannelConnection, deferred_jobs: InMemoryConnector
) -> None:
    turn = await receive(incoming("m-1", "hi"))
    assert turn is not None
    async with session_scope() as session:
        await session.execute(
            update(Conversation).values(last_customer_message_at=func.now() - timedelta(hours=25))
        )
    token = await sign_in_as(shop.merchant_id)

    late = await api.post(
        f"/v1/chats/{turn.conversation_id}/messages", headers=bearer(token), json={"text": "Hi!"}
    )
    blank = await api.post(
        f"/v1/conversations/{turn.conversation_id}/messages",
        headers=bearer(token),
        json={"text": "   "},
    )
    empty = await api.post(
        f"/v1/chats/{turn.conversation_id}/messages", headers=bearer(token), json={"text": ""}
    )

    assert late.status_code == 409
    assert "24 hours" in late.json()["detail"]
    assert blank.status_code == 422 and empty.status_code == 422
    async with session_scope() as session:
        assert await session.scalar(select(func.count()).select_from(OutboundMessage)) == 0
    assert (await chat(turn.conversation_id)).agent_active is True
    assert deferred_jobs.jobs == {}


async def test_the_chat_list_pages_with_before(
    api: httpx2.AsyncClient, shop: ChannelConnection
) -> None:
    for n in range(3):
        await receive(incoming(f"m-{n}", f"message {n}", customer=f"70000000000001{n}"))
    headers = bearer(await sign_in_as(shop.merchant_id))

    first = (await api.get("/v1/chats", headers=headers, params={"limit": 2})).json()
    second = (
        await api.get(
            "/v1/chats",
            headers=headers,
            params={"limit": 2, "before": first[-1]["last_message_at"]},
        )
    ).json()
    old_path = (await api.get("/v1/conversations", headers=headers)).json()

    assert [row["last_message_body"] for row in first] == ["message 2", "message 1"]
    assert [row["last_message_body"] for row in second] == ["message 0"]
    assert [row["id"] for row in old_path] == [row["id"] for row in first + second]
