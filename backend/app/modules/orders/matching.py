"""Finding which of today's items a customer means, from the words the agent passed on.

Tolerates typos ("choclate"), short forms ("choco"), word order ("chocolate scoop") and the
merchant's aliases (Tamil or Hindi names, nicknames). It never guesses between close
candidates: those come back together so the agent asks which one.
"""

import unicodedata
import uuid
from dataclasses import dataclass
from difflib import SequenceMatcher

from app.modules.inventory.schemas import StockItem

MIN_SCORE = 0.75  # how well every word of the request must match, on average
TIE_MARGIN = 0.05  # candidates this close to the best are equally likely
MIN_WORD_RATIO = 0.75  # spelling similarity for two words to count as the same


@dataclass(frozen=True)
class Match:
    items: tuple[StockItem, ...]  # one: found; several: ask which; none: not in stock


def find(
    stock: list[StockItem],
    product: str,
    variant: str | None,
    aliases: dict[uuid.UUID, list[str]] | None = None,
) -> Match:
    """`aliases` maps a product ID to the product's other names."""
    exact = [
        item
        for item in stock
        if _normal(item.product) == _normal(product)
        and (variant is None or _normal(item.variant or "") == _normal(variant))
    ]
    if exact:
        return Match(tuple(exact))

    wanted = [word for word in _words(f"{product} {variant or ''}") if not word.isdigit()]
    if not wanted:
        return Match(())
    scored = [(_score(wanted, item, _aliases_of(item, aliases)), item) for item in stock]
    best = max((score for score, _ in scored), default=0.0)
    if best < MIN_SCORE:
        return Match(())
    return Match(tuple(item for score, item in scored if score >= best - TIE_MARGIN))


def _aliases_of(item: StockItem, aliases: dict[uuid.UUID, list[str]] | None) -> list[str]:
    return (aliases or {}).get(item.product_id, []) if item.product_id else []


def _score(wanted: list[str], item: StockItem, aliases: list[str]) -> float:
    variant_words = _words(item.variant or "")
    return max(
        sum(_word_score(word, [*_words(name), *variant_words]) for word in wanted) / len(wanted)
        for name in (item.product, *aliases)
    )


def _word_score(word: str, candidates: list[str]) -> float:
    best = 0.0
    for candidate in candidates:
        if word == candidate:
            return 1.0
        if min(len(word), len(candidate)) >= 3 and (
            candidate.startswith(word) or word.startswith(candidate)
        ):
            best = max(best, 0.9)
            continue
        ratio = SequenceMatcher(None, word, candidate).ratio()
        if ratio >= MIN_WORD_RATIO:
            best = max(best, ratio)
    return best


def _words(text: str) -> list[str]:
    """Lower-case words, split on spaces, punctuation and symbols. Combining marks (Tamil and
    Hindi vowel signs) stay inside their words."""
    cleaned = "".join(
        " " if unicodedata.category(char)[0] in "PSZ" else char
        for char in unicodedata.normalize("NFKC", text.lower())
    )
    return cleaned.split()


def _normal(text: str) -> str:
    return " ".join(_words(text))
