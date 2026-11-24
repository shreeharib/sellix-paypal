"""Deleting a shop (DELETE /v1/shop, and Meta's data-deletion callback), and the public privacy
and data-deletion pages."""

import base64
import hashlib
import hmac
import json
import time
import uuid
from collections.abc import AsyncIterator

import httpx2
import jwt
import pytest
from procrastinate.testing import InMemoryConnector
from sqlalchemy import func, select, text, update

from app.core.db import session_scope
from app.main import create_app
from app.modules.accounts.models import MerchantMember, Session, User
from app.modules.agent import service as agent
from app.modules.channels.models import ChannelConnection
from app.modules.conversations import outbox
from app.modules.conversations.models import Conversation
from app.modules.escalations import service as escalations
from app.modules.merchants import service as merchants
from app.modules.merchants.models import Merchant
from app.modules.orders import service as orders
from app.modules.orders.schemas import OrderLineRequest, OrderRequest
from tests.integration.factories import SHOP_ACCOUNT_ID, start_conversation
from tests.integration.test_api import bearer, sign_in_as

pytestmark = pytest.mark.anyio

APP_SECRET = "test-instagram-app-secret"  # tests/conftest.py


@pytest.fixture
async def api(db: None) -> AsyncIterator[httpx2.AsyncClient]:
    transport = httpx2.ASGITransport(app=create_app())
    async with httpx2.AsyncClient(transport=transport, base_url="http://test") as client:
        yield client


async def fill_the_shop(shop: ChannelConnection) -> None:
    """Products and stock (v2_shop), a chat, an order, a question, a saved rule, an outbox row."""
    turn = await start_conversation()
    async with session_scope() as session:
        merchant = await merchants.get_merchant(session, shop.merchant_id)
        conversation = await session.get(Conversation, turn.conversation_id)
        assert conversation is not None
        await orders.place_order(
            session,
            merchant_id=shop.merchant_id,
            customer_id=conversation.customer_id,
            conversation_id=conversation.id,
            business_date=merchants.business_date(merchant),
            request=OrderRequest(
                lines=(OrderLineRequest("Scoop cookie", "Chocolate", 2),), fulfilment="pickup"
            ),
            hold_minutes=15,
        )
        question = await escalations.open_escalation(
            session,
            merchant_id=shop.merchant_id,
            conversation_id=turn.conversation_id,
            question="Eggless?",
        )
        await outbox.queue_text(
            session, conversation_id=turn.conversation_id, text="Yes!", key="reply-1"
        )
    await agent.save_rule(
        merchant_id=shop.merchant_id,
        question="Eggless?",
        answer="Yes, all of them",
        source_escalation_id=question.id,
    )


async def rows_left(merchant_id: uuid.UUID) -> dict[str, int]:
    """Rows still pointing at this shop, in every table that has a merchant_id column."""
    async with session_scope() as session:
        tables = list(
            await session.scalars(
                text(
                    "select table_name from information_schema.columns "
                    "where table_schema = 'public' and column_name = 'merchant_id'"
                )
            )
        )
        left: dict[str, int] = {}
        for table in tables:
            count = await session.scalar(
                text(f'select count(*) from "{table}" where merchant_id = :id'),  # noqa: S608
                {"id": merchant_id},
            )
            if count:
                left[table] = int(count)
    return left


def signed_request(user_id: str, secret: str = APP_SECRET) -> str:
    def encode(raw: bytes) -> str:
        return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()

    payload = encode(
        json.dumps(
            {"algorithm": "HMAC-SHA256", "issued_at": int(time.time()), "user_id": user_id}
        ).encode()
    )
    signature = encode(hmac.new(secret.encode(), payload.encode(), hashlib.sha256).digest())
    return f"{signature}.{payload}"


async def test_the_owner_deletes_the_shop_and_everything_in_it(
    api: httpx2.AsyncClient, v2_shop: ChannelConnection, deferred_jobs: InMemoryConnector
) -> None:
    await fill_the_shop(v2_shop)
    assert await rows_left(v2_shop.merchant_id)  # the check below would see leftovers
    owner = await sign_in_as(v2_shop.merchant_id)
    async with session_scope() as session:
        other = await merchants.create_merchant(session, name="Other shop")
    other_token = await sign_in_as(other.id, subject="17841400000009999")

    deleted = await api.request(
        "DELETE", "/v1/shop", headers=bearer(owner), json={"confirm_name": "Sweet Crumbs"}
    )
    me = await api.get("/v1/me", headers=bearer(owner))
    other_me = await api.get("/v1/me", headers=bearer(other_token))

    assert deleted.status_code == 204
    assert await rows_left(v2_shop.merchant_id) == {}
    async with session_scope() as session:
        assert await session.get(Merchant, v2_shop.merchant_id) is None
        owner_id = uuid.UUID(jwt.decode(owner, options={"verify_signature": False})["sub"])
        assert await session.get(User, owner_id) is None  # sessions and identities go with it
        assert (
            await session.scalar(
                select(func.count()).select_from(Session).where(Session.user_id == owner_id)
            )
            == 0
        )
    assert me.status_code == 403  # the access token no longer reaches a shop
    assert other_me.status_code == 200
    assert other_me.json()["merchant"]["name"] == "Other shop"


