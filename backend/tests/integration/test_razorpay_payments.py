"""Razorpay end to end: a shop connects its account, a customer gets a link and pays, refunds.

Razorpay itself is faked (fake_razorpay.py) at the HTTP level; the database, orders, payments,
webhook inbox, jobs and the API are real.
"""

import json
import time
import uuid
from collections.abc import AsyncIterator
from datetime import UTC, datetime, timedelta
from urllib.parse import urlencode

import httpx2
import pytest
from procrastinate.testing import InMemoryConnector
from sqlalchemy import select, text

from app.core.config import get_settings
from app.core.db import session_scope
from app.main import create_app
from app.modules.channels.models import ChannelConnection
from app.modules.conversations.models import Conversation, Message
from app.modules.conversations.tasks import notify_failed_payment
from app.modules.inventory import service as inventory
from app.modules.inventory.schemas import OpeningStockLine
from app.modules.merchants import service as merchants
from app.modules.orders import service as orders
from app.modules.orders.models import Order, RefundRequest
from app.modules.orders.schemas import (
    OrderLineRequest,
    OrderRequest,
    PlacedOrder,
    QuoteRefused,
    SavedQuote,
)
from app.modules.payments import service as payments
from app.modules.payments.models import Payment, PaymentAccount
from app.modules.shop_profile import service as shop_profile
from app.modules.shop_profile.schemas import OnboardingAnswers
from app.webhooks.models import WebhookEvent
from app.webhooks.tasks import process_razorpay_event
from tests.conftest import RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET
from tests.integration.factories import start_conversation
from tests.integration.fake_razorpay import FakeRazorpay
from tests.integration.test_api import bearer, sign_in_as

pytestmark = pytest.mark.anyio


@pytest.fixture
async def api(db: None) -> AsyncIterator[httpx2.AsyncClient]:
    transport = httpx2.ASGITransport(app=create_app())
    async with httpx2.AsyncClient(transport=transport, base_url="http://test") as client:
        yield client


@pytest.fixture
async def stocked_shop(shop: ChannelConnection) -> ChannelConnection:
    """Sweet Crumbs with 20 brownies at ₹90."""
    async with session_scope() as session:
        merchant = await merchants.get_merchant(session, shop.merchant_id)
        await inventory.set_opening_stock(
            session,
            merchant_id=shop.merchant_id,
            business_date=merchants.business_date(merchant),
            lines=[OpeningStockLine("Brownie", None, 9000, 20)],
        )
    return shop


@pytest.fixture
async def connected(
    stocked_shop: ChannelConnection, fake_razorpay: FakeRazorpay
) -> ChannelConnection:
    """The shop has connected its own Razorpay account (test keys)."""
    await payments.connect_account(
        stocked_shop.merchant_id, key_id=RAZORPAY_KEY_ID, key_secret=RAZORPAY_KEY_SECRET
    )
    return stocked_shop


async def place(shop: ChannelConnection, quantity: int = 2) -> PlacedOrder:
    """A customer's ₹90 x quantity brownie order, placed and unpaid."""
    turn = await start_conversation(message_id=f"m-{uuid.uuid4()}")
    async with session_scope() as session:
        merchant = await merchants.get_merchant(session, shop.merchant_id)
        conversation = await session.get(Conversation, turn.conversation_id)
        assert conversation is not None
        return await orders.place_order(
            session,
            merchant_id=shop.merchant_id,
            customer_id=conversation.customer_id,
            conversation_id=conversation.id,
            business_date=merchants.business_date(merchant),
            request=OrderRequest(lines=(OrderLineRequest("Brownie", None, quantity),)),
            hold_minutes=15,
        )


async def link_for(placed: PlacedOrder) -> payments.Checkout:
    return await payments.start_checkout(placed, shop_name="Sweet Crumbs")


async def order_of(order_id: uuid.UUID) -> Order:
    async with session_scope() as session:
        order = await session.get(Order, order_id)
    assert order is not None
    return order


async def payment_rows(order_id: uuid.UUID) -> list[Payment]:
    async with session_scope() as session:
        return list(
            await session.scalars(
                select(Payment).where(Payment.order_id == order_id).order_by(Payment.created_at)
            )
        )


