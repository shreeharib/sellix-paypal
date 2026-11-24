"""Shop B must never see or change shop A's data, through any endpoint.

Every /v1 endpoint that takes an id is listed in ATTACKS and called by a signed-in user of
another shop with shop A's real ids. A guard test fails when a new endpoint with an id is added
without being listed here, so isolation is checked for each one as it appears.
"""

import uuid
from collections.abc import AsyncIterator
from dataclasses import dataclass
from typing import Any

import httpx2
import pytest

from app.core.db import session_scope
from app.main import create_app
from app.modules.agent import service as agent
from app.modules.channels.models import ChannelConnection
from app.modules.conversations.models import Conversation
from app.modules.escalations import service as escalations
from app.modules.escalations.models import Escalation
from app.modules.merchants import service as merchants
from app.modules.merchants.models import Merchant
from app.modules.orders import service as orders
from app.modules.orders.models import Order
from app.modules.orders.schemas import OrderLineRequest, OrderRequest
from tests.integration.factories import start_conversation
from tests.integration.test_api import bearer, sign_in_as

pytestmark = pytest.mark.anyio


@dataclass
class Ids:
    product: uuid.UUID
    order: uuid.UUID
    question: uuid.UUID
    conversation: uuid.UUID
    rule: uuid.UUID | None = None  # a saved "always" answer


@pytest.fixture
async def api(db: None) -> AsyncIterator[httpx2.AsyncClient]:
    transport = httpx2.ASGITransport(app=create_app())
    async with httpx2.AsyncClient(transport=transport, base_url="http://test") as client:
        yield client


@pytest.fixture
async def world(api: httpx2.AsyncClient, shop: ChannelConnection) -> tuple[Ids, str, str]:
    """Shop A with a product, an order, a chat and a question; plus tokens for A and for B."""
    owner = await sign_in_as(shop.merchant_id)
    await api.put(
        "/v1/today/stock",
        headers=bearer(owner),
        json={"lines": [{"product": "Sourdough", "price_minor": 15000, "quantity": 10}]},
    )
    product_id = uuid.UUID((await api.get("/v1/products", headers=bearer(owner))).json()[0]["id"])
    turn = await start_conversation()
    async with session_scope() as session:
        merchant = await merchants.get_merchant(session, shop.merchant_id)
        conversation = await session.get(Conversation, turn.conversation_id)
        assert conversation is not None
        placed = await orders.place_order(
            session,
            merchant_id=shop.merchant_id,
            customer_id=conversation.customer_id,
            conversation_id=conversation.id,
            business_date=merchants.business_date(merchant),
            request=OrderRequest(
                lines=(OrderLineRequest("Sourdough", None, 2),), fulfilment="pickup"
            ),
            hold_minutes=15,
        )
        question = await escalations.open_escalation(
            session,
            merchant_id=shop.merchant_id,
            conversation_id=turn.conversation_id,
            question="Discount?",
        )
        other = Merchant(name="Other shop")
        session.add(other)
        await session.flush()
        other_id = other.id
    intruder = await sign_in_as(other_id, subject="17841400000009999")
    await agent.save_rule(
        merchant_id=shop.merchant_id,
        question="Discount?",
        answer="No discounts, sorry",
        source_escalation_id=question.id,
    )
    [rule] = await agent.saved_rules(shop.merchant_id)
    ids = Ids(
        product=product_id,
        order=placed.order_id,
        question=question.id,
        conversation=turn.conversation_id,
        rule=rule.id,
    )
    return ids, owner, intruder


