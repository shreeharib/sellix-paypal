"""The /v1 API and "Continue with Instagram" login, end to end against the real database.

Instagram's OAuth endpoints are replaced (Instagram has no sandbox); PKCE, login codes,
sessions, token rotation and shop isolation are all real.
"""

import base64
import hashlib
import secrets
import uuid
from collections.abc import AsyncIterator
from urllib.parse import parse_qs, urlparse

import httpx2
import pytest
from procrastinate.testing import InMemoryConnector
from sqlalchemy import select

from app.core.config import get_settings
from app.core.db import session_scope
from app.main import create_app
from app.modules.accounts import service as accounts
from app.modules.accounts.models import Session
from app.modules.channels import instagram
from app.modules.channels.models import ChannelConnection
from app.modules.conversations.models import Conversation, Message
from app.modules.escalations import service as escalations
from app.modules.merchants import service as merchants
from app.modules.merchants.models import Merchant
from app.modules.orders import service as orders
from app.modules.orders.schemas import OrderLineRequest, OrderRequest
from app.modules.shop_profile import service as shop_profile
from tests.integration.factories import start_conversation

pytestmark = pytest.mark.anyio

APP_REDIRECT = "sellix://auth/callback"


def pkce_pair() -> tuple[str, str]:
    verifier = secrets.token_urlsafe(48)
    digest = hashlib.sha256(verifier.encode()).digest()
    return verifier, base64.urlsafe_b64encode(digest).rstrip(b"=").decode()


@pytest.fixture
async def api(db: None) -> AsyncIterator[httpx2.AsyncClient]:
    transport = httpx2.ASGITransport(app=create_app())
    async with httpx2.AsyncClient(transport=transport, base_url="http://test") as client:
        yield client


async def sign_in_as(merchant_id: uuid.UUID, subject: str = "17841400000000001") -> str:
    """An access token for a user of this shop, through a real login code and PKCE."""
    verifier, challenge = pkce_pair()
    async with session_scope() as session:
        user_id = await accounts.sign_in(
            session,
            provider="instagram",
            subject=subject,
            merchant_id=merchant_id,
            display_name="sweetcrumbs",
        )
        code = await accounts.create_login_code(session, user_id, challenge)
    async with session_scope() as session:
        pair = await accounts.redeem_login_code(
            session, code=code, code_verifier=verifier, user_agent="test"
        )
    return pair.access_token


