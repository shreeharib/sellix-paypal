"""Shop-type templates: valid data, and the right template for each kind of shop."""

import pytest

from app.modules.shop_profile import shop_types


def test_every_template_loads_with_an_allowed_default() -> None:
    ids = [type_id for type_id, _ in shop_types.all_types()]
    assert {"bakery", "dress_shop", "other"} <= set(ids)
    for type_id in ids:
        schema = shop_types.schema_for(type_id)
        assert schema.shop_type == type_id
        assert schema.default_stock_mode in {mode.id for mode in schema.stock_modes}


def test_only_fresh_batch_shops_can_ever_see_a_shelf_life_question() -> None:
    """Shelf life is for food; other shops keep stock until it sells, or make to order."""
    for type_id, _ in shop_types.all_types():
        schema = shop_types.schema_for(type_id)
        asks = [mode.id for mode in schema.stock_modes if mode.asks_shelf_life]
        if type_id in ("bakery", "other"):
            assert asks == ["daily"]
        else:
            assert asks == [], f"{type_id} would ask how long a product can be sold"


def test_a_handmade_gift_shop_makes_to_order_by_default() -> None:
    schema = shop_types.schema_for("handmade_gifts")

    assert schema.default_stock_mode == "made_to_order"
    assert "lead_time" in {field.key for field in schema.detail_fields}


def test_a_dress_shop_is_never_asked_how_long_it_can_sell_something() -> None:
    schema = shop_types.schema_for("dress_shop")

    assert schema.default_stock_mode == "inventory"
    assert [mode.id for mode in schema.stock_modes] == ["inventory", "made_to_order"]
    assert not any(mode.asks_shelf_life for mode in schema.stock_modes)
    assert {field.key for field in schema.detail_fields} >= {"sizes", "colours", "fabric"}


def test_a_bakery_makes_fresh_batches_and_has_a_shelf_life_question() -> None:
    schema = shop_types.schema_for("bakery")

    assert schema.default_stock_mode == "daily"
    assert [mode.id for mode in schema.stock_modes if mode.asks_shelf_life] == ["daily"]
    assert [option.days for option in schema.shelf_life_options] == [1, 3, 7, 30]
    assert "allergens" in {field.key for field in schema.detail_fields}


@pytest.mark.parametrize(
    ("category", "expected"),
    [
        ("Food and sweets", "bakery"),
        ("Bakery", "bakery"),
        ("Home bakery & cakes", "bakery"),
        ("Clothing", "dress_shop"),
        ("Women's fashion boutique", "dress_shop"),
        ("Sarees", "dress_shop"),
        ("Jewellery", "jewellery"),
        ("Fashion jewellery", "jewellery"),
        ("Clothing & accessories", "dress_shop"),
        ("Skin care and beauty", "beauty"),
        ("Makeup artist", "beauty"),
        ("Plant nursery", "plants"),
        ("Handmade gifts", "handmade_gifts"),
        ("Handmade jewellery", "jewellery"),
        ("Electronics", "other"),
        ("", "other"),
        (None, "other"),
    ],
)
def test_the_category_picks_a_template_when_no_type_was_chosen(
    category: str | None, expected: str
) -> None:
    assert shop_types.schema_for(None, category).shop_type == expected


def test_a_chosen_type_beats_the_category_and_an_unknown_one_is_ignored() -> None:
    assert shop_types.schema_for("dress_shop", "Bakery").shop_type == "dress_shop"
    assert shop_types.schema_for("spaceship", "Bakery").shop_type == "bakery"
