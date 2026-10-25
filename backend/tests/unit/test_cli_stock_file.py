import pytest

from app.cli import _stock_lines


def test_prices_in_rupees_become_paise() -> None:
    lines = _stock_lines(
        [
            {"product": "Scoop cookie", "variant": "Chocolate", "price": "60", "quantity": 10},
            {"product": "Brownie", "price": 70.5, "quantity": "5"},
        ]
    )

    assert [(line.product, line.variant, line.price_minor, line.quantity) for line in lines] == [
        ("Scoop cookie", "Chocolate", 6000, 10),
        ("Brownie", None, 7050, 5),
    ]


@pytest.mark.parametrize(
    "raw",
    [
        {"product": "Brownie"},
        [{"price": "60", "quantity": 1}],
        [{"product": "Brownie", "price": "abc", "quantity": 1}],
        [{"product": "Brownie", "price": "60.123", "quantity": 1}],
        [{"product": "Brownie", "price": "-1", "quantity": 1}],
    ],
)
def test_invalid_stock_files_are_rejected(raw: object) -> None:
    with pytest.raises(ValueError):
        _stock_lines(raw)
