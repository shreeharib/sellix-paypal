"""Memory (agent-phase-2.md section 8) and the remaining tools (2.13), on the v2 engine."""

import uuid
from typing import Any

import httpx2
import pytest
from sqlalchemy import func, select

from app.core.db import session_scope
from app.main import create_app
from app.modules.agent import items
from app.modules.agent import service as agent
from app.modules.agent.models import CustomerMemory, MerchantRule
from app.modules.channels.models import ChannelConnection
from app.modules.channels.schemas import IncomingMessage
from app.modules.conversations import service as conversations
from app.modules.conversations.models import Conversation, Message
from app.modules.escalations import service as escalations
from app.modules.insights.models import MissedDemand
from app.modules.inventory import service as inventory
from app.modules.merchants import service as merchants
from app.modules.orders import service as orders
from app.modules.orders.models import Order, QuoteRecord
from app.modules.orders.schemas import OrderLineRequest, OrderRequest
from tests.integration.factories import CUSTOMER_ID, SHOP_ACCOUNT_ID, Instagram, ScriptedModel
from tests.integration.test_api import bearer, sign_in_as

pytestmark = pytest.mark.anyio


async def customer_says(text: str, mid: str) -> uuid.UUID:
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
    await agent.run_turn(turn.conversation_id)
    return turn.conversation_id


def tool_results(model: ScriptedModel, call: int = -1) -> list[str]:
    return [m.content for m in model.calls[call][0] if m.role == "tool"]


async def cookie(shop: ChannelConnection) -> str:
    async with session_scope() as session:
        merchant = await merchants.get_merchant(session, shop.merchant_id)
        [item] = await inventory.today_stock(
            session, shop.merchant_id, merchants.business_date(merchant)
        )
    assert item.variant_id is not None
    return items.ref(item.variant_id)


async def a_paid_order(shop: ChannelConnection, conversation_id: uuid.UUID) -> None:
    async with session_scope() as session:
        merchant = await merchants.get_merchant(session, shop.merchant_id)
        conversation = await session.get(Conversation, conversation_id)
        assert conversation is not None
        placed = await orders.place_order(
            session,
            merchant_id=shop.merchant_id,
            customer_id=conversation.customer_id,
            conversation_id=conversation_id,
            business_date=merchants.business_date(merchant),
            request=OrderRequest(
                lines=(OrderLineRequest("Scoop cookie", "Chocolate", 3),),
                fulfilment="delivery",
                delivery_address="12 Lake Road",
            ),
            hold_minutes=15,
        )
        await orders.record_payment(
            session, placed.order_id, amount_minor=18000, currency="INR", actor="paypal"
        )


async def test_same_as_last_time_quotes_the_usual_order_and_address(
    v2_shop: ChannelConnection, model: ScriptedModel, instagram: Instagram
) -> None:
    model.then(
        [("remember_customer_fact", {"key": "address", "value": "12 Lake Road"})],
        [("send_reply", {"text": "Noted!", "language": "en"})],
    )
    conversation_id = await customer_says("my address is 12 Lake Road", "m-1")
    await a_paid_order(v2_shop, conversation_id)
    item = await cookie(v2_shop)

    model.then(
        [("get_customer_profile", {})],
        [
            (
                "update_order_draft",
                {
                    "items": [{"item_id": item, "quantity": 3}],
                    "fulfilment": "delivery",
                    "delivery_address": "12 Lake Road",
                },
            )
        ],
        [("create_quote", {})],
        [
            (
                "send_reply",
                {"text": "Same as last time: [[quote_total]]. Confirm?", "language": "en"},
            )
        ],
    )
    await customer_says("same as last time please", "m-2")

    profile = tool_results(model, -3)[-1]
    assert item in profile and '"quantity": 3' in profile
    assert "12 Lake Road" in profile
    async with session_scope() as session:
        quote = await session.scalar(select(QuoteRecord))
    assert quote is not None
    assert quote.delivery_address == "12 Lake Road"
    assert quote.lines[0]["quantity"] == 3


