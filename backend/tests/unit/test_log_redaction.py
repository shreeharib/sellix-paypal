"""Secrets and payment details never reach the logs in clear (agent-phase-2.md 14, item 7)."""

from app.core.logging import redact


def test_secret_fields_are_hashed() -> None:
    event = redact(
        None,
        "info",
        {
            "event": "payments.checkout",
            "access_token": "EAAG-secret",
            "payment_link": "upi://pay?pa=shop@okhdfc&am=120.00",
            "payer_email": "priya@example.com",
            "order_id": "1234",
        },
    )

    assert event["order_id"] == "1234"
    for field in ("access_token", "payment_link", "payer_email"):
        assert str(event[field]).startswith("redacted:")
        assert "secret" not in str(event[field]) and "@" not in str(event[field])


def test_payment_links_inside_other_values_are_hashed() -> None:
    event = redact(
        None,
        "info",
        {"event": "sent", "text": "Pay here: https://www.paypal.com/checkoutnow?token=ABC123"},
    )

    assert "ABC123" not in event["text"]
    assert event["text"].startswith("Pay here: redacted:")