def attacks(ids: Ids) -> dict[str, tuple[str, dict[str, Any] | None]]:
    """ "METHOD /v1/path/{param}" -> (path with shop A's ids, JSON body)."""
    unknown = uuid.uuid4()
    table: dict[str, tuple[str, dict[str, Any] | None]] = {
        "GET /v1/products/{product_id}": (f"/v1/products/{ids.product}", None),
        "PATCH /v1/products/{product_id}": (
            f"/v1/products/{ids.product}",
            {"name": "Hijacked"},
        ),
        "POST /v1/products/{product_id}/aliases": (
            f"/v1/products/{ids.product}/aliases",
            {"alias_text": "stolen"},
        ),
        "DELETE /v1/products/{product_id}/aliases/{alias_id}": (
            f"/v1/products/{ids.product}/aliases/{unknown}",
            None,
        ),
        "GET /v1/orders/{order_id}": (f"/v1/orders/{ids.order}", None),
        "POST /v1/orders/{order_id}/refund": (f"/v1/orders/{ids.order}/refund", {}),
        "GET /v1/orders/{order_id}/payments": (f"/v1/orders/{ids.order}/payments", None),
        "POST /v1/orders/{order_id}/mark-paid": (f"/v1/orders/{ids.order}/mark-paid", {}),
        "POST /v1/orders/{order_id}/complete": (f"/v1/orders/{ids.order}/complete", None),
        "POST /v1/orders/{order_id}/cancel": (f"/v1/orders/{ids.order}/cancel", {}),
        "GET /v1/orders/{order_id}/payment-link": (
            f"/v1/orders/{ids.order}/payment-link",
            None,
        ),
        "PATCH /v1/orders/{order_id}/status": (
            f"/v1/orders/{ids.order}/status",
            {"status": "cancelled"},
        ),
        "GET /v1/orders/{order_id}/timeline": (f"/v1/orders/{ids.order}/timeline", None),
        "POST /v1/questions/{question_id}/answer": (
            f"/v1/questions/{ids.question}/answer",
            {"answer": "x"},
        ),
        "POST /v1/questions/{question_id}/close": (
            f"/v1/questions/{ids.question}/close",
            None,
        ),
        "GET /v1/conversations/{conversation_id}/messages": (
            f"/v1/conversations/{ids.conversation}/messages",
            None,
        ),
        "POST /v1/conversations/{conversation_id}/messages": (
            f"/v1/conversations/{ids.conversation}/messages",
            {"text": "Hijacked"},
        ),
        "PUT /v1/conversations/{conversation_id}/agent": (
            f"/v1/conversations/{ids.conversation}/agent",
            {"active": False},
        ),
        "GET /v1/conversations/{conversation_id}/memory": (
            f"/v1/conversations/{ids.conversation}/memory",
            None,
        ),
        "DELETE /v1/conversations/{conversation_id}/memory/{key}": (
            f"/v1/conversations/{ids.conversation}/memory/allergy",
            None,
        ),
        "GET /v1/conversations/{conversation_id}/drafts": (
            f"/v1/conversations/{ids.conversation}/drafts",
            None,
        ),
        "POST /v1/conversations/{conversation_id}/drafts/{message_id}/approve": (
            f"/v1/conversations/{ids.conversation}/drafts/{unknown}/approve",
            {},
        ),
        "POST /v1/conversations/{conversation_id}/drafts/{message_id}/discard": (
            f"/v1/conversations/{ids.conversation}/drafts/{unknown}/discard",
            None,
        ),
        "POST /v1/stories/{story_id}/confirm": (
            "/v1/stories/some-story/confirm",
            {"item_ids": [str(ids.product)]},
        ),
        "PUT /v1/stories/posts/{product_id}": (
            f"/v1/stories/posts/{ids.product}",
            {"ig_media_id": "123"},
        ),
        "DELETE /v1/rules/{rule_id}": (f"/v1/rules/{ids.rule or unknown}", None),
    }
    # The chat endpoints are served under /v1/chats as well (docs/api-changes-2026-11-24.md).
    for name, (path, body) in list(table.items()):
        if " /v1/conversations/" in name:
            table[name.replace("/v1/conversations/", "/v1/chats/")] = (
                path.replace("/v1/conversations/", "/v1/chats/"),
                body,
            )
    return table


