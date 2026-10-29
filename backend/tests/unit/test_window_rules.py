from datetime import UTC, datetime, timedelta

import pytest

from app.modules.conversations import window

NOW = datetime(2026, 10, 29, 12, 0, tzinfo=UTC)


def ago(**delta: float) -> datetime:
    return NOW - timedelta(**delta)


@pytest.mark.parametrize(
    ("last_customer_message_at", "state"),
    [
        (ago(minutes=5), "open"),
        (ago(hours=21, minutes=59), "open"),
        (ago(hours=22, minutes=30), "closing"),
        (ago(hours=24, minutes=1), "human_agent_only"),
        (ago(days=6, hours=23), "human_agent_only"),
        (ago(days=7, minutes=1), "closed"),
        (None, "closed"),
    ],
)
def test_window_state_follows_the_customers_last_message(
    last_customer_message_at: datetime | None, state: str
) -> None:
    assert window.window_at(last_customer_message_at, NOW).state == state


def test_the_window_closes_24_hours_after_the_customers_last_message() -> None:
    current = window.window_at(ago(hours=3), NOW)

    assert current.closes_at == NOW + timedelta(hours=21)
    assert current.human_agent_until == NOW + timedelta(days=7) - timedelta(hours=3)


@pytest.mark.parametrize(
    ("last_customer_message_at", "policy", "human_agent_enabled", "decision"),
    [
        (ago(hours=1), "standard", False, "send"),
        (ago(hours=23), "standard", False, "send"),
        (ago(hours=30), "standard", True, "wait"),
        (ago(hours=30), "when_open", True, "wait"),
        (ago(hours=30), "human_agent", True, "send_tagged"),
        (ago(hours=30), "human_agent", False, "wait"),
        (ago(hours=1), "human_agent", True, "send"),
        (ago(days=8), "human_agent", True, "expire"),
        (ago(days=8), "standard", False, "expire"),
    ],
)
def test_what_the_outbox_may_do(
    last_customer_message_at: datetime,
    policy: window.WindowPolicy,
    human_agent_enabled: bool,
    decision: str,
) -> None:
    current = window.window_at(last_customer_message_at, NOW)

    assert window.decide(current, policy, human_agent_enabled=human_agent_enabled) == decision
