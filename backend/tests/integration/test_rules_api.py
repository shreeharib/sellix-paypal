"""Settings > Rules: the saved "always" answers can be listed and deleted, per shop."""

import uuid
from collections.abc import AsyncIterator

import httpx2
import pytest
from procrastinate.testing import InMemoryConnector

from app.core.db import session_scope
from app.main import create_app
from app.modules.agent import service as agent
from app.modules.channels.models import ChannelConnection
from app.modules.escalations import service as escalations
from app.modules.merchants import service as merchants
from tests.integration.factories import start_conversation
from tests.integration.test_api import bearer, sign_in_as

pytestmark = pytest.mark.anyio


@pytest.fixture
async def api(db: None) -> AsyncIterator[httpx2.AsyncClient]:
    transport = httpx2.ASGITransport(app=create_app())
    async with httpx2.AsyncClient(transport=transport, base_url="http://test") as client:
        yield client


async def test_an_always_answer_is_listed_and_can_be_deleted(
    api: httpx2.AsyncClient, shop: ChannelConnection, deferred_jobs: InMemoryConnector
) -> None:
    turn = await start_conversation("do you deliver to Velachery?")
    async with session_scope() as session:
        question = await escalations.open_escalation(
            session,
            merchant_id=shop.merchant_id,
            conversation_id=turn.conversation_id,
            question="Do you deliver to Velachery?",
        )
    headers = bearer(await sign_in_as(shop.merchant_id))
    await api.post(
        f"/v1/questions/{question.id}/answer",
        headers=headers,
        json={"answer": "Yes, Rs 50 delivery", "always": True},
    )
    await agent.save_rule(
        merchant_id=shop.merchant_id,
        question="Eggless?",
        answer="All cakes can be eggless",
        source_escalation_id=question.id,
    )

    listed = await api.get("/v1/rules", headers=headers)
    rules = listed.json()
    deleted = await api.delete(f"/v1/rules/{rules[0]['id']}", headers=headers)
    again = await api.delete(f"/v1/rules/{rules[0]['id']}", headers=headers)
    after = await api.get("/v1/rules", headers=headers)

    assert listed.status_code == 200
    assert [rule["text"] for rule in rules] == [
        "Eggless?: All cakes can be eggless",
        "Do you deliver to Velachery?: Yes, Rs 50 delivery",
    ]
    assert {"id", "text", "created_at"} <= set(rules[0])
    assert deleted.status_code == 204
    assert again.status_code == 404
    assert [rule["text"] for rule in after.json()] == [
        "Do you deliver to Velachery?: Yes, Rs 50 delivery"
    ]


async def test_another_shops_rule_is_not_found_and_stays(
    api: httpx2.AsyncClient, shop: ChannelConnection
) -> None:
    turn = await start_conversation("bulk order for 200 people?")
    async with session_scope() as session:
        other = await merchants.create_merchant(session, name="Other shop")
        question = await escalations.open_escalation(
            session,
            merchant_id=shop.merchant_id,
            conversation_id=turn.conversation_id,
            question="Bulk orders?",
        )
    await agent.save_rule(
        merchant_id=shop.merchant_id,
        question="Bulk orders?",
        answer="Ask the owner",
        source_escalation_id=question.id,
    )
    [rule] = await agent.saved_rules(shop.merchant_id)
    intruder = bearer(await sign_in_as(other.id, subject="17841400000009999"))

    theirs = await api.get("/v1/rules", headers=intruder)
    delete = await api.delete(f"/v1/rules/{rule.id}", headers=intruder)
    unknown = await api.delete(f"/v1/rules/{uuid.uuid4()}", headers=intruder)

    assert theirs.json() == []
    assert delete.status_code == 404
    assert unknown.status_code == 404
    assert [r.id for r in await agent.saved_rules(shop.merchant_id)] == [rule.id]
