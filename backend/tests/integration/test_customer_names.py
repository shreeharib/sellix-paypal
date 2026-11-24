"""New Instagram customers get their profile name, so the app shows "Priya", not an id.

Instagram is faked at its HTTP call (channels/instagram.py `_request`): this can't be checked
against the real Instagram from this network.
"""

from collections.abc import AsyncIterator
from typing import Any

import httpx2
import pytest
from sqlalchemy import select

from app.core.config import get_settings
from app.core.db import session_scope
from app.main import create_app
from app.modules.channels import instagram
from app.modules.channels import service as channels
from app.modules.channels.models import ChannelConnection
from app.modules.channels.schemas import IncomingMessage
from app.modules.conversations import service as conversations
from app.modules.conversations.models import Customer
from tests.integration.factories import CUSTOMER_ID, start_conversation
from tests.integration.test_api import bearer, sign_in_as

pytestmark = pytest.mark.anyio


class FakeGraph:
    """Instagram's Graph API at the HTTP layer: answers profile look-ups, records each call."""

    def __init__(self, answer: dict[str, Any] | Exception) -> None:
        self.answer = answer
        self.calls: list[dict[str, Any]] = []

    async def __call__(self, method: str, url: str, **kwargs: Any) -> dict[str, Any]:
        self.calls.append({"method": method, "url": url, **kwargs})
        if isinstance(self.answer, Exception):
            raise self.answer
        return self.answer


@pytest.fixture
async def api(db: None) -> AsyncIterator[httpx2.AsyncClient]:
    transport = httpx2.ASGITransport(app=create_app())
    async with httpx2.AsyncClient(transport=transport, base_url="http://test") as client:
        yield client


def graph(monkeypatch: pytest.MonkeyPatch, answer: dict[str, Any] | Exception) -> FakeGraph:
    fake = FakeGraph(answer)
    monkeypatch.setattr(instagram, "_request", fake)
    return fake


async def customer() -> Customer:
    async with session_scope() as session:
        found = await session.scalar(select(Customer).where(Customer.external_id == CUSTOMER_ID))
    assert found is not None
    return found


async def test_a_new_customer_is_named_from_their_instagram_profile(
    api: httpx2.AsyncClient, shop: ChannelConnection, monkeypatch: pytest.MonkeyPatch
) -> None:
    fake = graph(monkeypatch, {"name": "Priya Raman", "username": "priya.bakes", "id": CUSTOMER_ID})
    turn = await start_conversation()

    named = await conversations.fetch_customer_names()
    again = await conversations.fetch_customer_names()
    chats = await api.get("/v1/chats", headers=bearer(await sign_in_as(shop.merchant_id)))
    async with session_scope() as session:
        state = await conversations.load_state(session, turn.conversation_id)

    assert (named, again) == (1, 0)
    assert len(fake.calls) == 1  # once per customer
    call = fake.calls[0]
    assert (call["method"], call["url"]) == (
        "GET",
        f"https://graph.instagram.com/{get_settings().graph_api_version}/{CUSTOMER_ID}",
    )
    assert call["params"] == {"fields": "name,username"}
    assert call["token"] == "ig-token"  # the shop's own token
    stored = await customer()
    assert stored.display_name == "Priya Raman"
    assert stored.custom_attributes["instagram_username"] == "priya.bakes"
    assert chats.json()[0]["customer_handle"] == "Priya Raman"
    assert state is not None and state.customer_handle == "Priya Raman"


async def test_a_profile_without_a_name_uses_the_username(
    shop: ChannelConnection, monkeypatch: pytest.MonkeyPatch
) -> None:
    graph(monkeypatch, {"username": "@meena_k"})
    await start_conversation()

    await conversations.fetch_customer_names()

    assert (await customer()).display_name == "meena_k"


async def test_a_failed_lookup_is_harmless_and_tried_three_times_at_most(
    shop: ChannelConnection, monkeypatch: pytest.MonkeyPatch
) -> None:
    fake = graph(monkeypatch, instagram.InstagramAPIError(400, "Unsupported get request"))
    turn = await start_conversation()

    results = [await conversations.fetch_customer_names() for _ in range(4)]

    assert results == [0, 0, 0, 0]
    assert len(fake.calls) == 3
    stored = await customer()
    assert stored.display_name is None
    assert stored.custom_attributes["instagram_profile"]["attempts"] == 3
    async with session_scope() as session:
        state = await conversations.load_state(session, turn.conversation_id)
    assert state is not None and state.customer_handle == CUSTOMER_ID  # as before


async def test_simulator_customers_are_never_looked_up(
    shop: ChannelConnection, monkeypatch: pytest.MonkeyPatch
) -> None:
    fake = graph(monkeypatch, {"name": "Should not be asked"})
    async with session_scope() as session:
        account = await channels.simulator_account(session, shop.merchant_id)
        await conversations.handle_incoming(
            session,
            IncomingMessage(
                channel="webchat",
                shop_account_id=account,
                customer_id="tester",
                message_id="w-1",
                text="hello",
            ),
        )

    assert await conversations.fetch_customer_names() == 0
    assert fake.calls == []