async def paid_order(shop: ChannelConnection, fake: FakeRazorpay) -> PlacedOrder:
    placed = await place(shop)
    await link_for(placed)
    link = fake.only_link() if len(fake.links) == 1 else list(fake.links.values())[-1]
    fake.pay(link["id"])
    result = await payments.verify_and_record(link["id"])
    assert result is not None and not isinstance(result, payments.PaymentFailed)
    assert result.outcome == "paid"
    return placed


# -- connecting the shop's account ----------------------------------------------------------------


async def test_connecting_checks_the_keys_with_razorpay_and_stores_the_secret_encrypted(
    stocked_shop: ChannelConnection, fake_razorpay: FakeRazorpay
) -> None:
    merchant_id = stocked_shop.merchant_id
    with pytest.raises(payments.AccountKeysRejected, match="rzp_test_"):
        await payments.connect_account(merchant_id, key_id="pk_live_123", key_secret="x" * 20)
    with pytest.raises(payments.AccountKeysRejected, match="didn't accept"):
        await payments.connect_account(
            merchant_id, key_id=RAZORPAY_KEY_ID, key_secret="WrongSecret12345678"
        )
    fake_razorpay.fail_next = [(503, "down")] * 3
    with pytest.raises(payments.ProviderUnreachable):
        await payments.connect_account(
            merchant_id, key_id=RAZORPAY_KEY_ID, key_secret=RAZORPAY_KEY_SECRET
        )
    assert (await payments.account_status(merchant_id)).source == "none"

    status = await payments.connect_account(
        merchant_id, key_id=f" {RAZORPAY_KEY_ID} ", key_secret=RAZORPAY_KEY_SECRET
    )

    assert status.source == "own" and status.payments_ready
    assert status.account is not None and status.account.mode == "test"
    assert status.account.webhook_url.startswith("https://sellix.test/webhooks/razorpay/")
    async with session_scope() as session:
        stored = await session.scalar(
            select(PaymentAccount).where(PaymentAccount.merchant_id == merchant_id)
        )
    assert stored is not None and stored.key_id == RAZORPAY_KEY_ID
    assert RAZORPAY_KEY_SECRET not in stored.key_secret_encrypted

    again = await payments.connect_account(
        merchant_id, key_id=RAZORPAY_KEY_ID, key_secret=RAZORPAY_KEY_SECRET
    )
    assert again.account is not None
    assert again.account.webhook_url == status.account.webhook_url  # no new webhook set-up
    assert again.account.webhook_secret == status.account.webhook_secret


async def test_without_an_account_there_is_no_razorpay_link(
    stocked_shop: ChannelConnection, fake_razorpay: FakeRazorpay
) -> None:
    placed = await place(stocked_shop)
    with pytest.raises(payments.PaymentUnavailable):
        await link_for(placed)
    assert fake_razorpay.links == {}


async def test_the_servers_shared_keys_are_used_only_outside_production(
    stocked_shop: ChannelConnection, fake_razorpay: FakeRazorpay, monkeypatch: pytest.MonkeyPatch
) -> None:
    settings = get_settings()
    monkeypatch.setattr(settings, "razorpay_key_id", RAZORPAY_KEY_ID)
    monkeypatch.setattr(settings, "razorpay_key_secret", RAZORPAY_KEY_SECRET)
    assert (await payments.account_status(stocked_shop.merchant_id)).source == "shared"

    monkeypatch.setattr(settings, "app_env", "prod")
    assert (await payments.account_status(stocked_shop.merchant_id)).source == "none"
    monkeypatch.setattr(settings, "razorpay_shared_account_in_prod", True)
    assert (await payments.account_status(stocked_shop.merchant_id)).source == "shared"


# -- the payment link ---------------------------------------------------------------------------


async def test_an_order_gets_one_razorpay_link_that_outlives_razorpays_minimum(
    connected: ChannelConnection, fake_razorpay: FakeRazorpay
) -> None:
    placed = await place(connected)

    checkout = await link_for(placed)
    resent = await link_for(placed)  # the customer asks for the link again

    link = fake_razorpay.only_link()
    assert checkout.url == resent.url == link["short_url"] and checkout.provider == "razorpay"
    assert link["amount"] == 18000 and link["currency"] == "INR"
    assert link["expire_by"] >= time.time() + 15 * 60
    assert link["callback_url"] == "https://sellix.test/payments/razorpay/return"
    assert link["notes"]["sellix_order_id"] == str(placed.order_id)
    [row] = await payment_rows(placed.order_id)
    assert row.provider == "razorpay" and row.status == "created" and row.method is None
    assert row.provider_order_id == link["id"] and row.provider_account == RAZORPAY_KEY_ID
    assert link["notes"]["sellix_payment_id"] == str(row.id)


