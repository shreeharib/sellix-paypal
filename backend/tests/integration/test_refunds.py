"""PayPal refunds are on record before money moves, so a refund is never lost (D4).

PayPal is replaced with queued answers; the database, orders and stock are real.
"""

import uuid
from datetime import UTC, date, datetime, timedelta

import pytest
from sqlalchemy import func, select, text

from app.core.db import session_scope
from app.modules.channels.models import ChannelConnection
from app.modules.conversations.models import Conversation
from app.modules.inventory import service as inventory
from app.modules.inventory.schemas import OpeningStockLine
from app.modules.orders import service as orders
from app.modules.orders.models import Order, Refund, RefundRequest
from app.modules.orders.schemas import OrderLineRequest, OrderRequest, PlacedOrder
from app.modules.payments import paypal
from app.modules.payments import service as payments
from app.modules.payments.models import Payment
from tests.integration.factories import start_conversation

pytestmark = pytest.mark.anyio

TODAY = date(2026, 10, 25)
COMPLETED = paypal.RefundResult("REFUND-1", "COMPLETED", 18000, "INR")
PENDING = paypal.RefundResult("REFUND-1", "PENDING", 18000, "INR")
TIMEOUT = paypal.PayPalError(0, "network error: ReadTimeout")

PayPalAnswer = paypal.RefundResult | paypal.PayPalError


@pytest.fixture
async def paid(shop: ChannelConnection, monkeypatch: pytest.MonkeyPatch) -> PlacedOrder:
    """A two-brownie order (₹180) paid through PayPal with capture CAPTURE-1."""
    monkeypatch.setattr(paypal, "configured", lambda: True)
    async with session_scope() as session:
        await inventory.set_opening_stock(
            session,
            merchant_id=shop.merchant_id,
            business_date=TODAY,
            lines=[OpeningStockLine("Brownie", None, 9000, 15)],
        )
    turn = await start_conversation(message_id=f"m-{datetime.now(UTC).timestamp()}")
    async with session_scope() as session:
        conversation = await session.get(Conversation, turn.conversation_id)
        assert conversation is not None
        placed = await orders.place_order(
            session,
            merchant_id=shop.merchant_id,
            customer_id=conversation.customer_id,
            conversation_id=conversation.id,
            business_date=TODAY,
            request=OrderRequest(
                lines=(OrderLineRequest("Brownie", None, 2),), fulfilment="pickup"
            ),
            hold_minutes=15,
        )
        session.add(
            Payment(
                merchant_id=shop.merchant_id,
                order_id=placed.order_id,
                provider="paypal",
                provider_order_id="ORDER-1",
                provider_capture_id="CAPTURE-1",
                status="completed",
                currency="INR",
                amount_minor=18000,
            )
        )
        await orders.record_payment(
            session, placed.order_id, amount_minor=18000, currency="INR", actor="paypal"
        )
    return placed


@pytest.fixture
def paypal_answers(monkeypatch: pytest.MonkeyPatch) -> list[PayPalAnswer]:
    """What PayPal answers next: each refund or refund lookup takes the first answer."""
    answers: list[PayPalAnswer] = []

    async def answer(*_: object, **__: object) -> paypal.RefundResult:
        reply = answers.pop(0)
        if isinstance(reply, paypal.PayPalError):
            raise reply
        return reply

    monkeypatch.setattr(paypal, "refund_capture", answer)
    monkeypatch.setattr(paypal, "get_refund", answer)
    return answers


async def refund_statuses(order_id: uuid.UUID) -> list[str]:
    async with session_scope() as session:
        found = await session.scalars(
            select(RefundRequest.status).where(RefundRequest.order_id == order_id)
        )
        return list(found)


async def money_returned(order_id: uuid.UUID) -> int:
    """How many `refunds` rows (money actually returned) the order has."""
    async with session_scope() as session:
        count = await session.scalar(
            select(func.count()).select_from(Refund).where(Refund.order_id == order_id)
        )
        return count or 0


async def order_and_payment_status(order_id: uuid.UUID) -> tuple[str, str]:
    async with session_scope() as session:
        order = await session.get(Order, order_id)
        payment = await session.scalar(select(Payment).where(Payment.order_id == order_id))
        assert order is not None
        assert payment is not None
        return order.status, payment.status


async def refund(shop: ChannelConnection, placed: PlacedOrder) -> payments.RefundOutcome:
    return await payments.refund_order(
        placed.order_id, merchant_id=shop.merchant_id, reason="Damaged box"
    )


