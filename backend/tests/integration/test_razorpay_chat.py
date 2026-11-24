"""A customer orders in the chat and pays through the shop's own Razorpay account.

The model is scripted and Razorpay is faked at the HTTP level; the agent's tools, orders,
payments, the outbox and the jobs are real.
"""

import pytest
from sqlalchemy import select

from app.core.db import session_scope
from app.modules.channels.models import ChannelConnection
from app.modules.conversations.models import Message
from app.modules.orders.models import Order
from app.modules.payments import service as payments
from app.modules.payments.models import Payment
from app.modules.shop_profile import service as shop_profile
from app.modules.shop_profile.schemas import OnboardingAnswers
from tests.conftest import RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET
from tests.integration.factories import Instagram, ScriptedModel
from tests.integration.fake_razorpay import FakeRazorpay
from tests.integration.test_payment_retry_chat import unpaid_order

pytestmark = pytest.mark.anyio


async def payment_messages() -> list[Message]:
    async with session_scope() as session:
        return list(
            await session.scalars(
                select(Message)
                .where(Message.details["kind"].as_string() == "payment")
                .order_by(Message.created_at)
            )
        )


async def test_the_customer_gets_a_razorpay_link_and_the_order_is_paid_through_it(
    v2_shop: ChannelConnection,
    model: ScriptedModel,
    instagram: Instagram,
    fake_razorpay: FakeRazorpay,
) -> None:
    await payments.connect_account(
        v2_shop.merchant_id, key_id=RAZORPAY_KEY_ID, key_secret=RAZORPAY_KEY_SECRET
    )

    order = await unpaid_order(v2_shop, model)

    link = fake_razorpay.only_link()
    [message] = await payment_messages()
    assert link["short_url"] in message.body and "UPI, card or net banking" in message.body
    assert link["amount"] == order.total_minor
    async with session_scope() as session:
        [row] = await session.scalars(select(Payment).where(Payment.order_id == order.id))
    assert row.provider == "razorpay" and row.status == "created"

    fake_razorpay.pay(link["id"])
    [settled] = await payments.settle_open_payments()

    assert settled.order_id == order.id
    async with session_scope() as session:
        paid = await session.get(Order, order.id)
    assert paid is not None and paid.status == "paid"


async def test_razorpay_comes_before_the_shops_plain_upi_link(
    v2_shop: ChannelConnection,
    model: ScriptedModel,
    instagram: Instagram,
    fake_razorpay: FakeRazorpay,
) -> None:
    """A UPI link can't be confirmed automatically, so it is only the fallback."""
    await payments.connect_account(
        v2_shop.merchant_id, key_id=RAZORPAY_KEY_ID, key_secret=RAZORPAY_KEY_SECRET
    )
    order = await unpaid_order(v2_shop, model)  # clears the UPI id; put it back and re-send
    async with session_scope() as session:
        await shop_profile.save_onboarding(
            session,
            v2_shop.merchant_id,
            shop_name="Sweet Crumbs",
            answers=OnboardingAnswers(upi_id="sweetcrumbs@okhdfcbank"),
        )

    shared = await payments.get_order_payment_link(order.id, merchant_id=v2_shop.merchant_id)

    assert shared.payment_method == "razorpay"
    assert shared.payment_link == fake_razorpay.only_link()["short_url"]