async def test_paid_only_once_razorpay_says_the_link_is_paid(
    connected: ChannelConnection, fake_razorpay: FakeRazorpay
) -> None:
    placed = await place(connected)
    await link_for(placed)
    link = fake_razorpay.only_link()

    assert await payments.verify_and_record(link["id"]) is None  # not paid yet
    assert (await order_of(placed.order_id)).status == "awaiting_payment"

    payment_id = fake_razorpay.pay(link["id"], method="card", fee=425)
    result = await payments.verify_and_record(link["id"])
    replay = await payments.verify_and_record(link["id"])

    assert result is not None and not isinstance(result, payments.PaymentFailed)
    assert result.outcome == "paid" and replay is None
    order = await order_of(placed.order_id)
    assert order.status == "paid" and order.amount_paid_minor == 18000
    [row] = await payment_rows(placed.order_id)
    assert row.status == "completed" and row.provider_capture_id == payment_id
    assert row.method == "card" and row.fee_minor == 425
    assert row.provider_checkout_id == link["order_id"]


async def test_a_link_that_razorpay_reports_for_another_amount_never_pays_the_order(
    connected: ChannelConnection, fake_razorpay: FakeRazorpay
) -> None:
    placed = await place(connected)
    await link_for(placed)
    link = fake_razorpay.only_link()
    fake_razorpay.pay(link["id"])
    link["amount"] = link["amount_paid"] = 100  # not the link we made

    assert await payments.verify_and_record(link["id"]) is None
    assert (await order_of(placed.order_id)).status == "awaiting_payment"


async def test_the_owner_shares_a_razorpay_link_and_falls_back_to_upi(
    api: httpx2.AsyncClient, connected: ChannelConnection, fake_razorpay: FakeRazorpay
) -> None:
    token = await sign_in_as(connected.merchant_id)
    placed = await place(connected)

    response = await api.get(f"/v1/orders/{placed.order_id}/payment-link", headers=bearer(token))
    assert response.status_code == 200
    assert response.json()["payment_method"] == "razorpay"
    assert response.json()["payment_link"] == fake_razorpay.only_link()["short_url"]

    other = await place(connected)
    async with session_scope() as session:
        await shop_profile.save_onboarding(
            session,
            connected.merchant_id,
            shop_name="Sweet Crumbs",
            answers=OnboardingAnswers(upi_id="sweetcrumbs@okhdfcbank"),
        )
    await payments.disconnect_account(connected.merchant_id)
    fallback = await api.get(f"/v1/orders/{other.order_id}/payment-link", headers=bearer(token))
    assert fallback.json()["payment_method"] == "upi"
    assert fallback.json()["payment_link"].startswith("upi://pay?pa=sweetcrumbs%40okhdfcbank")


async def test_no_link_for_an_order_that_isnt_waiting_for_payment(
    api: httpx2.AsyncClient, connected: ChannelConnection, fake_razorpay: FakeRazorpay
) -> None:
    token = await sign_in_as(connected.merchant_id)
    placed = await paid_order(connected, fake_razorpay)

    response = await api.get(f"/v1/orders/{placed.order_id}/payment-link", headers=bearer(token))

    assert response.status_code == 409


# -- how payments are confirmed -----------------------------------------------------------------


async def webhook(
    api: httpx2.AsyncClient,
    merchant_id: uuid.UUID,
    event: dict[str, object],
    *,
    event_id: str | None = None,
    secret: str | None = None,
    token: str | None = None,
) -> httpx2.Response:
    status = await payments.account_status(merchant_id)
    assert status.account is not None
    body = json.dumps(event).encode()
    url = status.account.webhook_url.removeprefix("https://sellix.test")
    if token is not None:
        url = url.rsplit("/", 1)[0] + "/" + token
    return await api.post(
        url,
        content=body,
        headers={
            "X-Razorpay-Signature": FakeRazorpay.sign(
                body, secret or status.account.webhook_secret
            ),
            "X-Razorpay-Event-Id": event_id or f"evt_{uuid.uuid4().hex[:14]}",
            "Content-Type": "application/json",
        },
    )


