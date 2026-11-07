import pytest

from app.core.ratelimit import WINDOW_SECONDS, RateLimiter, Rule, client_key, rule_for


def test_allows_up_to_the_limit_then_says_when_to_retry() -> None:
    limiter = RateLimiter()

    assert [limiter.hit("k", 3, now=100.0) for _ in range(3)] == [None, None, None]
    retry = limiter.hit("k", 3, now=100.0)

    assert retry is not None
    assert 1 <= retry <= WINDOW_SECONDS


def test_a_new_minute_starts_a_new_count() -> None:
    limiter = RateLimiter()
    for _ in range(3):
        limiter.hit("k", 3, now=100.0)

    assert limiter.hit("k", 3, now=100.0 + WINDOW_SECONDS) is None


def test_clients_are_counted_separately_and_zero_means_unlimited() -> None:
    limiter = RateLimiter()
    limiter.hit("a", 1, now=5.0)

    assert limiter.hit("a", 1, now=5.0) is not None
    assert limiter.hit("b", 1, now=5.0) is None
    assert all(limiter.hit("c", 0, now=5.0) is None for _ in range(100))


def test_paths_get_their_own_rule() -> None:
    assert rule_for("/health") is None
    assert rule_for("/v1/auth/token") == Rule("auth", rule_for("/v1/auth/token").limit)  # type: ignore[union-attr]
    assert rule_for("/webhooks/meta").name == "webhook"  # type: ignore[union-attr]
    assert rule_for("/v1/orders").name == "api"  # type: ignore[union-attr]


@pytest.mark.parametrize("header", ["", "Bearer not-a-token", "Basic abc"])
def test_unverifiable_callers_are_counted_by_address(header: str) -> None:
    scope = {
        "type": "http",
        "headers": [(b"authorization", header.encode())],
        "client": ("203.0.113.9", 5000),
    }

    assert client_key(scope, Rule("api", 10)) == "ip:203.0.113.9"