async def test_only_allow_listed_facts_are_remembered(
    v2_shop: ChannelConnection, model: ScriptedModel, instagram: Instagram
) -> None:
    model.then(
        [
            ("remember_customer_fact", {"key": "card_number", "value": "4111"}),
            ("remember_customer_fact", {"key": "name", "value": "Priya"}),
        ],
        [("send_reply", {"text": "Thanks Priya!", "language": "en"})],
    )

    await customer_says("I'm Priya", "m-1")

    async with session_scope() as session:
        memories = list(await session.scalars(select(CustomerMemory)))
    assert [(m.key, m.value) for m in memories] == [("name", "Priya")]
    assert "not_allowed" in tool_results(model)[0] or "invalid" in tool_results(model)[0]


async def test_the_merchant_can_see_and_delete_a_customers_memory(
    v2_shop: ChannelConnection, model: ScriptedModel, instagram: Instagram
) -> None:
    model.then(
        [("remember_customer_fact", {"key": "dietary_note", "value": "no eggs"})],
        [("send_reply", {"text": "Noted!", "language": "en"})],
    )
    conversation_id = await customer_says("we don't eat eggs", "m-1")
    token = await sign_in_as(v2_shop.merchant_id)
    async with httpx2.AsyncClient(
        transport=httpx2.ASGITransport(app=create_app()), base_url="http://test"
    ) as api:
        shown = await api.get(f"/v1/conversations/{conversation_id}/memory", headers=bearer(token))
        deleted = await api.delete(
            f"/v1/conversations/{conversation_id}/memory/dietary_note", headers=bearer(token)
        )
        after = await api.get(f"/v1/conversations/{conversation_id}/memory", headers=bearer(token))

    assert [(m["key"], m["value"]) for m in shown.json()] == [("dietary_note", "no eggs")]
    assert deleted.status_code == 204
    assert after.json() == []


async def test_order_status_shows_only_this_customers_orders(
    v2_shop: ChannelConnection, model: ScriptedModel, instagram: Instagram
) -> None:
    model.then([("send_reply", {"text": "Hi!", "language": "en"})])
    conversation_id = await customer_says("hi", "m-1")
    await a_paid_order(v2_shop, conversation_id)
    model.then(
        [("get_order_status", {})],
        [("send_reply", {"text": "Your order is paid!", "language": "en"})],
    )

    await customer_says("where is my order?", "m-2")

    [status] = tool_results(model)
    assert '"paid"' in status
    assert status.count('"number"') == 1


async def test_cancel_order_releases_the_stock_and_resend_reuses_the_link(
    v2_shop: ChannelConnection, model: ScriptedModel, instagram: Instagram
) -> None:
    item = await cookie(v2_shop)
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
    model.then(
        [("confirm_order", {"quote_id": str(quote.id)})],
        [("send_reply", {"text": "Done!", "language": "en"})],
    )
    await customer_says("yes", "m-2")
    async with session_scope() as session:
        order = await session.scalar(select(Order))
    assert order is not None

    model.then(
        [("resend_payment_link", {"order_id": str(order.id)})],
        [("send_reply", {"text": "Sent again!", "language": "en"})],
    )
    await customer_says("link please", "m-3")
    links = [t for t in instagram.texts() if "upi://pay" in t]
    assert len(links) == 2 and links[0] == links[1]

    model.then(
        [("cancel_order", {"order_id": str(order.id), "reason": "changed my mind"})],
        [("send_reply", {"text": "Cancelled.", "language": "en"})],
    )
    conversation_id = await customer_says("cancel it", "m-4")

    async with session_scope() as session:
        cancelled = await session.get(Order, order.id)
        conversation = await session.get(Conversation, conversation_id)
        merchant = await merchants.get_merchant(session, v2_shop.merchant_id)
        [stock] = await inventory.today_stock(
            session, v2_shop.merchant_id, merchants.business_date(merchant)
        )
    assert cancelled is not None and cancelled.status == "cancelled"
    assert conversation is not None and conversation.order_stage == "browsing"
    assert stock.available == 10