async def test_the_paid_webhook_goes_through_the_inbox_and_razorpay_decides(
    api: httpx2.AsyncClient,
    connected: ChannelConnection,
    fake_razorpay: FakeRazorpay,
    deferred_jobs: InMemoryConnector,
) -> None:
    placed = await place(connected)
    await link_for(placed)
    link = fake_razorpay.only_link()
    payment_id = fake_razorpay.pay(link["id"])
    event = fake_razorpay.event(
        "payment_link.paid",
        payment_link=link,
        payment=fake_razorpay.payments[payment_id],
    )

    forged = await webhook(api, connected.merchant_id, event, secret="not-the-secret")
    unknown = await webhook(api, connected.merchant_id, event, token="no-such-shop")
    first = await webhook(api, connected.merchant_id, event, event_id="evt_1")
    repeat = await webhook(api, connected.merchant_id, event, event_id="evt_1")

    assert forged.status_code == 401 and unknown.status_code == 401
    assert first.status_code == 200 and repeat.status_code == 200
    async with session_scope() as session:
        events = list(
            await session.scalars(select(WebhookEvent).where(WebhookEvent.source == "razorpay"))
        )
    assert len(events) == 1
    assert [j["task_name"] for j in deferred_jobs.jobs.values()] == ["process_razorpay_event"]

    await process_razorpay_event(event_id=str(events[0].id))

    assert (await order_of(placed.order_id)).status == "paid"
    status = await payments.account_status(connected.merchant_id)
    assert status.account is not None and status.account.last_webhook_at is not None
    tasks = [j["task_name"] for j in deferred_jobs.jobs.values()]
    assert "run_agent_turn" in tasks or "run_agent_turn_v2" in tasks  # the customer is told


async def test_the_return_page_checks_the_signature_then_razorpay(
    api: httpx2.AsyncClient,
    connected: ChannelConnection,
    fake_razorpay: FakeRazorpay,
    deferred_jobs: InMemoryConnector,
) -> None:
    placed = await place(connected)
    await link_for(placed)
    link = fake_razorpay.only_link()
    payment_id = fake_razorpay.pay(link["id"])
    query = FakeRazorpay.callback_query(link, payment_id, RAZORPAY_KEY_SECRET)

    tampered = await api.get(
        "/payments/razorpay/return?" + urlencode({**query, "razorpay_payment_id": "pay_other"})
    )
    assert tampered.status_code == 400
    assert (await order_of(placed.order_id)).status == "awaiting_payment"

    page = await api.get("/payments/razorpay/return?" + urlencode(query))

    assert page.status_code == 200 and "Thank you" in page.text and "Sweet Crumbs" in page.text
    assert (await order_of(placed.order_id)).status == "paid"


async def test_the_settle_job_confirms_payments_when_no_webhook_comes(
    connected: ChannelConnection, fake_razorpay: FakeRazorpay
) -> None:
    placed = await place(connected)
    await link_for(placed)
    fake_razorpay.pay(fake_razorpay.only_link()["id"])

    settled = await payments.settle_open_payments()

    assert [r.order_id for r in settled] == [placed.order_id]
    assert (await order_of(placed.order_id)).status == "paid"
    assert await payments.settle_open_payments() == []  # nothing left open


async def test_the_link_of_an_expired_order_is_cancelled_at_razorpay(
    connected: ChannelConnection, fake_razorpay: FakeRazorpay
) -> None:
    placed = await place(connected)
    await link_for(placed)
    async with session_scope() as session:
        await orders.expire_due(session, now=datetime.now(UTC) + timedelta(minutes=16))

    await payments.settle_open_payments()

    link = fake_razorpay.only_link()
    assert link["status"] == "cancelled"
    [row] = await payment_rows(placed.order_id)
    assert row.status == "cancelled"


async def test_a_payment_that_lands_just_after_the_hold_still_pays_the_order(
    connected: ChannelConnection, fake_razorpay: FakeRazorpay
) -> None:
    placed = await place(connected)
    await link_for(placed)
    async with session_scope() as session:
        await orders.expire_due(session, now=datetime.now(UTC) + timedelta(minutes=16))
    fake_razorpay.pay(fake_razorpay.only_link()["id"])  # paid before sellix cancelled the link

    [result] = await payments.settle_open_payments()

    assert not isinstance(result, payments.PaymentFailed)
    assert result.outcome == "paid"  # the brownies were still there, so they are sold again
    assert (await order_of(placed.order_id)).status == "paid"


