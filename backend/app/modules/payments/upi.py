"""UPI payment link generation for domestic Indian INR orders.

Generates standard NPCI UPI payment deep-links (upi://pay?...) directly launching
Google Pay, PhonePe, Paytm, or BHIM with prefilled merchant details, amount, and order note.
"""

import urllib.parse
from decimal import Decimal


def create_upi_link(
    *,
    vpa: str,
    payee_name: str,
    amount_minor: int,
    order_number: int,
    currency: str = "INR",
) -> str:
    """Generate a standard NPCI UPI payment deep-link (no QR code needed).

    Format:
        upi://pay?pa={vpa}&pn={payee_name}&am={amount:.2f}&cu=INR&tn=Order_{order_number}

    Args:
        vpa: Merchant Virtual Payment Address (UPI ID), e.g. "baker@okhdfcbank".
        payee_name: Merchant / Shop display name, e.g. "Sweet Crumbs".
        amount_minor: Total order amount in paise (100 paise = 1 INR).
        order_number: Sequential integer order number.
        currency: 3-letter currency code (must be "INR").

    Returns:
        The full `upi://pay?...` deep link URI.

    Raises:
        ValueError: If currency is not INR, vpa is empty, or amount_minor is <= 0.
    """
    if currency.upper() != "INR":
        raise ValueError(f"UPI only supports INR currency, got {currency}")
    if not vpa or not vpa.strip():
        raise ValueError("Merchant UPI ID (VPA) is required to generate a UPI link")
    if amount_minor <= 0:
        raise ValueError(f"Order amount must be positive, got {amount_minor} paise")

    amount_rupees = f"{Decimal(amount_minor) / 100:.2f}"
    params = {
        "pa": vpa.strip(),
        "pn": payee_name.strip(),
        "am": amount_rupees,
        "cu": "INR",
        "tn": f"Order #{order_number}",
    }
    return f"upi://pay?{urllib.parse.urlencode(params, quote_via=urllib.parse.quote)}"
