"""Rollout (agent-phase-2.md section 19): shadow mode and draft mode for the v2 engine."""

import httpx2
import pytest
from sqlalchemy import func, select

from app.core.db import session_scope
from app.main import create_app
from app.modules.agent import service as agent
from app.modules.agent.models import AgentTurn
from app.modules.agent.schemas import CustomerReply
from app.modules.channels.models import ChannelConnection
from app.modules.channels.schemas import IncomingMessage
from app.modules.conversations import service as conversations
from app.modules.merchants import service as merchants
from app.modules.orders.models import QuoteRecord
from tests.integration.factories import CUSTOMER_ID, SHOP_ACCOUNT_ID, Instagram, ScriptedModel
from tests.integration.test_agent_v2 import cookie_id
from tests.integration.test_api import bearer, sign_in_as

pytestmark = pytest.mark.anyio


async def receive(text: str, mid: str) -> conversations.TurnRequest:
    async with session_scope() as session:
        turn = await conversations.handle_incoming(
            session,
            IncomingMessage(
                channel="instagram",
                shop_account_id=SHOP_ACCOUNT_ID,
                customer_id=CUSTOMER_ID,
                message_id=mid,
                text=text,
            ),
        )
    assert turn is not None
    return turn


async def use_engine(shop: ChannelConnection, engine: str) -> None:
    async with session_scope() as session:
        await merchants.set_agent_engine(session, shop.merchant_id, engine)  # pyright: ignore[reportArgumentType]


async def test_shadow_mode_runs_v2_silently_next_to_v1(
    v2_shop: ChannelConnection,
    model: ScriptedModel,
    instagram: Instagram,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    await use_engine(v2_shop, "shadow")
    cookie = await cookie_id(v2_shop)

    async def v1_reply(**_: object) -> CustomerReply:
        return CustomerReply(reply="v1 says hi", language="en")

    monkeypatch.setattr(agent, "reply_to_customer", v1_reply)
    model.then(
        [
            (
                "update_order_draft",
                {"items": [{"item_id": cookie, "quantity": 2}], "fulfilment": "pickup"},
            )
        ],
        [("create_quote", {})],
        [("send_reply", {"text": "v2 would say hi", "language": "en"})],
    )
    turn = await receive("2 cookies pickup", "m-1")

    await conversations.run_turn(turn.conversation_id)  # v1 answers the customer
    await agent.run_turn(turn.conversation_id, shadow=True)  # v2 only watches

    assert instagram.texts() == ["v1 says hi"]
    async with session_scope() as session:
        quotes = await session.scalar(select(func.count()).select_from(QuoteRecord))
        traced = await session.scalar(select(AgentTurn))
    assert quotes == 0  # no writes in shadow mode
    assert traced is not None and traced.mode == "shadow" and traced.status == "replied"
    [row] = await agent.shadow_report(v2_shop.merchant_id)
    assert (row["customer"], row["v1"], row["v2"]) == (
        "2 cookies pickup",
        "v1 says hi",
        "v2 would say hi",
    )


async def test_draft_mode_waits_for_the_merchant_to_approve_each_reply(
    v2_shop: ChannelConnection, model: ScriptedModel, instagram: Instagram
) -> None:
    await use_engine(v2_shop, "draft")
    model.then([("send_reply", {"text": "Hello there!", "language": "en"})])
    turn = await receive("hi", "m-1")

    await agent.run_turn(turn.conversation_id)
    assert instagram.texts() == []

    token = await sign_in_as(v2_shop.merchant_id)
    async with httpx2.AsyncClient(
        transport=httpx2.ASGITransport(app=create_app()), base_url="http://test"
    ) as api:
        drafts = await api.get(
            f"/v1/conversations/{turn.conversation_id}/drafts", headers=bearer(token)
        )
        [draft] = drafts.json()
        approved = await api.post(
            f"/v1/conversations/{turn.conversation_id}/drafts/{draft['id']}/approve",
            headers=bearer(token),
            json={"text": "Hello! What would you like today?"},
        )

    assert draft["body"] == "Hello there!"
    assert approved.status_code == 200
    assert instagram.texts() == ["Hello! What would you like today?"]


async def test_a_draft_can_be_discarded(
    v2_shop: ChannelConnection, model: ScriptedModel, instagram: Instagram
) -> None:
    await use_engine(v2_shop, "draft")
    model.then([("send_reply", {"text": "Hello there!", "language": "en"})])
    turn = await receive("hi", "m-1")
    await agent.run_turn(turn.conversation_id)
    token = await sign_in_as(v2_shop.merchant_id)
    async with httpx2.AsyncClient(
        transport=httpx2.ASGITransport(app=create_app()), base_url="http://test"
    ) as api:
        [draft] = (
            await api.get(f"/v1/conversations/{turn.conversation_id}/drafts", headers=bearer(token))
        ).json()
        discarded = await api.post(
            f"/v1/conversations/{turn.conversation_id}/drafts/{draft['id']}/discard",
            headers=bearer(token),
        )
        after = await api.get(
            f"/v1/conversations/{turn.conversation_id}/drafts", headers=bearer(token)
        )

    assert discarded.status_code == 200
    assert after.json() == []
    assert instagram.texts() == []
