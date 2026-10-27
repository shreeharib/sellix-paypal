import urllib.parse

import pytest

from app.modules.payments.upi import create_upi_link


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
