"""Shop-type templates: which stock behaviours and product details a kind of shop gets.

The data is in shop_types.yaml and is checked when this module loads, so a bad template stops the
app starting instead of breaking one merchant's add-product screen. The four stock behaviours
are fixed in code (they change holds, carry-over and restocking); templates only choose among them.
Other modules reach this through `shop_profile.service`, not directly.
"""

import re
from dataclasses import dataclass
from pathlib import Path

import yaml

from app.modules.shop_profile.schemas import (
    DetailField,
    ProductSchema,
    ShelfLifeOption,
    StockModeOption,
    Vocabulary,
)

_DATA = Path(__file__).with_name("shop_types.yaml")
FALLBACK_TYPE = "other"


@dataclass(frozen=True)
class _Entry:
    schema: ProductSchema
    match: list[str]


def _load() -> dict[str, _Entry]:
    raw = yaml.safe_load(_DATA.read_text(encoding="utf-8"))
    modes = {key: StockModeOption(id=key, **value) for key, value in raw["stock_modes"].items()}
    shelf = [ShelfLifeOption(**option) for option in raw["shelf_life_options"]]
    entries: dict[str, _Entry] = {}
    for type_id, spec in raw["types"].items():
        schema = ProductSchema(
            shop_type=type_id,
            label=spec["label"],
            version=raw["version"],
            default_stock_mode=spec["default_stock_mode"],
            stock_modes=[modes[mode_id] for mode_id in spec["stock_modes"]],
            shelf_life_options=shelf,
            detail_fields=[DetailField(**field) for field in spec["detail_fields"]],
            vocabulary=Vocabulary(**spec["vocabulary"]),
        )
        entries[type_id] = _Entry(schema=schema, match=[word.lower() for word in spec["match"]])
    if FALLBACK_TYPE not in entries:
        raise ValueError(f"shop_types.yaml needs a '{FALLBACK_TYPE}' type")
    return entries


_TYPES = _load()


def all_types() -> list[tuple[str, str]]:
    """(id, label) of every shop type, in file order: for a chooser."""
    return [(type_id, entry.schema.label) for type_id, entry in _TYPES.items()]


def schema_for(shop_type: str | None, category: str | None = None) -> ProductSchema:
    """The template for this shop: the type it picked, else the best match for its category."""
    if shop_type and shop_type in _TYPES:
        return _TYPES[shop_type].schema
    text = re.sub(r"\s+", " ", (category or "").lower())
    for entry in _TYPES.values():
        if any(word in text for word in entry.match):
            return entry.schema
    return _TYPES[FALLBACK_TYPE].schema
