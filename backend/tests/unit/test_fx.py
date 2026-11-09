"""The dollar rate used to charge a rupee order through PayPal: rounding, sources, fallback."""

from collections.abc import Iterator
from decimal import Decimal

import pytest

from app.core.config import get_settings
from app.modules.payments import fx


@pytest.fixture(autouse=True)
def fresh_cache(monkeypatch: pytest.MonkeyPatch) -> Iterator[None]:
    monkeypatch.setattr(get_settings(), "fx_fallback_inr_per_usd", 94.0)
    fx._cache.clear()
    yield
    fx._cache.clear()


def test_the_charge_is_rounded_up_so_the_shop_is_never_short() -> None:
    assert fx.to_charge_minor(89900, Decimal("94")) == 957  # 956.38 cents
    assert fx.to_charge_minor(18000, Decimal("94")) == 192  # 191.49 cents
    assert fx.to_charge_minor(9400, Decimal("94")) == 100  # exactly $1


def test_the_charge_is_never_zero() -> None:
    assert fx.to_charge_minor(1, Decimal("94")) == 1


@pytest.mark.anyio
async def test_the_first_source_is_used_and_the_answer_is_kept(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    asked: list[str] = []

    async def fetch(url: str, query: dict[str, str], currency: str) -> Decimal | None:
        asked.append(url)
        return Decimal("93.9")

    monkeypatch.setattr(fx, "_fetch", fetch)

    assert await fx.per_dollar("INR") == Decimal("93.9")
    assert await fx.per_dollar("INR") == Decimal("93.9")
    assert len(asked) == 1


@pytest.mark.anyio
async def test_the_second_source_answers_when_the_first_is_down(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    async def fetch(url: str, query: dict[str, str], currency: str) -> Decimal | None:
        return None if "frankfurter" in url else Decimal("94.2")

    monkeypatch.setattr(fx, "_fetch", fetch)

    assert await fx.per_dollar("INR") == Decimal("94.2")


@pytest.mark.anyio
async def test_a_rate_far_from_the_fixed_one_is_ignored(monkeypatch: pytest.MonkeyPatch) -> None:
    async def fetch(url: str, query: dict[str, str], currency: str) -> Decimal | None:
        return Decimal("9.4") if "frankfurter" in url else Decimal("94.2")

    monkeypatch.setattr(fx, "_fetch", fetch)

    assert await fx.per_dollar("INR") == Decimal("94.2")


@pytest.mark.anyio
async def test_the_fixed_rate_is_used_when_every_source_is_down(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    async def fetch(url: str, query: dict[str, str], currency: str) -> Decimal | None:
        return None

    monkeypatch.setattr(fx, "_fetch", fetch)

    assert await fx.per_dollar("INR") == Decimal("94.0")
