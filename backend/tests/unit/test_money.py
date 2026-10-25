from app.core.money import format_money


def test_whole_amounts_have_no_decimals() -> None:
    assert format_money(6000, "INR") == "₹60"
    assert format_money(1000, "USD") == "$10"


def test_fractional_amounts_have_two_decimals() -> None:
    assert format_money(7050, "INR") == "₹70.50"
    assert format_money(1999, "USD") == "$19.99"


def test_unknown_currency_uses_its_code() -> None:
    assert format_money(1250, "SGD") == "SGD 12.50"