async def test_the_refund_is_on_record_before_paypal_moves_money(
    shop: ChannelConnection, paid: PlacedOrder, monkeypatch: pytest.MonkeyPatch
) -> None:
    seen_by_paypal: list[tuple[list[str], int]] = []

    async def refund_capture(*_: object, **__: object) -> paypal.RefundResult:
        seen_by_paypal.append(
            (await refund_statuses(paid.order_id), await money_returned(paid.order_id))
        )
        return COMPLETED

    monkeypatch.setattr(paypal, "refund_capture", refund_capture)

    outcome = await refund(shop, paid)

    assert seen_by_paypal == [(["pending"], 0)]
    assert outcome.status == "COMPLETED"
    assert await refund_statuses(paid.order_id) == ["completed"]
    assert await money_returned(paid.order_id) == 1
    assert await order_and_payment_status(paid.order_id) == ("refunded", "refunded")


async def test_a_refund_whose_paypal_answer_is_lost_is_settled_by_reconcile(
    shop: ChannelConnection, paid: PlacedOrder, paypal_answers: list[PayPalAnswer]
) -> None:
    paypal_answers.append(TIMEOUT)

    outcome = await refund(shop, paid)

    assert outcome.status == "PENDING"
    assert await refund_statuses(paid.order_id) == ["pending"]
    assert await order_and_payment_status(paid.order_id) == ("paid", "completed")
    async with session_scope() as session:
        pnl_refunds = await session.scalar(
            text("SELECT total_refunds_minor FROM v_merchant_pnl_summary WHERE merchant_id = :m"),
            {"m": shop.merchant_id},
        )
    assert pnl_refunds == 0

    paypal_answers.append(COMPLETED)
    settled = await payments.reconcile_refunds(older_than=timedelta(0))

    assert settled == 1
    assert await refund_statuses(paid.order_id) == ["completed"]
    assert await order_and_payment_status(paid.order_id) == ("refunded", "refunded")


async def test_reconcile_counts_a_capture_paypal_already_refunded_as_done(
    shop: ChannelConnection, paid: PlacedOrder, paypal_answers: list[PayPalAnswer]
) -> None:
    paypal_answers.append(TIMEOUT)
    await refund(shop, paid)

    paypal_answers.append(paypal.PayPalError(422, "unprocessable", "CAPTURE_FULLY_REFUNDED"))
    await payments.reconcile_refunds(older_than=timedelta(0))

    assert await refund_statuses(paid.order_id) == ["completed"]
    assert await order_and_payment_status(paid.order_id) == ("refunded", "refunded")


async def test_a_refund_paypal_refuses_is_marked_failed_and_the_order_stays_paid(
    shop: ChannelConnection, paid: PlacedOrder, paypal_answers: list[PayPalAnswer]
) -> None:
    paypal_answers.append(paypal.PayPalError(422, "unprocessable", "REFUND_NOT_ALLOWED"))

    with pytest.raises(RuntimeError):
        await refund(shop, paid)

    assert await refund_statuses(paid.order_id) == ["failed"]
    assert await order_and_payment_status(paid.order_id) == ("paid", "completed")


async def test_a_second_refund_request_while_pending_reuses_the_first(
    shop: ChannelConnection, paid: PlacedOrder, paypal_answers: list[PayPalAnswer]
) -> None:
    paypal_answers.extend([TIMEOUT, COMPLETED])

    await refund(shop, paid)
    await refund(shop, paid)

    assert await refund_statuses(paid.order_id) == ["completed"]
    assert await money_returned(paid.order_id) == 1


async def test_the_refunded_webhook_is_checked_with_paypal_before_completing(
    shop: ChannelConnection, paid: PlacedOrder, paypal_answers: list[PayPalAnswer]
) -> None:
    paypal_answers.append(PENDING)
    outcome = await refund(shop, paid)
    assert outcome.status == "PENDING"
    event = {
        "event_type": "PAYMENT.CAPTURE.REFUNDED",
        "resource": {
            "id": "REFUND-1",
            "status": "COMPLETED",
            "links": [
                {"rel": "up", "href": "https://api.paypal.com/v2/payments/captures/CAPTURE-1"}
            ],
        },
    }

    paypal_answers.append(PENDING)
    await payments.handle_webhook(event)
    assert await refund_statuses(paid.order_id) == ["pending"]

    paypal_answers.append(COMPLETED)
    await payments.handle_webhook(event)
    assert await refund_statuses(paid.order_id) == ["completed"]
    assert await order_and_payment_status(paid.order_id) == ("refunded", "refunded")