async def test_every_endpoint_with_an_id_is_covered_here(
    world: tuple[Ids, str, str],
) -> None:
    documented = create_app().openapi()["paths"]
    with_ids = {
        f"{method.upper()} {path}"
        for path, methods in documented.items()
        if path.startswith("/v1") and "{" in path
        for method in methods
    }

    assert with_ids == set(attacks(world[0])), (
        "Add the new endpoint to ATTACKS (or remove the old one)"
    )


async def test_another_shop_gets_not_found_everywhere_and_changes_nothing(
    api: httpx2.AsyncClient, world: tuple[Ids, str, str], monkeypatch: pytest.MonkeyPatch
) -> None:
    ids, owner, intruder = world
    leaks: list[str] = []

    for name, (path, body) in attacks(ids).items():
        method = name.split()[0]
        response = await api.request(method, path, headers=bearer(intruder), json=body)
        # Story items are looked up by id inside the shop's own catalog: unknown ids are a 400.
        allowed = (400,) if name == "POST /v1/stories/{story_id}/confirm" else (403, 404)
        if response.status_code not in allowed:
            leaks.append(f"{name} -> {response.status_code} {response.text[:120]}")

    assert not leaks, "\n".join(leaks)

    async with session_scope() as session:
        order = await session.get(Order, ids.order)
        question = await session.get(Escalation, ids.question)
        conversation = await session.get(Conversation, ids.conversation)
    assert order is not None
    assert order.status == "awaiting_payment"
    assert question is not None
    assert question.status == "open"
    assert conversation is not None
    assert conversation.agent_active is True
    assert [rule.id for rule in await agent.saved_rules(conversation.merchant_id)] == [ids.rule]
    product = await api.get(f"/v1/products/{ids.product}", headers=bearer(owner))
    assert product.json()["name"] == "Sourdough"
    assert "stolen" not in [alias["alias_text"] for alias in product.json()["aliases"]]


@pytest.mark.parametrize(
    "path",
    [
        "/v1/orders",
        "/v1/products",
        "/v1/products/search?q=sourdough",
        "/v1/conversations",
        "/v1/chats",
        "/v1/rules",
        "/v1/questions",
        "/v1/today",
        "/v1/today/leftovers",
        "/v1/stock/upcoming",
        "/v1/stories/unconfirmed",
    ],
)
async def test_lists_of_another_shop_show_none_of_this_shops_data(
    api: httpx2.AsyncClient, world: tuple[Ids, str, str], path: str
) -> None:
    ids, owner, intruder = world

    mine = await api.get(path, headers=bearer(owner))
    theirs = await api.get(path, headers=bearer(intruder))

    assert theirs.status_code == 200
    for secret in ("Sourdough", str(ids.product), str(ids.order), str(ids.conversation)):
        assert secret not in theirs.text
    assert mine.status_code == 200


def body_attacks(variant_id: str) -> dict[str, dict[str, Any]]:
    """Endpoints that take shop A's id in the JSON body, not the path."""
    return {
        "/v1/today/restock": {"variant_id": variant_id, "quantity": 5},
        "/v1/today/sold-out": {"variant_id": variant_id},
        "/v1/today/counter-sale": {"variant_id": variant_id, "quantity": 1},
        "/v1/today/rollover": {"items": [{"variant_id": variant_id, "rollover_quantity": 1}]},
    }


async def test_another_shops_id_in_a_request_body_is_not_found_and_changes_nothing(
    api: httpx2.AsyncClient, world: tuple[Ids, str, str]
) -> None:
    _, owner, intruder = world
    before = (await api.get("/v1/today", headers=bearer(owner))).json()["stock"]
    variant_id = before[0]["variant_id"]
    leaks: list[str] = []

    for path, body in body_attacks(variant_id).items():
        response = await api.post(path, headers=bearer(intruder), json=body)
        if response.status_code not in (404, 422):
            leaks.append(f"POST {path} -> {response.status_code} {response.text[:120]}")

    assert not leaks, "\n".join(leaks)
    after = (await api.get("/v1/today", headers=bearer(owner))).json()["stock"]
    assert after == before
    assert (after[0]["opening"], after[0]["restocked"], after[0]["counter_sales"]) == (10, 0, 0)
