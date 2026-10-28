import urllib.parse
import uuid
from datetime import UTC, datetime
from typing import Any, cast

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.orders import service as orders
from app.modules.orders.schemas import OrderSummary, PaymentResult
from app.modules.payments import service as payments
from app.modules.payments.models import Payment
from app.modules.payments.upi import create_upi_link


class _RecordingSession:
    def __init__(self) -> None:
        self.added: list[Any] = []

    def add(self, instance: Any) -> None:
        self.added.append(instance)


def _order_summary(*, order_id: uuid.UUID, merchant_id: uuid.UUID, status: str) -> OrderSummary:
    return OrderSummary(
        id=order_id,
        number=101,
        status=status,
        payment_status="paid" if status in ("paid", "completed") else "pending",
        fulfilment_method="pickup",
        currency="INR",
        total_minor=18000,
        customer_id=uuid.uuid4(),
        conversation_id=None,
        created_at=datetime.now(UTC),
        paid_at=datetime.now(UTC) if status in ("paid", "completed") else None,
        hold_expires_at=None,
        customer_note=None,
        items=(),
        merchant_id=merchant_id,
    )


def test_create_upi_link_valid() -> None:
    link = create_upi_link(
        vpa="sweetcrumbs@okhdfcbank",
        payee_name="Sweet Crumbs",
        amount_minor=18000,
        order_number=101,
        currency="INR",
    )
    assert link.startswith("upi://pay?")
    parsed = urllib.parse.parse_qs(link[len("upi://pay?") :])
    assert parsed["pa"] == ["sweetcrumbs@okhdfcbank"]
    assert parsed["pn"] == ["Sweet Crumbs"]
    assert parsed["am"] == ["180.00"]
    assert parsed["cu"] == ["INR"]
    assert parsed["tn"] == ["Order #101"]


def test_create_upi_link_rejects_non_inr() -> None:
    with pytest.raises(ValueError, match="UPI only supports INR"):
        create_upi_link(
            vpa="sweetcrumbs@okhdfcbank",
            payee_name="Sweet Crumbs",
            amount_minor=18000,
            order_number=101,
            currency="USD",
        )


def test_create_upi_link_rejects_empty_vpa() -> None:
    with pytest.raises(ValueError, match="Merchant UPI ID"):
        create_upi_link(
            vpa="",
            payee_name="Sweet Crumbs",
            amount_minor=18000,
            order_number=101,
            currency="INR",
        )


def test_create_upi_link_rejects_negative_or_zero_amount() -> None:
    with pytest.raises(ValueError, match="positive"):
        create_upi_link(
            vpa="sweetcrumbs@okhdfcbank",
            payee_name="Sweet Crumbs",
            amount_minor=0,
            order_number=101,
            currency="INR",
        )


@pytest.mark.anyio
@pytest.mark.parametrize("terminal_status", ["cancelled", "expired"])
async def test_mark_order_paid_rejects_cancelled_or_expired_order_without_recording_payment(
    monkeypatch: pytest.MonkeyPatch,
    terminal_status: str,
) -> None:
    order_id = uuid.uuid4()
    merchant_id = uuid.uuid4()
    session = _RecordingSession()

    async def fake_get_order(
        _session: AsyncSession, _order_id: uuid.UUID, _merchant_id: uuid.UUID | None = None
    ) -> OrderSummary | None:
        return _order_summary(order_id=order_id, merchant_id=merchant_id, status=terminal_status)

    async def fake_record_payment(
        _session: AsyncSession,
        target_order_id: uuid.UUID,
        *,
        amount_minor: int,
        currency: str,
        actor: str,
    ) -> PaymentResult:
        return PaymentResult(
            order_id=target_order_id,
            number=101,
            merchant_id=merchant_id,
            conversation_id=None,
            currency=currency,
            total_minor=amount_minor,
            outcome="paid",
        )

    monkeypatch.setattr(orders, "get_order", fake_get_order)
    monkeypatch.setattr(orders, "record_payment", fake_record_payment)

    with pytest.raises(
        ValueError,
        match=f"Cannot mark order as paid when status is '{terminal_status}'",
    ):
        await payments.mark_order_paid(
            cast(AsyncSession, session),
            order_id,
            merchant_id=merchant_id,
        )

    assert session.added == []


@pytest.mark.anyio
@pytest.mark.parametrize("already_settled_status", ["paid", "completed", "refunded"])
async def test_mark_order_paid_does_not_insert_duplicate_payment_when_already_paid(
    monkeypatch: pytest.MonkeyPatch,
    already_settled_status: str,
) -> None:
    order_id = uuid.uuid4()
    merchant_id = uuid.uuid4()
    session = _RecordingSession()

    async def fake_get_order(
        _session: AsyncSession, _order_id: uuid.UUID, _merchant_id: uuid.UUID | None = None
    ) -> OrderSummary | None:
        return _order_summary(
            order_id=order_id, merchant_id=merchant_id, status=already_settled_status
        )

    async def fake_record_payment(
        _session: AsyncSession,
        target_order_id: uuid.UUID,
        *,
        amount_minor: int,
        currency: str,
        actor: str,
    ) -> PaymentResult:
        return PaymentResult(
            order_id=target_order_id,
            number=101,
            merchant_id=merchant_id,
            conversation_id=None,
            currency=currency,
            total_minor=amount_minor,
            outcome="already_paid",
        )

    monkeypatch.setattr(orders, "get_order", fake_get_order)
    monkeypatch.setattr(orders, "record_payment", fake_record_payment)

    result = await payments.mark_order_paid(
        cast(AsyncSession, session),
        order_id,
        merchant_id=merchant_id,
    )

    assert result.outcome == "already_paid"
    assert session.added == []


@pytest.mark.anyio
async def test_mark_order_paid_records_single_manual_payment_for_awaiting_payment_order(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    order_id = uuid.uuid4()
    merchant_id = uuid.uuid4()
    session = _RecordingSession()

    async def fake_get_order(
        _session: AsyncSession, _order_id: uuid.UUID, _merchant_id: uuid.UUID | None = None
    ) -> OrderSummary | None:
        return _order_summary(order_id=order_id, merchant_id=merchant_id, status="awaiting_payment")

    async def fake_record_payment(
        _session: AsyncSession,
        target_order_id: uuid.UUID,
        *,
        amount_minor: int,
        currency: str,
        actor: str,
    ) -> PaymentResult:
        return PaymentResult(
            order_id=target_order_id,
            number=101,
            merchant_id=merchant_id,
            conversation_id=None,
            currency=currency,
            total_minor=amount_minor,
            outcome="paid",
        )

    monkeypatch.setattr(orders, "get_order", fake_get_order)
    monkeypatch.setattr(orders, "record_payment", fake_record_payment)

    result = await payments.mark_order_paid(
        cast(AsyncSession, session),
        order_id,
        merchant_id=merchant_id,
        method="upi",
        reference_id="UTR-998877",
    )

    assert result.outcome == "paid"
    assert len(session.added) == 1
    recorded = session.added[0]
    assert isinstance(recorded, Payment)
    assert recorded.order_id == order_id
    assert recorded.merchant_id == merchant_id
    assert recorded.provider == "upi_manual"
    assert recorded.method == "upi"
    assert recorded.provider_order_id == "UTR-998877"
    assert recorded.amount_minor == 18000
    assert recorded.currency == "INR"
    assert recorded.status == "completed"
