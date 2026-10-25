"""Payments against the real PayPal sandbox (api-m.sandbox.paypal.com): no fakes.

Credentials come from PAYPAL_SANDBOX_CLIENT_ID / PAYPAL_SANDBOX_CLIENT_SECRET (and optionally
PAYPAL_SANDBOX_WEBHOOK_ID), or from PAYPAL_* in backend/.env when PAYPAL_ENV is sandbox.
Without them these tests are skipped; REQUIRE_PAYPAL_SANDBOX_TESTS=1 makes that a failure.
Approving a payment needs a sandbox buyer in a browser, so that step is tested by hand.
"""

import os
import uuid
from datetime import date

import pytest
from dotenv import dotenv_values
from sqlalchemy import select

from app.core.config import BACKEND_DIR, get_settings
from app.core.db import session_scope
from app.modules.channels.models import ChannelConnection
from app.modules.conversations.models import Conversation
from app.modules.inventory import service as inventory
from app.modules.inventory.schemas import OpeningStockLine
from app.modules.orders import service as orders
from app.modules.orders.schemas import OrderLineRequest, OrderRequest
from app.modules.payments import paypal
from app.modules.payments import service as payments
from app.modules.payments.models import Payment
from tests.integration.factories import start_conversation

pytestmark = pytest.mark.anyio

TODAY = date(2026, 10, 25)


def _sandbox_credentials() -> dict[str, str]:
    from_env = {
        "client_id": os.environ.get("PAYPAL_SANDBOX_CLIENT_ID", ""),
        "client_secret": os.environ.get("PAYPAL_SANDBOX_CLIENT_SECRET", ""),
        "webhook_id": os.environ.get("PAYPAL_SANDBOX_WEBHOOK_ID", ""),
    }
    if from_env["client_id"] and from_env["client_secret"]:
        return from_env
    local = dotenv_values(BACKEND_DIR / ".env")
    if (local.get("PAYPAL_ENV") or "sandbox") != "sandbox":
        return {}
    return {
        "client_id": local.get("PAYPAL_CLIENT_ID") or "",
        "client_secret": local.get("PAYPAL_CLIENT_SECRET") or "",
        "webhook_id": local.get("PAYPAL_WEBHOOK_ID") or "",
    }


@pytest.fixture
def sandbox(monkeypatch: pytest.MonkeyPatch) -> dict[str, str]:
    credentials = _sandbox_credentials()
    if not (credentials.get("client_id") and credentials.get("client_secret")):
        if os.environ.get("REQUIRE_PAYPAL_SANDBOX_TESTS") == "1":
            pytest.fail("PayPal sandbox credentials are required for these tests")
        pytest.skip("No PayPal sandbox credentials (set PAYPAL_CLIENT_ID/SECRET in backend/.env)")
    settings = get_settings()
    monkeypatch.setattr(settings, "paypal_env", "sandbox")
    monkeypatch.setattr(settings, "paypal_client_id", credentials["client_id"])
    monkeypatch.setattr(settings, "paypal_client_secret", credentials["client_secret"])
    monkeypatch.setattr(settings, "paypal_webhook_id", credentials.get("webhook_id", ""))
    monkeypatch.setattr(paypal, "_token_cache", {})
    return credentials


async def test_sandbox_order_has_a_paypal_approval_link(sandbox: dict[str, str]) -> None:
    reference = f"test-{uuid.uuid4()}"

    created = await paypal.create_order(
        reference_id=reference,
        description="sellix sandbox test",
        amount_minor=1250,
        currency="USD",
        brand_name="Sweet Crumbs",
        return_url="https://sellix.test/payments/paypal/return",
        cancel_url="https://sellix.test/payments/paypal/cancel",
    )
    repeated = await paypal.create_order(
        reference_id=reference,
        description="sellix sandbox test",
        amount_minor=1250,
        currency="USD",
        brand_name="Sweet Crumbs",
        return_url="https://sellix.test/payments/paypal/return",
        cancel_url="https://sellix.test/payments/paypal/cancel",
    )

    assert created.paypal_order_id
    assert "sandbox.paypal.com" in created.approve_url
    # Same request ID: PayPal returns the same order instead of creating a second one.
    assert repeated.paypal_order_id == created.paypal_order_id


async def test_sandbox_refuses_to_capture_before_the_buyer_approves(
    sandbox: dict[str, str],
) -> None:
    created = await paypal.create_order(
        reference_id=f"test-{uuid.uuid4()}",
        description="sellix sandbox test",
        amount_minor=500,
        currency="USD",
        brand_name="Sweet Crumbs",
        return_url="https://sellix.test/payments/paypal/return",
        cancel_url="https://sellix.test/payments/paypal/cancel",
    )

    assert await paypal.capture_order(created.paypal_order_id) is None


async def test_sandbox_rejects_a_forged_webhook(sandbox: dict[str, str]) -> None:
    if not sandbox.get("webhook_id"):
        pytest.skip("No PayPal sandbox webhook ID (PAYPAL_WEBHOOK_ID)")
    forged_headers = {
        "PAYPAL-AUTH-ALGO": "SHA256withRSA",
        "PAYPAL-CERT-URL": "https://api.sandbox.paypal.com/v1/notifications/certs/CERT-360caa42-fca2a594-a5cafa77",
        "PAYPAL-TRANSMISSION-ID": str(uuid.uuid4()),
        "PAYPAL-TRANSMISSION-SIG": "forged-signature",
        "PAYPAL-TRANSMISSION-TIME": "2026-10-25T10:00:00Z",
    }

    genuine = await paypal.verify_webhook(
        headers=forged_headers,
        event={"id": "WH-FORGED", "event_type": "PAYMENT.CAPTURE.COMPLETED", "resource": {}},
    )

    assert genuine is False


async def test_placed_order_gets_a_real_sandbox_checkout(
    shop: ChannelConnection, sandbox: dict[str, str]
) -> None:
    async with session_scope() as session:
        await inventory.set_opening_stock(
            session,
            merchant_id=shop.merchant_id,
            business_date=TODAY,
            lines=[OpeningStockLine("Gift box", "Chocolate", 1250, 5, currency="USD")],
        )
    turn = await start_conversation("1 chocolate gift box please")
    async with session_scope() as session:
        conversation = await session.get(Conversation, turn.conversation_id)
        assert conversation is not None
        placed = await orders.place_order(
            session,
            merchant_id=shop.merchant_id,
            customer_id=conversation.customer_id,
            conversation_id=conversation.id,
            business_date=TODAY,
            request=OrderRequest(lines=(OrderLineRequest("Gift box", "Chocolate", 1),)),
            hold_minutes=15,
        )

    link = await payments.create_checkout(placed, shop_name="Sweet Crumbs")

    async with session_scope() as session:
        payment = await session.scalar(select(Payment).where(Payment.order_id == placed.order_id))
    assert "sandbox.paypal.com" in link
    assert payment is not None
    assert (payment.status, payment.amount_minor, payment.currency) == ("created", 1250, "USD")
    assert payment.approve_url == link
    # Not approved by a buyer yet: capturing does nothing, the order still awaits payment.
    assert await payments.capture(payment.provider_order_id) is None