def bearer(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def fake_instagram(monkeypatch: pytest.MonkeyPatch) -> None:
    async def exchange_code(**_: str) -> instagram.TokenGrant:
        return instagram.TokenGrant("short-token", None, instagram.SCOPES)

    async def exchange_long_lived(**_: str) -> instagram.TokenGrant:
        return instagram.TokenGrant("long-token", 5_184_000)

    async def fetch_account(**_: str) -> instagram.InstagramAccount:
        return instagram.InstagramAccount("17841477777777777", "chennaibakes")

    async def subscribe_webhooks(**_: str) -> None:
        return None

    for function in (exchange_code, exchange_long_lived, fetch_account, subscribe_webhooks):
        monkeypatch.setattr(instagram, function.__name__, function)


async def test_continue_with_instagram_creates_the_shop_and_signs_in(
    api: httpx2.AsyncClient, fake_instagram: None
) -> None:
    verifier, challenge = pkce_pair()
    start = await api.post(
        "/v1/auth/instagram/start",
        json={"code_challenge": challenge, "redirect_uri": APP_REDIRECT},
    )
    state = parse_qs(urlparse(start.json()["authorize_url"]).query)["state"][0]

    callback = await api.get("/oauth/instagram/callback", params={"code": "ig", "state": state})
    location = urlparse(callback.headers["location"])
    code = parse_qs(location.query)["code"][0]
    stolen = await api.post("/v1/auth/token", json={"code": code, "code_verifier": pkce_pair()[0]})
    tokens = await api.post("/v1/auth/token", json={"code": code, "code_verifier": verifier})
    replay = await api.post("/v1/auth/token", json={"code": code, "code_verifier": verifier})
    me = await api.get("/v1/me", headers=bearer(tokens.json()["access_token"]))

    assert start.status_code == 200
    assert (
        callback.status_code == 303
        and f"{location.scheme}://{location.netloc}{location.path}" == APP_REDIRECT
    )
    assert stolen.status_code == 401  # a code without the app's PKCE verifier is useless
    assert tokens.status_code == 200
    assert replay.status_code == 401  # one-time
    assert me.json()["merchant"]["name"] == "chennaibakes"
    assert me.json()["channels"][0]["username"] == "chennaibakes"
    assert me.json()["role"] == "owner"
    assert me.json()["onboarding_completed"] is False  # a new shop lands in onboarding


async def test_login_start_rejects_unknown_apps_and_bad_challenges(api: httpx2.AsyncClient) -> None:
    _, challenge = pkce_pair()

    unknown_app = await api.post(
        "/v1/auth/instagram/start",
        json={"code_challenge": challenge, "redirect_uri": "https://evil.test/callback"},
    )
    bad_challenge = await api.post(
        "/v1/auth/instagram/start", json={"code_challenge": "short", "redirect_uri": APP_REDIRECT}
    )

    assert unknown_app.status_code == 400
    assert bad_challenge.status_code == 400


@pytest.mark.parametrize(
    ("setting", "value"),
    [("instagram_app_id", ""), ("instagram_app_secret", ""), ("public_base_url", "http://x.test")],
)
async def test_login_start_refuses_when_instagram_cant_complete_it(
    api: httpx2.AsyncClient, monkeypatch: pytest.MonkeyPatch, setting: str, value: str
) -> None:
    monkeypatch.setattr(get_settings(), setting, value)

    start = await api.post(
        "/v1/auth/instagram/start",
        json={"code_challenge": pkce_pair()[1], "redirect_uri": APP_REDIRECT},
    )

    assert start.status_code == 400
    assert "Instagram sign-in" in start.json()["detail"]


async def test_onboarding_saves_each_step_and_finishing_writes_the_shop_profile(
    api: httpx2.AsyncClient, shop: ChannelConnection
) -> None:
    headers = bearer(await sign_in_as(shop.merchant_id))
    async with session_scope() as session:
        await shop_profile.save_profile(
            session, shop.merchant_id, "# Old\n## Saved answers\n- Bulk orders: ask the owner."
        )

    before = await api.get("/v1/onboarding", headers=headers)
    step = await api.put(
        "/v1/onboarding",
        headers=headers,
        json={"shop_name": "Sweet Crumbs", "answers": {"category": "home bakery"}},
    )
    done = await api.put(
        "/v1/onboarding",
        headers=headers,
        json={
            "shop_name": "Sweet Crumbs ",
            "answers": {
                "category": "home bakery",
                "area": "Anna Nagar",
                "city": "Chennai",
                "products": "cookies, brownies, custom cakes",
                "tone": "friendly",
                "emoji": True,
                "custom_orders": "2 days' notice, 50% advance",
            },
            "complete": True,
        },
    )
    me = await api.get("/v1/me", headers=headers)
    profile = await api.get("/v1/shop-profile", headers=headers)

    assert before.json()["completed"] is False
    assert before.json()["channels"][0]["username"] == "sweetcrumbs"
    assert step.json()["completed"] is False
    assert done.status_code == 200 and done.json()["completed"] is True
    assert me.json()["onboarding_completed"] is True
    assert me.json()["merchant"]["name"] == "Sweet Crumbs"
    content = profile.json()["content_md"]
    assert content.startswith("# Sweet Crumbs (home bakery, Anna Nagar, Chennai)")
    assert "- We sell: cookies, brownies, custom cakes" in content
    assert "- Custom orders: 2 days' notice, 50% advance" in content
    assert content.endswith("## Saved answers\n- Bulk orders: ask the owner.")  # kept


async def test_cancelled_instagram_login_returns_to_the_app_with_an_error(
    api: httpx2.AsyncClient,
) -> None:
    _, challenge = pkce_pair()
    start = await api.post(
        "/v1/auth/instagram/start",
        json={"code_challenge": challenge, "redirect_uri": APP_REDIRECT},
    )
    state = parse_qs(urlparse(start.json()["authorize_url"]).query)["state"][0]

    callback = await api.get(
        "/oauth/instagram/callback", params={"error": "access_denied", "state": state}
    )

    assert callback.status_code == 303
    assert "error" in parse_qs(urlparse(callback.headers["location"]).query)


async def test_api_requires_a_valid_token(api: httpx2.AsyncClient) -> None:
    missing = await api.get("/v1/today")
    forged = await api.get("/v1/today", headers=bearer("not-a-token"))

    assert missing.status_code == 401
    assert forged.status_code == 401


async def test_refresh_rotates_and_a_reused_token_ends_the_session(
    api: httpx2.AsyncClient, shop: ChannelConnection
) -> None:
    verifier, challenge = pkce_pair()
    async with session_scope() as session:
        user_id = await accounts.sign_in(
            session,
            provider="instagram",
            subject="17841400000000001",
            merchant_id=shop.merchant_id,
            display_name=None,
        )
        code = await accounts.create_login_code(session, user_id, challenge)
    first = (
        await api.post("/v1/auth/token", json={"code": code, "code_verifier": verifier})
    ).json()

    second = await api.post("/v1/auth/refresh", json={"refresh_token": first["refresh_token"]})
    reused = await api.post("/v1/auth/refresh", json={"refresh_token": first["refresh_token"]})
    after_reuse = await api.post(
        "/v1/auth/refresh", json={"refresh_token": second.json()["refresh_token"]}
    )

    assert second.status_code == 200
    assert second.json()["refresh_token"] != first["refresh_token"]
    assert reused.status_code == 401
    assert after_reuse.status_code == 401  # the whole session was revoked
    async with session_scope() as session:
        record = await session.scalar(select(Session))
    assert record is not None and record.revoked_at is not None


async def test_today_shows_the_stock_after_the_morning_update(
    api: httpx2.AsyncClient, shop: ChannelConnection
) -> None:
    token = await sign_in_as(shop.merchant_id)

    update = await api.put(
        "/v1/today/stock",
        headers=bearer(token),
        json={
            "lines": [
                {
                    "product": "Scoop cookie",
                    "variant": "Chocolate",
                    "price_minor": 6000,
                    "quantity": 10,
                },
                {"product": "Gift box", "price_minor": 1250, "currency": "USD", "quantity": 4},
            ]
        },
    )
    today = await api.get("/v1/today", headers=bearer(token))

    assert update.status_code == 200
    stock = {row["product"]: row for row in today.json()["stock"]}
    assert stock["Scoop cookie"]["available"] == 10
    assert stock["Gift box"]["currency"] == "USD"
    assert today.json()["agent_enabled"] is True


async def test_today_restock_counter_sale_and_sold_out_flow(
    api: httpx2.AsyncClient, shop: ChannelConnection
) -> None:
    token = await sign_in_as(shop.merchant_id)

    # 1. Set morning stock
    await api.put(
        "/v1/today/stock",
        headers=bearer(token),
        json={
            "lines": [
                {"product": "Brownie", "price_minor": 9000, "quantity": 10},
                {"product": "Croissant", "price_minor": 12000, "quantity": 5},
            ]
        },
    )
    today = (await api.get("/v1/today", headers=bearer(token))).json()
    stock_by_product = {row["product"]: row for row in today["stock"]}
    brownie_variant_id = stock_by_product["Brownie"]["variant_id"]
    croissant_variant_id = stock_by_product["Croissant"]["variant_id"]

    # 2. Restock Brownie by +5 (e.g. afternoon fresh bake)
    restock_res = await api.post(
        "/v1/today/restock",
        headers=bearer(token),
        json={"variant_id": brownie_variant_id, "quantity": 5},
    )
    assert restock_res.status_code == 200
    brownie_stock = {row["product"]: row for row in restock_res.json()["stock"]}["Brownie"]
    assert brownie_stock["opening"] == 10
    assert brownie_stock["restocked"] == 5
    assert brownie_stock["available"] == 15

    # 3. Record counter sale of 4 Brownies
    counter_res = await api.post(
        "/v1/today/counter-sale",
        headers=bearer(token),
        json={"variant_id": brownie_variant_id, "quantity": 4},
    )
    assert counter_res.status_code == 200
    assert counter_res.json()["quantity_sold"] == 4
    assert counter_res.json()["remaining_available"] == 11

    # Overselling at counter returns 409 Conflict
    conflict_res = await api.post(
        "/v1/today/counter-sale",
        headers=bearer(token),
        json={"variant_id": brownie_variant_id, "quantity": 20},
    )
    assert conflict_res.status_code == 409

    # 4. Mark Croissant as Sold Out
    sold_out_res = await api.post(
        "/v1/today/sold-out",
        headers=bearer(token),
        json={"variant_id": croissant_variant_id},
    )
    assert sold_out_res.status_code == 200
    croissant_stock = {row["product"]: row for row in sold_out_res.json()["stock"]}["Croissant"]
    assert croissant_stock["available"] == 0
    assert croissant_stock["counter_sales"] == 5


async def test_today_parse_stock_text_api(api: httpx2.AsyncClient) -> None:
    res = await api.post(
        "/v1/today/parse-stock-text",
        json={"text": "10 choc cookies 60rs, 5 brownies 90"},
    )
    assert res.status_code == 200
    lines = res.json()["lines"]
    assert len(lines) == 2
    assert lines[0] == {
        "product": "choc cookies",
        "variant": None,
        "price_minor": 6000,
        "currency": "INR",
        "quantity": 10,
    }
    assert lines[1] == {
        "product": "brownies",
        "variant": None,
        "price_minor": 9000,
        "currency": "INR",
        "quantity": 5,
    }

    # Invalid text returns 422
    bad_res = await api.post(
        "/v1/today/parse-stock-text",
        json={"text": "# Only comments"},
    )
    assert bad_res.status_code == 422


async def test_today_leftovers_and_rollover_api(
    api: httpx2.AsyncClient, shop: ChannelConnection
) -> None:
    from datetime import timedelta
    from app.modules.inventory import service as inventory
    from app.modules.inventory.schemas import OpeningStockLine

    token = await sign_in_as(shop.merchant_id)

    # 1. Establish stock yesterday
    async with session_scope() as session:
        merchant = await session.get(Merchant, shop.merchant_id)
        assert merchant is not None
        today_date = merchants.business_date(merchant)
        yesterday_date = today_date - timedelta(days=1)

        await inventory.set_opening_stock(
            session,
            merchant_id=shop.merchant_id,
            business_date=yesterday_date,
            lines=[
                OpeningStockLine("Almond Biscotti", None, 4500, 10),
                OpeningStockLine("Strawberry Tart", None, 8500, 4),
            ],
        )
        ledger = await inventory.day_ledger(session, shop.merchant_id, yesterday_date)
        biscotti_var_id = str(ledger[0].variant_id)
        tart_var_id = str(ledger[1].variant_id)

    # 2. GET /v1/today/leftovers
    leftovers_res = await api.get("/v1/today/leftovers", headers=bearer(token))
    assert leftovers_res.status_code == 200
    leftovers_data = leftovers_res.json()
    assert len(leftovers_data["leftovers"]) == 2
    leftover_items = {item["product"]: item for item in leftovers_data["leftovers"]}
    assert leftover_items["Almond Biscotti"]["leftover_quantity"] == 10
    assert leftover_items["Strawberry Tart"]["leftover_quantity"] == 4

    # 3. POST /v1/today/rollover - merchant chooses 4 out of 10 biscotti and 1 out of 4 tarts
    rollover_res = await api.post(
        "/v1/today/rollover",
        headers=bearer(token),
        json={
            "items": [
                {"variant_id": biscotti_var_id, "rollover_quantity": 4},
                {"variant_id": tart_var_id, "rollover_quantity": 1},
            ]
        },
    )
    assert rollover_res.status_code == 200
    res_data = rollover_res.json()
    assert res_data["rolled_count"] == 2
    today_stock = {row["product"]: row for row in res_data["today"]["stock"]}
    assert today_stock["Almond Biscotti"]["opening"] == 4
    assert today_stock["Strawberry Tart"]["opening"] == 1

    # 4. POST /v1/today/rollover - trying to roll over more than yesterday's available gives 409
    bad_rollover_res = await api.post(
        "/v1/today/rollover",
        headers=bearer(token),
        json={"items": [{"variant_id": biscotti_var_id, "rollover_quantity": 50}]},
    )
    assert bad_rollover_res.status_code == 409

    # 5. POST /v1/today/rollover/auto
    auto_res = await api.post("/v1/today/rollover/auto", headers=bearer(token))
    assert auto_res.status_code == 200


async def test_merchant_switches_the_agent_off_for_the_shop(
    api: httpx2.AsyncClient, shop: ChannelConnection
) -> None:
    token = await sign_in_as(shop.merchant_id)

    response = await api.patch("/v1/merchant", headers=bearer(token), json={"agent_enabled": False})

    async with session_scope() as session:
        merchant = await session.get(Merchant, shop.merchant_id)
    assert response.status_code == 200
    assert merchant is not None and merchant.agent_enabled is False


async def test_answering_a_question_relays_it_to_the_customer(
    api: httpx2.AsyncClient, shop: ChannelConnection, deferred_jobs: InMemoryConnector
) -> None:
    turn = await start_conversation("can you make a birthday cake for saturday?")
    async with session_scope() as session:
        question = await escalations.open_escalation(
            session,
            merchant_id=shop.merchant_id,
            conversation_id=turn.conversation_id,
            question="Customer wants a birthday cake for Saturday. What should I say?",
        )
    token = await sign_in_as(shop.merchant_id)

    listed = await api.get("/v1/questions", headers=bearer(token))
    answered = await api.post(
        f"/v1/questions/{question.id}/answer",
        headers=bearer(token),
        json={"answer": "Yes, 1kg is Rs 900, needs 2 days notice"},
    )
    again = await api.post(
        f"/v1/questions/{question.id}/answer", headers=bearer(token), json={"answer": "No"}
    )

    async with session_scope() as session:
        note = await session.scalar(select(Message).where(Message.sender == "system"))
    assert [q["id"] for q in listed.json()] == [str(question.id)]
    assert answered.json()["status"] == "answered"
    assert again.status_code == 409
    assert note is not None and "Yes, 1kg is Rs 900" in note.body
    assert [job["task_name"] for job in deferred_jobs.jobs.values()] == ["run_agent_turn"]


async def test_chats_list_messages_and_the_per_chat_switch(
    api: httpx2.AsyncClient, shop: ChannelConnection
) -> None:
    turn = await start_conversation("rendu cookie venum")
    token = await sign_in_as(shop.merchant_id)

    chats = await api.get("/v1/conversations", headers=bearer(token))
    messages = await api.get(
        f"/v1/conversations/{turn.conversation_id}/messages", headers=bearer(token)
    )
    switched = await api.put(
        f"/v1/conversations/{turn.conversation_id}/agent",
        headers=bearer(token),
        json={"active": False},
    )
    after = await api.get("/v1/conversations", headers=bearer(token))

    assert chats.json()[0]["last_message_body"] == "rendu cookie venum"
    assert [m["body"] for m in messages.json()] == ["rendu cookie venum"]
    assert switched.status_code == 200
    assert after.json()[0]["agent_active"] is False


async def test_one_shop_cannot_see_or_touch_another_shops_data(
    api: httpx2.AsyncClient, shop: ChannelConnection
) -> None:
    turn = await start_conversation()
    async with session_scope() as session:
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

    questions = await api.get("/v1/questions", headers=bearer(intruder))
    answer = await api.post(
        f"/v1/questions/{question.id}/answer", headers=bearer(intruder), json={"answer": "x"}
    )
    messages = await api.get(
        f"/v1/conversations/{turn.conversation_id}/messages", headers=bearer(intruder)
    )

    assert questions.json() == []
    assert answer.status_code == 404
    assert messages.status_code == 404


async def test_order_lifecycle_and_upi_payment_link_endpoints(
    api: httpx2.AsyncClient, shop: ChannelConnection, deferred_jobs: InMemoryConnector
) -> None:
    token = await sign_in_as(shop.merchant_id)

    # 1. Setup stock
    await api.put(
        "/v1/today/stock",
        headers=bearer(token),
        json={"lines": [{"product": "Sourdough", "price_minor": 15000, "quantity": 10}]},
    )
    turn = await start_conversation()
    async with session_scope() as session:
        merchant = await merchants.get_merchant(session, shop.merchant_id)
        day = merchants.business_date(merchant)
        conversation = await session.get(Conversation, turn.conversation_id)
        assert conversation is not None
        placed = await orders.place_order(
            session,
            merchant_id=shop.merchant_id,
            customer_id=conversation.customer_id,
            conversation_id=conversation.id,
            business_date=day,
            request=OrderRequest(
                lines=(OrderLineRequest("Sourdough", None, 2),), fulfilment="pickup"
            ),
            hold_minutes=15,
        )

    # 2. Get payment link (UPI for INR)
    link_res = await api.get(f"/v1/orders/{placed.order_id}/payment-link", headers=bearer(token))
    assert link_res.status_code == 200
    assert link_res.json()["payment_method"] == "upi"
    assert link_res.json()["payment_link"].startswith("upi://pay?")
    assert "am=300.00" in link_res.json()["payment_link"]

    # 3. Mark paid (merchant tap-to-confirm when receiving UPI alert)
    paid_res = await api.post(f"/v1/orders/{placed.order_id}/mark-paid", headers=bearer(token))
    assert paid_res.status_code == 200
    assert paid_res.json()["status"] == "paid"
    assert paid_res.json()["paid_at"] is not None

    # 4. Complete order (picked up or delivered)
    complete_res = await api.post(f"/v1/orders/{placed.order_id}/complete", headers=bearer(token))
    assert complete_res.status_code == 200
    assert complete_res.json()["status"] == "completed"

    # 5. Place another order and cancel it -> held stock returned
    async with session_scope() as session:
        placed2 = await orders.place_order(
            session,
            merchant_id=shop.merchant_id,
            customer_id=conversation.customer_id,
            conversation_id=conversation.id,
            business_date=day,
            request=OrderRequest(
                lines=(OrderLineRequest("Sourdough", None, 3),), fulfilment="pickup"
            ),
            hold_minutes=15,
        )

    cancel_res = await api.post(
        f"/v1/orders/{placed2.order_id}/cancel",
        headers=bearer(token),
        json={"reason": "Customer cancelled"},
    )
    assert cancel_res.status_code == 200
    assert cancel_res.json()["status"] == "cancelled"

    # 6. Verify HTTP exception responses
    # 400 on completing an unpaid/cancelled order
    bad_complete = await api.post(f"/v1/orders/{placed2.order_id}/complete", headers=bearer(token))
    assert bad_complete.status_code == 400
    assert "Order must be paid first" in bad_complete.json()["detail"]

    # 400 on cancelling an already completed order
    bad_cancel = await api.post(f"/v1/orders/{placed.order_id}/cancel", headers=bearer(token))
    assert bad_cancel.status_code == 400
    assert "Cannot cancel order with status 'completed'" in bad_cancel.json()["detail"]

    # 404 for non-existent order IDs
    fake_id = uuid.uuid4()
    assert (
        await api.post(f"/v1/orders/{fake_id}/mark-paid", headers=bearer(token))
    ).status_code == 404
    assert (
        await api.post(f"/v1/orders/{fake_id}/complete", headers=bearer(token))
    ).status_code == 404
    assert (
        await api.post(f"/v1/orders/{fake_id}/cancel", headers=bearer(token))
    ).status_code == 404
    assert (
        await api.get(f"/v1/orders/{fake_id}/payment-link", headers=bearer(token))
    ).status_code == 404
