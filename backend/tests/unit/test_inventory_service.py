import pytest

from app.modules.inventory import service as inventory
from app.modules.inventory.schemas import OpeningStockLine


def test_parse_stock_text_basic_quantity_first() -> None:
    text = "10 Chocolate Brownie 90"
    lines = inventory.parse_stock_text(text)
    assert lines == [
        OpeningStockLine(
            product="Chocolate Brownie",
            variant=None,
            price_minor=9000,
            quantity=10,
            currency="INR",
        )
    ]


def test_parse_stock_text_with_variant_in_parentheses() -> None:
    text = "10 Scoop cookie (Chocolate) 60"
    lines = inventory.parse_stock_text(text)
    assert lines == [
        OpeningStockLine(
            product="Scoop cookie",
            variant="Chocolate",
            price_minor=6000,
            quantity=10,
            currency="INR",
        )
    ]


def test_parse_stock_text_product_first_colon_at() -> None:
    text = "Brownie: 10 @ 90"
    lines = inventory.parse_stock_text(text)
    assert lines == [
        OpeningStockLine(
            product="Brownie",
            variant=None,
            price_minor=9000,
            quantity=10,
            currency="INR",
        )
    ]


def test_parse_stock_text_product_first_dash_and_pieces() -> None:
    text = "Scoop cookie (Red velvet) - 8 pcs - 75.50"
    lines = inventory.parse_stock_text(text)
    assert lines == [
        OpeningStockLine(
            product="Scoop cookie",
            variant="Red velvet",
            price_minor=7550,
            quantity=8,
            currency="INR",
        )
    ]


def test_parse_stock_text_multi_currency_and_symbols() -> None:
    text = """
    # Morning batch
    10 Scoop cookie (Chocolate) ₹60
    5 Brownie 90rs
    8 Croissant 120 INR
    4 Gift box $12.50
    2 Luxury Hamper €45
    """
    lines = inventory.parse_stock_text(text)
    assert lines == [
        OpeningStockLine("Scoop cookie", "Chocolate", 6000, 10, currency="INR"),
        OpeningStockLine("Brownie", None, 9000, 5, currency="INR"),
        OpeningStockLine("Croissant", None, 12000, 8, currency="INR"),
        OpeningStockLine("Gift box", None, 1250, 4, currency="USD"),
        OpeningStockLine("Luxury Hamper", None, 4500, 2, currency="EUR"),
    ]


def test_parse_stock_text_comma_separated_single_line() -> None:
    text = "10 choc cookies 60rs, 5 brownies 90"
    lines = inventory.parse_stock_text(text)
    assert lines == [
        OpeningStockLine("choc cookies", None, 6000, 10, currency="INR"),
        OpeningStockLine("brownies", None, 9000, 5, currency="INR"),
    ]


@pytest.mark.parametrize(
    "invalid_text",
    [
        "",
        "   ",
        "# Only comments\n// another comment",
        "Just a product name without numbers",
        "Brownie 10",
        "-5 Brownie 90",
        "Brownie 10 @ -90",
        "Brownie 10 90.123",  # 3 decimal places
    ],
)
def test_parse_stock_text_rejects_invalid_inputs(invalid_text: str) -> None:
    with pytest.raises(ValueError):
        inventory.parse_stock_text(invalid_text)
