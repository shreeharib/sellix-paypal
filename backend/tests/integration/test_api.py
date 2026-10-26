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
from app.modules.conversations.models import Message
from app.modules.escalations import service as escalations
from app.modules.merchants.models import Merchant
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


async def test_merchant_switches_the_agent_off_for_the_shop(
    api: httpx2.AsyncClient, shop: ChannelConnection
) -> None:
    token = await sign_in_as(shop.merchant_id)

    response = await api.patch("/v1/merchant", headers=bearer(token), json={"agent_enabled": False})

    async with session_scope() as session:
        merchant = await session.get(Merchant, shop.merchant_id)
    assert response.status_code == 200
    assert merchant is not None and merchant.agent_enabled is False


async def test_merchant_sets_and_clears_opening_hours(
    api: httpx2.AsyncClient, shop: ChannelConnection
) -> None:
    token = await sign_in_as(shop.merchant_id)
    hours = {
        "week": {"tue": [{"opens": "09:00", "closes": "20:00"}]},
        "closed_dates": ["2026-11-01"],
    }

    saved = await api.patch("/v1/merchant", headers=bearer(token), json={"opening_hours": hours})
    renamed = await api.patch("/v1/merchant", headers=bearer(token), json={"name": "Crumbs"})
    bad = await api.patch(
        "/v1/merchant",
        headers=bearer(token),
        json={"opening_hours": {"week": {"tue": [{"opens": "09:00", "closes": "09:00"}]}}},
    )
    cleared = await api.patch("/v1/merchant", headers=bearer(token), json={"opening_hours": None})

    assert saved.status_code == 200
    assert saved.json()["opening_hours"] == {
        "week": {"tue": [{"opens": "09:00:00", "closes": "20:00:00"}]},
        "closed_dates": ["2026-11-01"],
    }
    assert renamed.json()["opening_hours"] == saved.json()["opening_hours"]  # left alone
    assert bad.status_code == 422
    assert cleared.status_code == 200 and cleared.json()["opening_hours"] is None


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