async def test_a_failed_try_tells_the_customer_once_if_the_link_is_still_unpaid(
    api: httpx2.AsyncClient,
    connected: ChannelConnection,
    fake_razorpay: FakeRazorpay,
    deferred_jobs: InMemoryConnector,
) -> None:
    placed = await place(connected)
    checkout = await link_for(placed)
    link = fake_razorpay.only_link()
    failed = fake_razorpay.fail_attempt(link["id"])

    result = await payments.handle_razorpay_event(
        fake_razorpay.event("payment.failed", payment=failed)
    )
    assert isinstance(result, payments.PaymentFailed) and result.link == checkout.url
    await payments_after(result)
    assert "notify_failed_payment" in [j["task_name"] for j in deferred_jobs.jobs.values()]

    await notify_failed_payment(order_id=str(placed.order_id))
    await notify_failed_payment(order_id=str(placed.order_id))  # a second run says nothing new

    async with session_scope() as session:
        notices = list(
            await session.scalars(
                select(Message).where(Message.details["kind"].as_string() == "payment_try_again")
            )
        )
    assert len(notices) == 1
    assert checkout.url in notices[0].body and "didn't go through" in notices[0].body


async def test_no_failed_notice_once_the_customer_paid_on_the_second_try(
    connected: ChannelConnection, fake_razorpay: FakeRazorpay, deferred_jobs: InMemoryConnector
) -> None:
    placed = await place(connected)
    await link_for(placed)
    link = fake_razorpay.only_link()
    fake_razorpay.fail_attempt(link["id"])
    fake_razorpay.pay(link["id"])

    await notify_failed_payment(order_id=str(placed.order_id))

    async with session_scope() as session:
        notices = list(
            await session.scalars(
                select(Message).where(Message.details["kind"].as_string() == "payment_try_again")
            )
        )
    assert notices == []


async def payments_after(result: payments.PaymentFailed) -> None:
    from app.modules.conversations import service as conversations

    await conversations.after_payment(result)


# -- refunds ------------------------------------------------------------------------------------


async def test_a_razorpay_refund_is_recorded_before_razorpay_moves_money(
    connected: ChannelConnection, fake_razorpay: FakeRazorpay
) -> None:
    placed = await paid_order(connected, fake_razorpay)

    outcome = await payments.refund_order(
        placed.order_id, merchant_id=connected.merchant_id, reason="Out of stock"
    )

    assert outcome.status == "completed" and outcome.mode == "razorpay"
    [refund] = fake_razorpay.refunds.values()
    assert refund["amount"] == 18000 and refund["receipt"] == uuid.UUID(outcome.refund_id).hex
    order = await order_of(placed.order_id)
    assert order.status == "refunded" and order.payment_status == "refunded"
    [row] = await payment_rows(placed.order_id)
    assert row.status == "refunded"


async def test_a_pending_refund_is_settled_by_reconcile_and_a_lost_answer_never_refunds_twice(
    connected: ChannelConnection, fake_razorpay: FakeRazorpay
) -> None:
    placed = await paid_order(connected, fake_razorpay)
    fake_razorpay.fail_next = [(502, "gateway")] * 3  # Razorpay's answer never reaches us

    outcome = await payments.refund_order(placed.order_id, merchant_id=connected.merchant_id)

    assert outcome.status == "pending"
    assert (await order_of(placed.order_id)).status == "paid"
    async with session_scope() as session:
        [ticket] = await orders.pending_refunds(session)
    fake_razorpay.refund_status = "pending"
    assert await payments.reconcile_refunds(older_than=timedelta(0)) == 0  # asks again, same key
    [refund] = fake_razorpay.refunds.values()
    assert refund["receipt"] == ticket.id.hex
    refund["status"] = "processed"

    assert await payments.reconcile_refunds(older_than=timedelta(0)) == 1
    assert len(fake_razorpay.refunds) == 1
    assert (await order_of(placed.order_id)).status == "refunded"


async def test_a_refund_razorpay_refuses_fails_and_the_order_stays_paid(
    connected: ChannelConnection, fake_razorpay: FakeRazorpay
) -> None:
    placed = await paid_order(connected, fake_razorpay)
    fake_razorpay.fail_next = [(400, "Your account does not have enough balance")]

    with pytest.raises(RuntimeError, match="enough balance"):
        await payments.refund_order(placed.order_id, merchant_id=connected.merchant_id)

    assert (await order_of(placed.order_id)).status == "paid"
    async with session_scope() as session:
        [request] = await session.scalars(select(RefundRequest))
    assert request.status == "failed"


