"""An order becomes paid only once code has checked with PayPal (invariant I4, defect D5).

PayPal's API is replaced; the database, orders and payments are real.
"""

import uuid
from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
from sqlalchemy import select

from app.core.db import session_scope
from app.modules.channels.models import ChannelConnection
from app.modules.conversations.models import Conversation, Message
from app.modules.inventory import service as inventory
from app.modules.inventory.schemas import OpeningStockLine
from app.modules.merchants import service as merchants
from app.modules.orders import service as orders
from app.modules.orders.models import Order
from app.modules.orders.schemas import (
    OrderLineRequest,
    OrderRequest,
    PlacedOrder,
    QuoteRefused,
    SavedQuote,
)
from app.modules.payments import paypal
from app.modules.payments import service as payments
from app.modules.payments.models import Payment
from tests.integration.factories import start_conversation

pytestmark = pytest.mark.anyio

PAYPAL_ORDER = "PP-ORDER-1"


async def place(shop: ChannelConnection, quantity: int = 2) -> PlacedOrder:
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


@pytest.fixture
async def pending(shop: ChannelConnection) -> PlacedOrder:
    """A ₹180 order with a PayPal payment the customer has been sent to."""
    async with session_scope() as session:
        merchant = await merchants.get_merchant(session, shop.merchant_id)
        await inventory.set_opening_stock(
            session,
            merchant_id=shop.merchant_id,
            business_date=merchants.business_date(merchant),
            lines=[OpeningStockLine("Brownie", None, 9000, 20)],
        )
    placed = await place(shop)
    async with session_scope() as session:
        session.add(
            Payment(
                merchant_id=shop.merchant_id,
                order_id=placed.order_id,
                provider="paypal",
                provider_order_id=PAYPAL_ORDER,
                status="created",
                currency="INR",
                amount_minor=18000,
            )
        )
    return placed


def paypal_order(
    custom_id: uuid.UUID | str,
    *,
    status: str = "COMPLETED",
    capture_status: str = "COMPLETED",
    value: str = "180.00",
) -> dict[str, Any]:
    return {
        "id": PAYPAL_ORDER,
        "status": status,
        "purchase_units": [
            {
                "reference_id": str(custom_id),
                "custom_id": str(custom_id),
                "payments": {
                    "captures": [
                        {
                            "id": "CAPTURE-1",
                            "status": capture_status,
                            "amount": {"value": value, "currency_code": "INR"},
                        }
                    ]
                },
            }
        ],
    }


@pytest.fixture
def paypal_says(monkeypatch: pytest.MonkeyPatch) -> list[dict[str, Any]]:
    """What GET /v2/checkout/orders/{id} returns next."""
    answers: list[dict[str, Any]] = []

    async def get_order(paypal_order_id: str) -> dict[str, Any]:
        assert paypal_order_id == PAYPAL_ORDER
        return answers.pop(0)

    monkeypatch.setattr(paypal, "configured", lambda: True)
    monkeypatch.setattr(paypal, "get_order", get_order)
    return answers


def completed_webhook(value: str = "180.00") -> dict[str, Any]:
    """A signature-verified webhook; its body is only a hint of which order to check."""
    return {
        "event_type": "PAYMENT.CAPTURE.COMPLETED",
        "resource": {
            "id": "CAPTURE-1",
            "status": "COMPLETED",
            "amount": {"value": value, "currency_code": "INR"},
            "supplementary_data": {"related_ids": {"order_id": PAYPAL_ORDER}},
        },
    }


async def order_status(order_id: uuid.UUID) -> str:
    async with session_scope() as session:
        order = await session.get(Order, order_id)
    assert order is not None
    return order.status


async def test_paid_only_after_paypal_confirms_the_order(
    pending: PlacedOrder, paypal_says: list[dict[str, Any]]
) -> None:
    paypal_says.append(paypal_order(pending.order_id))

    result = await payments.handle_webhook(completed_webhook())

    assert result is not None and getattr(result, "outcome", None) == "paid"
    assert await order_status(pending.order_id) == "paid"


async def test_a_webhook_is_not_trusted_when_paypal_says_the_order_is_pending(
    pending: PlacedOrder, paypal_says: list[dict[str, Any]]
) -> None:
    paypal_says.append(paypal_order(pending.order_id, status="APPROVED", capture_status="PENDING"))

    assert await payments.handle_webhook(completed_webhook()) is None
    assert await order_status(pending.order_id) == "awaiting_payment"


async def test_the_amount_paypal_reports_is_what_counts_not_the_webhooks(
    pending: PlacedOrder, paypal_says: list[dict[str, Any]]
) -> None:
    """The webhook claims ₹180; PayPal says ₹1 was paid."""
    paypal_says.append(paypal_order(pending.order_id, value="1.00"))

    result = await payments.handle_webhook(completed_webhook())

    assert result is not None and getattr(result, "outcome", None) == "amount_mismatch"
    assert await order_status(pending.order_id) == "awaiting_payment"


async def test_a_capture_for_another_order_never_marks_this_one_paid(
    pending: PlacedOrder, paypal_says: list[dict[str, Any]]
) -> None:
    paypal_says.append(paypal_order(uuid.uuid4()))

    assert await payments.handle_webhook(completed_webhook()) is None
    assert await order_status(pending.order_id) == "awaiting_payment"


async def test_a_replayed_webhook_records_the_payment_once(
    pending: PlacedOrder, paypal_says: list[dict[str, Any]]
) -> None:
    paypal_says.extend([paypal_order(pending.order_id), paypal_order(pending.order_id)])

    await payments.handle_webhook(completed_webhook())
    second = await payments.handle_webhook(completed_webhook())

    assert second is None
    async with session_scope() as session:
        payment = await session.scalar(select(Payment))
    assert payment is not None and payment.status == "completed"


async def test_the_return_page_goes_through_the_same_check(
    pending: PlacedOrder, paypal_says: list[dict[str, Any]], monkeypatch: pytest.MonkeyPatch
) -> None:
    async def capture_order(paypal_order_id: str) -> paypal.Capture:
        # PayPal's capture answer is ignored too: only the re-fetched order counts.
        return paypal.Capture("COMPLETED", "CAPTURE-1", 18000, "INR")

    monkeypatch.setattr(paypal, "capture_order", capture_order)
    paypal_says.append(paypal_order(pending.order_id, status="APPROVED", capture_status="PENDING"))

    assert await payments.capture(PAYPAL_ORDER) is None
    assert await order_status(pending.order_id) == "awaiting_payment"


async def test_a_customer_cant_hold_more_than_two_unpaid_orders(
    pending: PlacedOrder, shop: ChannelConnection
) -> None:
    await place(shop, quantity=1)  # the second unpaid order
    async with session_scope() as session:
        conversation = await session.scalar(select(Conversation))
        merchant = await merchants.get_merchant(session, shop.merchant_id)
        assert conversation is not None
        saved = await orders.save_quote(
            session,
            merchant_id=shop.merchant_id,
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
