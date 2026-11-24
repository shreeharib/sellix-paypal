"""A refresh token rotated less than 2 minutes ago still works once more (a lost response or two
refreshes at once); after that, reusing it ends the session."""

import asyncio
from collections.abc import AsyncIterator
from datetime import timedelta

import httpx2
import pytest
from sqlalchemy import select, update

from app.core.db import session_scope
from app.main import create_app
from app.modules.accounts import service as accounts
from app.modules.accounts.models import Session
from app.modules.channels.models import ChannelConnection
from tests.integration.test_api import bearer, pkce_pair

pytestmark = pytest.mark.anyio


@pytest.fixture
async def api(db: None) -> AsyncIterator[httpx2.AsyncClient]:
    transport = httpx2.ASGITransport(app=create_app())
    async with httpx2.AsyncClient(transport=transport, base_url="http://test") as client:
        yield client


async def signed_in(api: httpx2.AsyncClient, shop: ChannelConnection) -> dict[str, str]:
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
    return (await api.post("/v1/auth/token", json={"code": code, "code_verifier": verifier})).json()


async def refresh(api: httpx2.AsyncClient, token: str) -> httpx2.Response:
    return await api.post("/v1/auth/refresh", json={"refresh_token": token})


async def rotated_minutes_ago(minutes: float) -> None:
    async with session_scope() as session:
        await session.execute(
            update(Session).values(
                refresh_rotated_at=Session.refresh_rotated_at - timedelta(minutes=minutes)
            )
        )


async def test_a_lost_refresh_response_can_be_retried_with_the_old_token(
    api: httpx2.AsyncClient, shop: ChannelConnection
) -> None:
    first = await signed_in(api, shop)

    lost = await refresh(api, first["refresh_token"])  # the phone never got this answer
    retried = await refresh(api, first["refresh_token"])
    me = await api.get("/v1/me", headers=bearer(retried.json()["access_token"]))
    later = await refresh(api, retried.json()["refresh_token"])

    assert lost.status_code == 200
    assert retried.status_code == 200
    # The retry carries the refresh token the lost answer had (the session's current one).
    assert retried.json()["refresh_token"] == lost.json()["refresh_token"]
    assert retried.json()["refresh_token"] != first["refresh_token"]
    assert me.status_code == 200
    assert later.status_code == 200  # the session carries on
    async with session_scope() as session:
        record = await session.scalar(select(Session))
    assert record is not None and record.revoked_at is None


async def test_two_refreshes_at_once_both_succeed_and_agree(
    api: httpx2.AsyncClient, shop: ChannelConnection
) -> None:
    first = await signed_in(api, shop)

    one, two = await asyncio.gather(
        refresh(api, first["refresh_token"]), refresh(api, first["refresh_token"])
    )
    # Whichever answer the app keeps, its refresh token still works.
    next_one = await refresh(api, one.json()["refresh_token"])

    assert (one.status_code, two.status_code) == (200, 200)
    assert one.json()["refresh_token"] == two.json()["refresh_token"]
    assert next_one.status_code == 200


async def test_reusing_a_rotated_token_after_two_minutes_still_ends_the_session(
    api: httpx2.AsyncClient, shop: ChannelConnection
) -> None:
    first = await signed_in(api, shop)
    second = await refresh(api, first["refresh_token"])
    await rotated_minutes_ago(2.5)

    reused = await refresh(api, first["refresh_token"])
    current = await refresh(api, second.json()["refresh_token"])

    assert reused.status_code == 401
    assert current.status_code == 401  # the whole session was revoked
    async with session_scope() as session:
        record = await session.scalar(select(Session))
    assert record is not None and record.revoked_at is not None
    assert record.refresh_token_encrypted is None


async def test_a_signed_out_session_gets_no_grace(
    api: httpx2.AsyncClient, shop: ChannelConnection
) -> None:
    first = await signed_in(api, shop)
    second = (await refresh(api, first["refresh_token"])).json()

    await api.post("/v1/auth/logout", headers=bearer(second["access_token"]))
    reused = await refresh(api, first["refresh_token"])

    assert reused.status_code == 401
    async with session_scope() as session:
        record = await session.scalar(select(Session))
    assert record is not None and record.refresh_token_encrypted is None


async def test_unknown_tokens_are_refused(api: httpx2.AsyncClient, db: None) -> None:
    assert (await refresh(api, "not-a-token")).status_code == 401


async def test_the_copy_of_the_refresh_token_is_forgotten_after_the_grace(
    api: httpx2.AsyncClient, shop: ChannelConnection
) -> None:
    tokens = await signed_in(api, shop)
    first = await refresh(api, tokens["refresh_token"])
    assert first.status_code == 200

    async with session_scope() as session:  # still within the grace: kept
        assert await accounts.forget_rotated_refresh_tokens(session) == 0
    await rotated_minutes_ago(3)
    async with session_scope() as session:
        assert await accounts.forget_rotated_refresh_tokens(session) == 1
        copies = list(
            await session.scalars(
                select(Session.refresh_token_encrypted).where(
                    Session.refresh_token_encrypted.is_not(None)
                )
            )
        )
    assert copies == []
    again = await refresh(api, first.json()["refresh_token"])  # the session still works
    assert again.status_code == 200
