"""When may a customer have another payment link? Cooldown, tries and the time window."""

import uuid
from datetime import UTC, datetime, timedelta

import pytest

from app.core.config import get_settings
from app.modules.orders.schemas import OrderSummary
from app.modules.payments import service
from app.modules.payments.models import Payment

NOW = datetime(2026, 11, 8, 12, 0, tzinfo=UTC)


@pytest.fixture(autouse=True)
def rules(monkeypatch: pytest.MonkeyPatch) -> None:
    settings = get_settings()
    monkeypatch.setattr(settings, "payment_max_attempts", 3)
    monkeypatch.setattr(settings, "payment_retry_cooldown_seconds", 60)


def order(*, status: str = "awaiting_payment", window_ends_in: int | None = 900) -> OrderSummary:
    return OrderSummary(
        id=uuid.uuid4(),
        number=1003,
        status=status,
        currency="INR",
        total_minor=89900,
        customer_id=uuid.uuid4(),
        conversation_id=uuid.uuid4(),
        created_at=NOW - timedelta(minutes=5),
        paid_at=None,
        hold_expires_at=None if window_ends_in is None else NOW + timedelta(seconds=window_ends_in),
        items=(),
    )


def attempt(status: str, ago: int = 0) -> Payment:
    return Payment(
        merchant_id=uuid.uuid4(),
        order_id=uuid.uuid4(),
        provider="simulator",
        status=status,
        currency="INR",
        amount_minor=89900,
        updated_at=NOW - timedelta(seconds=ago),
    )


def test_a_new_order_may_have_its_first_link() -> None:
    status = service._retry_policy(order(), [], NOW)

    assert status.can_retry and status.wait_seconds == 0 and status.attempts_left == 3


def test_after_a_failed_payment_the_customer_waits_out_the_cooldown() -> None:
    status = service._retry_policy(order(), [attempt("denied", ago=20)], NOW)

    assert status.can_retry
    assert status.wait_seconds == 40  # 60 seconds after the failure, 20 already gone
    assert status.attempts_left == 2


def test_once_the_cooldown_has_passed_a_new_link_is_allowed_now() -> None:
    status = service._retry_policy(order(), [attempt("denied", ago=61)], NOW)

    assert status.can_retry and status.wait_seconds == 0


def test_no_new_link_after_the_last_try() -> None:
    tries = [attempt("denied", ago=300), attempt("denied", ago=200), attempt("denied", ago=100)]

    status = service._retry_policy(order(), tries, NOW)

    assert not status.can_retry and status.reason == "too_many_attempts"
    assert status.attempts_left == 0


def test_no_new_link_after_the_time_to_pay_is_over() -> None:
    status = service._retry_policy(order(window_ends_in=-1), [attempt("denied", ago=300)], NOW)

    assert not status.can_retry and status.reason == "window_over"


def test_no_new_link_when_the_cooldown_would_outlast_the_time_to_pay() -> None:
    status = service._retry_policy(order(window_ends_in=30), [attempt("denied", ago=10)], NOW)

    assert not status.can_retry and status.reason == "window_over"


def test_a_paid_or_cancelled_order_gets_no_link() -> None:
    for state in ("paid", "cancelled", "expired"):
        status = service._retry_policy(order(status=state), [attempt("denied", ago=300)], NOW)
        assert not status.can_retry and status.reason == "not_payable"


def test_an_unfinished_attempt_does_not_start_a_cooldown() -> None:
    """The link is still open (the customer just hasn't paid): resending it isn't a retry."""
    status = service._retry_policy(order(), [attempt("created", ago=5)], NOW)

    assert status.can_retry and status.wait_seconds == 0
