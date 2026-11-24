"""New shops start with the assistant off, on the v2 engine, until the onboarding is finished."""

import uuid
from collections.abc import AsyncIterator
from urllib.parse import parse_qs, urlparse

import httpx2
import pytest

from app.core.db import session_scope
from app.main import create_app
from app.modules.channels import instagram
from app.modules.channels.models import ChannelConnection
from app.modules.channels.schemas import IncomingMessage
from app.modules.conversations import service as conversations
from app.modules.merchants import service as merchants
from app.modules.merchants.models import Merchant
from tests.integration.test_api import APP_REDIRECT, bearer, pkce_pair, sign_in_as

pytestmark = pytest.mark.anyio

NEW_ACCOUNT_ID = "17841477777777777"


@pytest.fixture
async def api(db: None) -> AsyncIterator[httpx2.AsyncClient]:
    transport = httpx2.ASGITransport(app=create_app())
    async with httpx2.AsyncClient(transport=transport, base_url="http://test") as client:
        yield client


@pytest.fixture
def new_instagram_account(monkeypatch: pytest.MonkeyPatch) -> None:
    async def exchange_code(**_: str) -> instagram.TokenGrant:
        return instagram.TokenGrant("short-token", None, instagram.SCOPES)

    async def exchange_long_lived(**_: str) -> instagram.TokenGrant:
        return instagram.TokenGrant("long-token", 5_184_000)

    async def fetch_account(**_: str) -> instagram.InstagramAccount:
        return instagram.InstagramAccount(NEW_ACCOUNT_ID, "chennaibakes")

    async def subscribe_webhooks(**_: str) -> None:
        return None

    for function in (exchange_code, exchange_long_lived, fetch_account, subscribe_webhooks):
        monkeypatch.setattr(instagram, function.__name__, function)


async def sign_up(api: httpx2.AsyncClient) -> str:
    """A first "Continue with Instagram": creates the shop; returns an access token."""
    verifier, challenge = pkce_pair()
    start = await api.post(
        "/v1/auth/instagram/start",
        json={"code_challenge": challenge, "redirect_uri": APP_REDIRECT},
    )
    state = parse_qs(urlparse(start.json()["authorize_url"]).query)["state"][0]
    callback = await api.get("/oauth/instagram/callback", params={"code": "ig", "state": state})
    code = parse_qs(urlparse(callback.headers["location"]).query)["code"][0]
    tokens = await api.post("/v1/auth/token", json={"code": code, "code_verifier": verifier})
    return tokens.json()["access_token"]


def onboarding(complete: bool) -> dict[str, object]:
    return {"shop_name": "Chennai Bakes", "answers": {"category": "bakery"}, "complete": complete}


async def test_a_shop_made_by_the_first_instagram_login_starts_off_on_v2(
    api: httpx2.AsyncClient, new_instagram_account: None
) -> None:
    token = await sign_up(api)

    me = await api.get("/v1/me", headers=bearer(token))
    async with session_scope() as session:
        merchant = await merchants.get_merchant(session, uuid.UUID(me.json()["merchant"]["id"]))
        # A customer writes before the owner has finished setting up: no reply is queued.
        turn = await conversations.handle_incoming(
            session,
            IncomingMessage(
                channel="instagram",
                shop_account_id=NEW_ACCOUNT_ID,
                customer_id="7000000000000555",
                message_id="m-early",
                text="hi, do you have cakes?",
            ),
        )

    assert me.json()["merchant"]["agent_enabled"] is False
    assert (merchant.agent_enabled, merchant.agent_engine) == (False, "v2")
    assert turn is None


async def test_finishing_the_onboarding_switches_the_assistant_on(
    api: httpx2.AsyncClient, new_instagram_account: None
) -> None:
    headers = bearer(await sign_up(api))

    step = await api.put("/v1/onboarding", headers=headers, json=onboarding(complete=False))
    after_step = (await api.get("/v1/me", headers=headers)).json()["merchant"]["agent_enabled"]
    done = await api.put("/v1/onboarding", headers=headers, json=onboarding(complete=True))
    after_done = (await api.get("/v1/me", headers=headers)).json()["merchant"]["agent_enabled"]

    assert step.status_code == 200 and after_step is False
    assert done.status_code == 200 and done.json()["completed"] is True
    assert after_done is True


async def test_saving_a_finished_onboarding_again_keeps_the_owners_switch(
    api: httpx2.AsyncClient, new_instagram_account: None
) -> None:
    headers = bearer(await sign_up(api))
    await api.put("/v1/onboarding", headers=headers, json=onboarding(complete=True))
    await api.patch("/v1/merchant", headers=headers, json={"agent_enabled": False})

    # Settings saves the answers again later, with the setup already finished.
    again = await api.put("/v1/onboarding", headers=headers, json=onboarding(complete=True))
    me = await api.get("/v1/me", headers=headers)

    assert again.status_code == 200
    assert me.json()["merchant"]["agent_enabled"] is False


async def test_existing_shops_keep_their_assistant_and_engine(
    api: httpx2.AsyncClient, shop: ChannelConnection
) -> None:
    token = await sign_in_as(shop.merchant_id)

    me = await api.get("/v1/me", headers=bearer(token))
    async with session_scope() as session:
        merchant = await merchants.get_merchant(session, shop.merchant_id)

    assert me.json()["merchant"]["agent_enabled"] is True
    assert merchant.agent_engine == "v1"


async def test_the_database_defaults_are_off_and_v2(db: None) -> None:
    async with session_scope() as session:
        created = await merchants.create_merchant(session, name="CLI shop")
        bare = Merchant(name="Inserted directly")
        session.add(bare)
        await session.flush()
        await session.refresh(bare)

    assert (created.agent_enabled, created.agent_engine) == (False, "v2")
    assert (bare.agent_enabled, bare.agent_engine) == (False, "v2")