async def test_missed_demand_is_logged_for_insights(
    v2_shop: ChannelConnection, model: ScriptedModel, instagram: Instagram
) -> None:
    model.then(
        [("log_missed_demand", {"wanted_text": "red velvet cake", "reason": "not_stocked"})],
        [("send_reply", {"text": "Sorry, not today!", "language": "en"})],
    )

    await customer_says("red velvet cake irukka?", "m-1")

    async with session_scope() as session:
        demand = await session.scalar(select(MissedDemand))
    assert demand is not None and demand.requested_item_name == "red velvet cake"


async def test_a_playbook_can_be_loaded_once_per_turn(
    v2_shop: ChannelConnection, model: ScriptedModel, instagram: Instagram
) -> None:
    model.then(
        [("load_playbook", {"name": "complaint"}), ("load_playbook", {"name": "small_talk"})],
        [("send_reply", {"text": "Sorry to hear that.", "language": "en"})],
    )

    await customer_says("hmm", "m-1")

    first, second = tool_results(model)
    assert "Apologise" in first
    assert "once" in second


async def test_always_answer_this_way_becomes_a_saved_rule_the_agent_sees(
    v2_shop: ChannelConnection,
    model: ScriptedModel,
    instagram: Instagram,
    deferred_jobs: Any,
) -> None:
    model.then(
        [("ask_shop_owner", {"question": "Do you deliver to Velachery?"})],
        [("send_reply", {"text": "Let me check!", "language": "en"})],
    )
    await customer_says("deliver to velachery?", "m-1")
    async with session_scope() as session:
        [question] = await escalations.list_escalations(session, v2_shop.merchant_id)
    token = await sign_in_as(v2_shop.merchant_id)
    async with httpx2.AsyncClient(
        transport=httpx2.ASGITransport(app=create_app()), base_url="http://test"
    ) as api:
        await api.post(
            f"/v1/questions/{question.id}/answer",
            headers=bearer(token),
            json={"answer": "Yes, Velachery delivery is fine.", "always": True},
        )
    async with session_scope() as session:
        rules = list(await session.scalars(select(MerchantRule)))
    assert len(rules) == 1

    model.then([("send_reply", {"text": "Yes!", "language": "en"})])
    await customer_says("so velachery ok?", "m-2")

    system = model.calls[-1][0][0].content
    assert "Velachery delivery is fine" in system


async def test_long_conversations_get_a_summary_without_amounts(
    v2_shop: ChannelConnection, monkeypatch: pytest.MonkeyPatch
) -> None:
    from app.modules.agent import llm
    from app.modules.agent.models import ConversationSummary
    from app.modules.agent.schemas import ChatMessage

    async with session_scope() as session:
        turn = await conversations.handle_incoming(
            session,
            IncomingMessage(
                channel="instagram",
                shop_account_id=SHOP_ACCOUNT_ID,
                customer_id=CUSTOMER_ID,
                message_id="m-0",
                text="hi",
            ),
        )
        assert turn is not None
        for n in range(40):
            session.add(
                Message(
                    merchant_id=v2_shop.merchant_id,
                    conversation_id=turn.conversation_id,
                    direction="inbound",
                    sender="customer",
                    body=f"message {n}",
                    details={},
                    status="received",
                )
            )
    answers = ["Customer paid Rs.120 for cookies.", "Customer likes chocolate cookies."]

    async def complete(messages: list[ChatMessage], *, json_output: bool = False) -> Any:
        return llm.Completion(answers.pop(0), "cheap", 10, 10, 1)

    monkeypatch.setattr(llm, "complete", complete)

    assert await agent.summarise_long_conversations() == 0  # the summary had an amount
    assert await agent.summarise_long_conversations() == 1
    async with session_scope() as session:
        summary = await session.scalar(select(ConversationSummary))
        count = await session.scalar(select(func.count()).select_from(ConversationSummary))
    assert summary is not None and "chocolate" in summary.summary
    assert count == 1