async def test_the_refund_webhook_is_checked_with_razorpay(
    connected: ChannelConnection, fake_razorpay: FakeRazorpay
) -> None:
    placed = await paid_order(connected, fake_razorpay)
    fake_razorpay.refund_status = "pending"
    await payments.refund_order(placed.order_id, merchant_id=connected.merchant_id)
    [refund] = fake_razorpay.refunds.values()

    # The event claims processed, but Razorpay still says pending: nothing changes.
    claimed = {**refund, "status": "processed"}
    await payments.handle_razorpay_event(fake_razorpay.event("refund.processed", refund=claimed))
    assert (await order_of(placed.order_id)).status == "paid"

    refund["status"] = "processed"
    await payments.handle_razorpay_event(fake_razorpay.event("refund.processed", refund=refund))
    assert (await order_of(placed.order_id)).status == "refunded"


async def test_an_order_paid_by_hand_is_refunded_by_hand(
    connected: ChannelConnection, fake_razorpay: FakeRazorpay
) -> None:
    placed = await place(connected)
    async with session_scope() as session:
        await payments.mark_order_paid(
            session, placed.order_id, merchant_id=connected.merchant_id, method="upi"
        )
    calls_before = len(fake_razorpay.requests)

    outcome = await payments.refund_order(placed.order_id, merchant_id=connected.merchant_id)

    assert outcome.status == "completed" and outcome.mode == "manual"
    assert len(fake_razorpay.requests) == calls_before  # Razorpay isn't involved
    assert (await order_of(placed.order_id)).status == "refunded"


# -- the app's endpoints ------------------------------------------------------------------------


async def test_settings_connect_show_and_disconnect_the_account(
    api: httpx2.AsyncClient, stocked_shop: ChannelConnection, fake_razorpay: FakeRazorpay
) -> None:
    token = await sign_in_as(stocked_shop.merchant_id)

    empty = await api.get("/v1/payments/account", headers=bearer(token))
    assert empty.status_code == 200
    assert empty.json()["source"] == "none" and empty.json()["connected"] is False

    refused = await api.put(
        "/v1/payments/account",
        headers=bearer(token),
        json={"key_id": RAZORPAY_KEY_ID, "key_secret": "WrongSecret12345678"},
    )
    assert refused.status_code == 422 and "didn't accept" in refused.json()["detail"]

    connected = await api.put(
        "/v1/payments/account",
        headers=bearer(token),
        json={"key_id": RAZORPAY_KEY_ID, "key_secret": RAZORPAY_KEY_SECRET},
    )
    body = connected.json()
    assert connected.status_code == 200
    assert body["connected"] and body["source"] == "own" and body["mode"] == "test"
    assert body["key_id_hint"] == "rzp_test_••••0001"
    assert RAZORPAY_KEY_SECRET not in connected.text
    assert body["webhook_secret"] and "payment_link.paid" in body["webhook_events"]

    rotated = await api.post("/v1/payments/account/webhook-secret", headers=bearer(token))
    assert rotated.json()["webhook_secret"] != body["webhook_secret"]
    assert rotated.json()["webhook_url"] == body["webhook_url"]

    gone = await api.delete("/v1/payments/account", headers=bearer(token))
    assert gone.status_code == 204
    after = await api.get("/v1/payments/account", headers=bearer(token))
    assert after.json()["connected"] is False


