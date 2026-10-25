"""Money is stored as integer minor units (paise, cents) with an ISO currency code."""

from decimal import Decimal

CURRENCY_SYMBOLS = {"INR": "₹", "USD": "$", "GBP": "£", "EUR": "€"}


def format_money(amount_minor: int, currency: str) -> str:
    """₹60, ₹70.50, $19.99: whole amounts without decimals."""
    amount = Decimal(amount_minor) / 100
    text = f"{amount:.0f}" if amount == amount.to_integral_value() else f"{amount:.2f}"
    return f"{CURRENCY_SYMBOLS.get(currency, currency + ' ')}{text}"