async def test_a_wrong_name_deletes_nothing(
    api: httpx2.AsyncClient, shop: ChannelConnection
) -> None:
    owner = await sign_in_as(shop.merchant_id)

    wrong = await api.request(
        "DELETE", "/v1/shop", headers=bearer(owner), json={"confirm_name": "sweet crumbs!"}
    )
    missing = await api.request("DELETE", "/v1/shop", headers=bearer(owner), json={})

    assert wrong.status_code == 422
    assert "name" in wrong.json()["detail"]
    assert missing.status_code == 422
    async with session_scope() as session:
        assert await session.get(Merchant, shop.merchant_id) is not None


async def test_staff_cannot_delete_the_shop(
    api: httpx2.AsyncClient, shop: ChannelConnection
) -> None:
    staff = await sign_in_as(shop.merchant_id, subject="17841400000005555")
    staff_id = uuid.UUID(jwt.decode(staff, options={"verify_signature": False})["sub"])
    async with session_scope() as session:
        await session.execute(
            update(MerchantMember).where(MerchantMember.user_id == staff_id).values(role="staff")
        )

    response = await api.request(
        "DELETE", "/v1/shop", headers=bearer(staff), json={"confirm_name": "Sweet Crumbs"}
    )

    assert response.status_code == 403
    async with session_scope() as session:
        assert await session.get(Merchant, shop.merchant_id) is not None


async def test_metas_data_deletion_callback_deletes_the_shop_of_that_account(
    api: httpx2.AsyncClient, v2_shop: ChannelConnection, deferred_jobs: InMemoryConnector
) -> None:
    await fill_the_shop(v2_shop)

    answer = await api.post(
        "/auth/instagram/data-deletion", data={"signed_request": signed_request(SHOP_ACCOUNT_ID)}
    )
    body = answer.json()
    status = await api.get("/data-deletion", params={"code": body["confirmation_code"]})

    assert answer.status_code == 200
    assert set(body) == {"url", "confirmation_code"}
    assert body["url"] == f"https://sellix.test/data-deletion?code={body['confirmation_code']}"
    assert await rows_left(v2_shop.merchant_id) == {}
    assert status.status_code == 200
    assert body["confirmation_code"] in status.text
    assert "were deleted" in status.text


async def test_the_callback_also_finds_the_shop_by_its_app_scoped_instagram_id(
    api: httpx2.AsyncClient, v2_shop: ChannelConnection, deferred_jobs: InMemoryConnector
) -> None:
    """Meta's callback most likely names the app-scoped id (`id` from /me), not the professional
    account id webhooks use; sign-in now keeps both."""
    async with session_scope() as session:
        connection = await session.get(ChannelConnection, v2_shop.id)
        assert connection is not None
        connection.app_user_id = "9876543210123456"
    await fill_the_shop(v2_shop)

    answer = await api.post(
        "/auth/instagram/data-deletion", data={"signed_request": signed_request("9876543210123456")}
    )

    assert answer.status_code == 200
    assert await rows_left(v2_shop.merchant_id) == {}


async def test_the_callback_refuses_a_forged_request_and_answers_for_unknown_accounts(
    api: httpx2.AsyncClient, shop: ChannelConnection
) -> None:
    forged = await api.post(
        "/auth/instagram/data-deletion",
        data={"signed_request": signed_request(SHOP_ACCOUNT_ID, secret="not-our-secret")},
    )
    garbage = await api.post("/auth/instagram/data-deletion", data={"signed_request": "abc"})
    unknown = await api.post(
        "/v1/auth/instagram/data-deletion",
        data={"signed_request": signed_request("17841499999990000")},
    )
    status = await api.get("/data-deletion", params={"code": unknown.json()["confirmation_code"]})
    no_such = await api.get("/data-deletion", params={"code": "NOPE"})

    assert forged.status_code == 400 and garbage.status_code == 400
    async with session_scope() as session:
        assert await session.get(Merchant, shop.merchant_id) is not None
    assert unknown.status_code == 200
    assert "nothing to delete" in status.text
    assert no_such.status_code == 404


async def test_the_privacy_and_data_deletion_pages_are_public(api: httpx2.AsyncClient) -> None:
    privacy = await api.get("/privacy")
    how_to = await api.get("/data-deletion")

    for page in (privacy, how_to):
        assert page.status_code == 200
        assert page.headers["content-type"].startswith("text/html")
        assert "CONTACT EMAIL" in page.text  # the operator still has to fill it in
    assert "the sellix operator" in privacy.text
    assert "Instagram" in privacy.text and "orders" in privacy.text
    assert "AI model provider" in privacy.text
    assert "Delete shop" in how_to.text
