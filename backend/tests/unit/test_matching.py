import uuid

import pytest

from app.modules.inventory.schemas import StockItem
from app.modules.orders import matching

COOKIES = uuid.uuid4()
CHOCOLATE = StockItem("Scoop cookie", "Chocolate", 6000, "INR", 8, uuid.uuid4(), COOKIES)
RED_VELVET = StockItem("Scoop cookie", "Red velvet", 7000, "INR", 4, uuid.uuid4(), COOKIES)
BROWNIE = StockItem("Brownie", None, 9000, "INR", 15, uuid.uuid4(), uuid.uuid4())
WALNUT_BROWNIE = StockItem("Walnut brownie", None, 11000, "INR", 5, uuid.uuid4(), uuid.uuid4())
STOCK = [BROWNIE, CHOCOLATE, RED_VELVET]


def found(
    product: str,
    variant: str | None = None,
    *,
    stock: list[StockItem] = STOCK,
    aliases: dict[uuid.UUID, list[str]] | None = None,
) -> tuple[StockItem, ...]:
    return matching.find(stock, product, variant, aliases).items


@pytest.mark.parametrize(
    ("product", "variant"),
    [
        ("Scoop cookie", "Chocolate"),
        ("scoop  COOKIE", "chocolate"),
        ("choco cookie", None),
        ("choclate cookie", None),
        ("chocolate scoop", None),
        ("cookie", "choco"),
        ("Scoop cookies", "Chocolate"),
    ],
)
def test_close_names_find_the_chocolate_cookie(product: str, variant: str | None) -> None:
    assert found(product, variant) == (CHOCOLATE,)


def test_product_without_its_variant_asks_which_one() -> None:
    assert found("scoop cookie") == (CHOCOLATE, RED_VELVET)
    assert found("cookies") == (CHOCOLATE, RED_VELVET)


def test_equally_close_products_come_back_together() -> None:
    assert found("brownie", stock=[BROWNIE, WALNUT_BROWNIE]) == (BROWNIE,)  # exact name wins
    assert found("brownies", stock=[BROWNIE, WALNUT_BROWNIE]) == (BROWNIE, WALNUT_BROWNIE)


@pytest.mark.parametrize("product", ["Plum cake", "chocolate brownie", "cake", "2", ""])
def test_unrelated_or_half_matching_names_find_nothing(product: str) -> None:
    assert found(product) == ()


def test_aliases_find_products_by_other_names() -> None:
    aliases = {COOKIES: ["சாக்லேட் குக்கீ", "biscuit"]}

    assert found("சாக்லேட் குக்கீ", aliases=aliases) == (CHOCOLATE, RED_VELVET)
    assert found("biscuit", "red velvet", aliases=aliases) == (RED_VELVET,)
    assert found("சாக்லேட் குக்கீ") == ()  # not without the alias


def test_refs_are_short_and_stable() -> None:
    assert CHOCOLATE.variant_id is not None
    assert CHOCOLATE.ref == f"p{CHOCOLATE.variant_id.hex[:6]}"
    assert StockItem("Loose", None, 100, "INR", 1).ref is None
