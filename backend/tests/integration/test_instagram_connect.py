import uuid
from datetime import UTC, datetime, timedelta
from urllib.parse import parse_qs, urlparse

import pytest
from sqlalchemy import select

from app.core import crypto, signing
from app.core.db import session_scope
from app.modules.channels import instagram
from app.modules.channels import service as channels
from app.modules.channels.models import ChannelConnection
from app.modules.merchants.models import Merchant

pytestmark = pytest.mark.anyio


@pytest.fixture
def fake_instagram(monkeypatch: pytest.MonkeyPatch) -> list[str]:
    """Replaces Instagram's OAuth endpoints; returns the calls made, in order."""
    calls: list[str] = []

    async def exchange_code(**_: str) -> instagram.TokenGrant:
        calls.append("exchange_code")
        return instagram.TokenGrant("short-token", None, instagram.SCOPES)

    async def exchange_long_lived(**_: str) -> instagram.TokenGrant:
        calls.append("exchange_long_lived")
        return instagram.TokenGrant("long-token", 5_184_000)

    async def fetch_account(**_: str) -> instagram.InstagramAccount:
        calls.append("fetch_account")
        return instagram.InstagramAccount("17841499999999999", "sweetcrumbs")

    async def subscribe_webhooks(**_: str) -> None:
        calls.append("subscribe_webhooks")

    async def refresh_long_lived(**_: str) -> instagram.TokenGrant:
        calls.append("refresh_long_lived")
        return instagram.TokenGrant("refreshed-token", 5_184_000)

    for function in (
        exchange_code,
        exchange_long_lived,
        fetch_account,
        subscribe_webhooks,
        refresh_long_lived,
    ):
        monkeypatch.setattr(instagram, function.__name__, function)
    return calls


async def new_merchant(name: str = "Sweet Crumbs") -> uuid.UUID:
    async with session_scope() as session:
        merchant = Merchant(name=name)
        session.add(merchant)
        await session.flush()
        return merchant.id


def state_from(url: str) -> str:
    return parse_qs(urlparse(url).query)["state"][0]


async def test_connecting_stores_an_encrypted_long_lived_token(
    db: None, fake_instagram: list[str]
) -> None:
    merchant_id = await new_merchant()
    state = state_from(channels.instagram_authorize_url(merchant_id))

    async with session_scope() as session:
        await channels.complete_instagram_oauth(session, code="auth-code", state=state)

    async with session_scope() as session:
        connection = await session.scalar(select(ChannelConnection))
    assert connection is not None
    assert (connection.merchant_id, connection.external_account_id) == (
        merchant_id,
        "17841499999999999",
    )
    assert "long-token" not in connection.access_token_encrypted
    assert crypto.decrypt(connection.access_token_encrypted) == "long-token"
    assert connection.token_expires_at is not None
    assert fake_instagram == [
        "exchange_code",
        "exchange_long_lived",
        "fetch_account",
        "subscribe_webhooks",
    ]


async def test_forged_or_foreign_state_is_rejected(db: None, fake_instagram: list[str]) -> None:
    other_purpose = signing.sign({"purpose": "something_else", "merchant_id": "x"}, ttl_seconds=60)

    for state in ("not-a-signed-value", other_purpose):
        async with session_scope() as session:
            with pytest.raises(channels.ChannelConnectError):
                await channels.complete_instagram_oauth(session, code="c", state=state)
    assert fake_instagram == []


async def test_account_already_connected_to_another_shop_is_rejected(
    db: None, fake_instagram: list[str]
) -> None:
    first, second = await new_merchant("First"), await new_merchant("Second")
    async with session_scope() as session:
        await channels.complete_instagram_oauth(
            session, code="c", state=state_from(channels.instagram_authorize_url(first))
        )

    async with session_scope() as session:
        with pytest.raises(channels.ChannelConnectError, match="another shop"):
            await channels.complete_instagram_oauth(
                session, code="c", state=state_from(channels.instagram_authorize_url(second))
            )


async def test_tokens_close_to_expiry_are_refreshed(db: None, fake_instagram: list[str]) -> None:
    merchant_id = await new_merchant()
    now = datetime.now(UTC)
    async with session_scope() as session:
        session.add(
            ChannelConnection(
                merchant_id=merchant_id,
                channel="instagram",
                external_account_id="17841400000000005",
                access_token_encrypted=crypto.encrypt("old-token"),
                token_expires_at=now + timedelta(days=3),
                token_refreshed_at=now - timedelta(days=57),
            )
        )

    async with session_scope() as session:
        refreshed = await channels.refresh_expiring_tokens(session, within=timedelta(days=15))

    async with session_scope() as session:
        connection = await session.scalar(select(ChannelConnection))
    assert refreshed == 1
    assert connection is not None
    assert crypto.decrypt(connection.access_token_encrypted) == "refreshed-token"
    assert connection.token_expires_at is not None
    assert connection.token_expires_at > now + timedelta(days=50)
