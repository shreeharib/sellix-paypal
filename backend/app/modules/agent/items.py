"""Short, stable item ids the model uses instead of names (agent-phase-2.md section 5.1).

An id is "i" and the first six hex digits of the variant's UUID, so it never changes while the
item exists, and code can always map it back. The model can't misspell an id into another item:
an unknown id is an error it has to fix.
"""

import uuid
from collections.abc import Iterable

from app.modules.inventory.schemas import StockItem


def ref(variant_id: uuid.UUID) -> str:
    return f"i{variant_id.hex[:6]}"


def resolve(item_id: str, stock: Iterable[StockItem]) -> StockItem | None:
    """The stock item with this id, or None if there's none (or, rarely, two)."""
    wanted = item_id.strip().lower()
    matches = [item for item in stock if item.variant_id and ref(item.variant_id) == wanted]
    return matches[0] if len(matches) == 1 else None
