"""The live rate for charging a rupee order in dollars, because PayPal can't take rupees.

Two public sources are tried in turn and the answer is kept for an hour. If both are down, the
fixed rate in the settings is used, so a checkout never fails for want of a rate. A source whose
answer is far from that fixed rate is treated as wrong.
"""

import time
from decimal import ROUND_CEILING, Decimal

import httpx2
import structlog

from app.core.config import get_settings

log = structlog.get_logger()

# Currencies converted to dollars at checkout: two decimal places like the dollar, and PayPal
# won't take them itself. Others need their own fallback rate before they can be added.
CONVERTIBLE = frozenset({"INR"})
CHARGE_CURRENCY = "USD"

TIMEOUT_SECONDS = 5
_RETRY_AFTER_SECONDS = 300  # after a total failure, ask the sources again sooner than an hour
_MAX_DRIFT = Decimal("0.3")  # a source more than 30% away from the fixed rate is ignored

# (name, url, query): both answer {"rates": {"INR": 94.1, ...}} for one US dollar.
_SOURCES = (
    ("frankfurter", "https://api.frankfurter.dev/v1/latest", {"base": "USD", "symbols": "INR"}),
    ("open-er-api", "https://open.er-api.com/v6/latest/USD", {}),
)

_cache: dict[str, tuple[Decimal, float]] = {}  # currency -> (units per dollar, expires at)


async def per_dollar(currency: str) -> Decimal:
    """How many units of `currency` one US dollar buys now."""
    cached = _cache.get(currency)
    if cached and cached[1] > time.monotonic():
        return cached[0]
    settings = get_settings()
    fixed = Decimal(str(settings.fx_fallback_inr_per_usd))
    for name, url, query in _SOURCES:
        rate = await _fetch(url, query, currency)
        if rate is None:
            log.warning("payments.fx_source_failed", source=name, currency=currency)
        elif abs(rate - fixed) / fixed > _MAX_DRIFT:
            log.warning("payments.fx_rate_implausible", source=name, rate=str(rate))
        else:
            _cache[currency] = (rate, time.monotonic() + settings.fx_cache_minutes * 60)
            return rate
    log.error("payments.fx_using_fixed_rate", currency=currency, rate=str(fixed))
    _cache[currency] = (fixed, time.monotonic() + _RETRY_AFTER_SECONDS)
    return fixed


def to_charge_minor(amount_minor: int, units_per_dollar: Decimal) -> int:
    """Cents to charge for `amount_minor` (paise): rounded up so the shop is never short.

    Both are two-decimal currencies, so minor units divide the same way whole ones do.
    """
    cents = (Decimal(amount_minor) / units_per_dollar).to_integral_value(rounding=ROUND_CEILING)
    return max(int(cents), 1)


async def _fetch(url: str, query: dict[str, str], currency: str) -> Decimal | None:
    try:
        async with httpx2.AsyncClient(timeout=TIMEOUT_SECONDS) as client:
            response = await client.get(url, params=query)
        response.raise_for_status()
        value = response.json()["rates"][currency]
        rate = Decimal(str(value))
    except (httpx2.HTTPError, ValueError, KeyError, TypeError, ArithmeticError):
        return None
    return rate if rate > 0 else None
