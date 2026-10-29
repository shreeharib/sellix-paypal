"""The simulator: a web chat through the same pipeline as Instagram (agent-phase-2.md 17)."""

from collections.abc import AsyncIterator

import httpx2
import pytest
from sqlalchemy import select

from app.core.db import session_scope
from app.main import create_app
from app.modules.channels.models import ChannelConnection
from app.modules.conversations import outbox
from app.modules.conversations.models import OutboundMessage
from tests.integration.factories import ScriptedModel
from tests.integration.test_agent_v2 import cookie_id
from tests.integration.test_api import bearer, sign_in_as

pytestmark = pytest.mark.anyio


@pytest.fixture
async def api(db: None) -> AsyncIterator[httpx2.AsyncClient]:
    transport = httpx2.ASGITransport(app=create_app())
    async with httpx2.AsyncClient(transport=transport, base_url="http://test") as client:
        yield client


async def test_an_order_through_the_simulator(
    v2_shop: ChannelConnection,
    model: ScriptedModel,
    api: httpx2.AsyncClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(outbox, "PACING_SECONDS", 0)
    token = await sign_in_as(v2_shop.merchant_id)
    cookie = await cookie_id(v2_shop)
    model.then(
        [
            (
                "update_order_draft",
                {"items": [{"item_id": cookie, "quantity": 2}], "fulfilment": "pickup"},
            )
        ],
        [("create_quote", {})],
        [("send_reply", {"text": "Confirm with the button!", "language": "en"})],
    )

    first = await api.post(
        "/v1/simulator/messages", headers=bearer(token), json={"text": "2 cookies, pickup"}
    )

    assert first.status_code == 200
    transcript = first.json()["messages"]
    card = transcript[-2]
    assert card["sender"] == "agent" and "₹120" in card["body"]
    confirm = next(b for b in card["buttons"] if b["payload"].startswith("CONFIRM:"))
    assert transcript[-1]["body"] == "Confirm with the button!"
    assert first.json()["turn"]["tools"] == ["update_order_draft", "create_quote", "send_reply"]

    model.then([("send_reply", {"text": "Thank you!", "language": "en"})])
    second = await api.post(
        "/v1/simulator/messages",
        headers=bearer(token),
        json={"text": confirm["title"], "quick_reply": confirm["payload"]},
    )

    bodies = [m["body"] for m in second.json()["messages"]]
    assert any("upi://pay" in body for body in bodies)
    assert bodies[-1] == "Thank you!"
    async with session_scope() as session:
        ids = list(await session.scalars(select(OutboundMessage.provider_message_id)))
    assert ids and all(i and i.startswith("web-") for i in ids)  # nothing went to Instagram


async def test_the_simulator_needs_a_signed_in_merchant(api: httpx2.AsyncClient) -> None:
    response = await api.post("/v1/simulator/messages", json={"text": "hi"})

    assert response.status_code == 401


async def test_the_simulator_page_is_served(api: httpx2.AsyncClient) -> None:
    page = await api.get("/simulator")

    assert page.status_code == 200
    assert "sellix simulator" in page.text.lower()