async def test_the_order_screen_shows_payments_and_refunds(
    api: httpx2.AsyncClient, connected: ChannelConnection, fake_razorpay: FakeRazorpay
) -> None:
    token = await sign_in_as(connected.merchant_id)
    placed = await paid_order(connected, fake_razorpay)

    before = await api.get(f"/v1/orders/{placed.order_id}/payments", headers=bearer(token))
    assert before.status_code == 200
    data = before.json()
    assert data["refundable"] and data["refund_mode"] == "razorpay" and data["refund"] is None
    [payment] = data["payments"]
    assert payment["provider"] == "razorpay" and payment["status"] == "completed"
    assert payment["method"] == "upi" and payment["provider_payment_id"].startswith("pay_")

    refund = await api.post(
        f"/v1/orders/{placed.order_id}/refund", headers=bearer(token), json={"reason": "Late"}
    )
    assert refund.status_code == 200
    assert refund.json()["mode"] == "razorpay" and refund.json()["status"] == "completed"

    after = (await api.get(f"/v1/orders/{placed.order_id}/payments", headers=bearer(token))).json()
    assert after["refundable"] is False
    assert after["refund"]["status"] == "completed" and after["refund"]["reason"] == "Late"
    again = await api.post(f"/v1/orders/{placed.order_id}/refund", headers=bearer(token))
    assert again.status_code == 200  # a second tap returns the same refund, never a second one
    assert again.json()["refund_id"] == refund.json()["refund_id"]
    assert len(fake_razorpay.refunds) == 1


async def test_a_second_refund_request_while_one_is_pending_reuses_it(
    connected: ChannelConnection, fake_razorpay: FakeRazorpay
) -> None:
    placed = await paid_order(connected, fake_razorpay)
    fake_razorpay.refund_status = "pending"

    first = await payments.refund_order(placed.order_id, merchant_id=connected.merchant_id)
    second = await payments.refund_order(placed.order_id, merchant_id=connected.merchant_id)

    assert first.refund_id == second.refund_id and second.status == "pending"
    assert len(fake_razorpay.refunds) == 1  # the same idempotency key both times
    async with session_scope() as session:
        requests = list(await session.scalars(select(RefundRequest)))
    assert [r.status for r in requests] == ["pending"]


# -- order rules that payments rely on ----------------------------------------------------------


async def test_a_customer_cant_hold_more_than_two_unpaid_orders(
    connected: ChannelConnection,
) -> None:
    await place(connected, quantity=1)
    await place(connected, quantity=1)  # the second unpaid order
    async with session_scope() as session:
        conversation = await session.scalar(select(Conversation))
        merchant = await merchants.get_merchant(session, connected.merchant_id)
        assert conversation is not None
        saved = await orders.save_quote(
            session,
            merchant_id=connected.merchant_id,
            conversation_id=conversation.id,
            customer_id=conversation.customer_id,
            business_date=merchants.business_date(merchant),
            request=OrderRequest(lines=(OrderLineRequest("Brownie", None, 1),)),
            expires_at=datetime.now(UTC) + timedelta(hours=1),
        )
        assert isinstance(saved, SavedQuote)
        card = await session.scalar(select(Message.id).limit(1))
        assert card is not None
        await orders.mark_quote_shown(session, saved.id, card)

    with pytest.raises(QuoteRefused) as refused:
        async with session_scope() as session:
            await orders.confirm_quote(
                session, quote_id=saved.id, conversation_id=conversation.id, hold_minutes=15
            )

    assert refused.value.code == "too_many_unpaid_orders"


async def test_a_refund_with_restock_puts_the_sold_items_back_on_sale(
    connected: ChannelConnection, fake_razorpay: FakeRazorpay
) -> None:
    placed = await paid_order(connected, fake_razorpay)  # 2 of the 20 brownies sold
    other = await place(connected, quantity=3)  # another customer's 3 brownies are held

    await payments.refund_order(placed.order_id, merchant_id=connected.merchant_id, restock=True)

    async with session_scope() as session:
        merchant = await merchants.get_merchant(session, connected.merchant_id)
        stock = await session.execute(
            text(
                "select opening + restocked - held - sold - counter_sales, held, sold "
                "from daily_stock where business_date = :day"
            ),
            {"day": merchants.business_date(merchant)},
        )
        available, held, sold = stock.one()
    assert (available, held, sold) == (17, 3, 0)  # 20 - 3 held; the 2 refunded are back
    assert (await order_of(other.order_id)).status == "awaiting_payment"


# -- review fixes (24 Nov) ----------------------------------------------------------------------


async def test_switching_to_another_razorpay_account_ends_the_old_accounts_open_links(
    connected: ChannelConnection, fake_razorpay: FakeRazorpay
) -> None:
    placed = await place(connected)
    await link_for(placed)
    old_link = fake_razorpay.only_link()
    fake_razorpay.add_account("rzp_test_OtherAccount01", "OtherSecret1234567")

    status = await payments.connect_account(
        connected.merchant_id, key_id="rzp_test_OtherAccount01", key_secret="OtherSecret1234567"
    )

    assert old_link["status"] == "cancelled" and status.settled == ()
    [row] = await payment_rows(placed.order_id)
    assert row.status == "cancelled"
    fresh = await link_for(placed)  # a new link, on the new account
    assert fresh.url != old_link["short_url"]
    assert list(fake_razorpay.links.values())[-1]["_account"] == "rzp_test_OtherAccount01"


async def test_a_link_paid_just_before_the_shop_disconnects_is_still_recorded(
    connected: ChannelConnection, fake_razorpay: FakeRazorpay
) -> None:
    placed = await place(connected)
    await link_for(placed)
    fake_razorpay.pay(fake_razorpay.only_link()["id"])

    settled = await payments.disconnect_account(connected.merchant_id)

    assert [r.order_id for r in settled] == [placed.order_id]
    assert (await order_of(placed.order_id)).status == "paid"


async def test_a_second_payment_for_a_paid_order_is_flagged_for_the_owner(
    connected: ChannelConnection, fake_razorpay: FakeRazorpay
) -> None:
    placed = await place(connected)
    await link_for(placed)
    link = fake_razorpay.only_link()
    async with session_scope() as session:  # the shop marked it paid (UPI it saw) ...
        await payments.mark_order_paid(session, placed.order_id, merchant_id=connected.merchant_id)
    fake_razorpay.pay(link["id"])  # ... and the customer paid the link as well

    result = await payments.verify_and_record(link["id"])

    assert result is not None and not isinstance(result, payments.PaymentFailed)
    assert result.outcome == "paid_twice"


async def test_two_askers_at_once_get_the_same_single_link(
    connected: ChannelConnection, fake_razorpay: FakeRazorpay
) -> None:
    import asyncio

    placed = await place(connected)

    first, second = await asyncio.gather(link_for(placed), link_for(placed))

    assert first.url == second.url
    assert len(fake_razorpay.links) == 1


async def test_a_shops_webhook_cant_act_on_another_shops_payments(
    connected: ChannelConnection, fake_razorpay: FakeRazorpay
) -> None:
    placed = await place(connected)
    await link_for(placed)
    link = fake_razorpay.only_link()
    fake_razorpay.pay(link["id"])
    sender = payments.WebhookSender(uuid.uuid4(), uuid.uuid4())  # some other shop's webhook
    event = payments.stored_event(
        fake_razorpay.event("payment_link.paid", payment_link=link), sender
    )

    assert await payments.handle_razorpay_event(event) is None
    assert (await order_of(placed.order_id)).status == "awaiting_payment"


async def test_a_refund_made_elsewhere_doesnt_settle_sellixs_pending_refund(
    connected: ChannelConnection, fake_razorpay: FakeRazorpay
) -> None:
    placed = await paid_order(connected, fake_razorpay)
    fake_razorpay.refund_status = "pending"
    await payments.refund_order(placed.order_id, merchant_id=connected.merchant_id)
    [payment_id] = list(fake_razorpay.payments)
    partial = {  # a partial refund made in Razorpay's dashboard: no receipt
        "id": "rfnd_DASHBOARD0001",
        "entity": "refund",
        "amount": 5000,
        "currency": "INR",
        "payment_id": payment_id,
        "receipt": None,
        "status": "processed",
    }
    fake_razorpay.refunds[partial["id"]] = partial

    await payments.handle_razorpay_event(fake_razorpay.event("refund.processed", refund=partial))

    assert (await order_of(placed.order_id)).status == "paid"


async def test_test_mode_payments_are_marked_and_live_only_refuses_test_keys(
    api: httpx2.AsyncClient,
    connected: ChannelConnection,
    fake_razorpay: FakeRazorpay,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    token = await sign_in_as(connected.merchant_id)
    placed = await paid_order(connected, fake_razorpay)
    view = (await api.get(f"/v1/orders/{placed.order_id}/payments", headers=bearer(token))).json()
    assert view["payments"][0]["test_mode"] is True

    monkeypatch.setattr(get_settings(), "razorpay_live_keys_only", True)
    with pytest.raises(payments.AccountKeysRejected, match="live keys only"):
        await payments.connect_account(
            connected.merchant_id, key_id=RAZORPAY_KEY_ID, key_secret=RAZORPAY_KEY_SECRET
        )
    with pytest.raises(payments.PaymentUnavailable):
        await link_for(await place(connected, quantity=1))
