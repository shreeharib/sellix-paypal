"""Output guardrails: every reply is checked before it can reach a customer (section 15).

The model never types an amount, link or order number. It writes tokens such as
`[[price:i3f9a2c]]`, `[[quote_total]]` or `[[payment_link]]`, and code fills them from the
database. Because code fills every amount, the checks on what the model typed can be strict:
any amount, link or promise in the model's own words is rejected.
"""

import re
from collections.abc import Sequence
from dataclasses import dataclass, field

MAX_REPLY_BYTES = 2000  # the outbox sends at most two 1,000-byte messages

_TOKEN = re.compile(r"\[\[([^\[\]]*)\]\]")
_CURRENCY = r"(?:₹|\$|rs\.?|inr|usd|rupees?|rupa[iy]?|rupaay|ரூ\.?|ரூபாய்|रु\.?|रुपये|रुपया|dollars?)"
_NUMBER = r"\d[\d,]*(?:\.\d+)?"
_MONEY_WORDS = r"(?:total|price|cost|amount|rate|mothham|motham|mottham|மொத்தம்|விலை|कुल|दाम|कीमत)"
_RAW_AMOUNT = re.compile(
    rf"{_CURRENCY}\s*{_NUMBER}|{_NUMBER}\s*{_CURRENCY}(?![a-z])"
    rf"|{_MONEY_WORDS}\W{{0,3}}(?:\w+\W+)?{_NUMBER}",
    re.IGNORECASE,
)
_LINK = re.compile(
    r"https?://|www\.|\b[\w-]+\.(?:com|in|net|org|me|link|ly|co|shop|store|app|io)\b",
    re.IGNORECASE,
)
# Things only the shop may offer. Each shop adds its own list in Settings.
_PROMISES = re.compile(
    r"\bfree\b|\bdiscounts?\b|\boffers?\b|\d+\s*%\s*off\b|\bcashback\b|\bguarantee"
    r"|\b(?:in|within)\s+(?:\d+|an?|one|two)\s*(?:min|mins|minutes?|hours?|hrs?)\b"
    r"|இலவச|தள்ளுபடி|\bilavasam|\bmuft|मुफ्त|छूट|\bchhoot",
    re.IGNORECASE,
)
_HEALTH = re.compile(
    r"\begg[\s-]?less\b|\begg[\s-]?free\b|\bvegan\b|\bgluten|\bnut[\s-]?free\b|\bnuts?\b"
    r"|\ballerg|\bsugar[\s-]?free\b|\bjain\b|\bdairy\b|\blactose\b|\bdiabetic",
    re.IGNORECASE,
)
# "I'll check with the shop": a promise only an open Ask me question can keep.
_CHECK_WITH_SHOP = re.compile(
    r"(?:check|confirm|ask)(?:ing)? with the (?:shop|owner|team)|ask the (?:shop|owner)"
    r"|shop[\s-]*(?:kitta|kitte|la|il)\s+(?:check|kettu|confirm)"
    r"|shop\s+se\s+(?:pooch|puch|check|confirm)|கடையில்\s+கேட்டு|दुकान\s+से\s+पूछ",
    re.IGNORECASE,
)
_TAMIL = re.compile(r"[஀-௿]")
_DEVANAGARI = re.compile(r"[ऀ-ॿ]")
_LATIN = re.compile(r"[A-Za-z]")


@dataclass(frozen=True)
class TokenValues:
    """What code fills into this turn's reply. Missing values make their tokens invalid."""

    prices: dict[str, str] = field(default_factory=dict)  # item id -> formatted price
    quote_total: str | None = None
    order_total: str | None = None
    order_number: str | None = None
    payment_link: str | None = None


@dataclass(frozen=True)
class Check:
    ok: bool
    text: str  # with tokens filled in (only meaningful when ok)
    problems: tuple[str, ...]


def has_amount(text: str) -> bool:
    """Does this text contain an amount (in any of the forms the reply check rejects)?"""
    return bool(_RAW_AMOUNT.search(_TOKEN.sub(" ", text)))


def check_reply(
    text: str,
    *,
    values: TokenValues,
    customer_text: str,
    health_fields_seen: bool,
    never_promise: Sequence[str],
    owner_asked: bool = True,
) -> Check:
    problems: list[str] = []
    model_words = _TOKEN.sub(" ", text)  # what the model typed itself

    if _RAW_AMOUNT.search(model_words):
        problems.append(
            "Don't type amounts: use [[price:<item id>]], [[quote_total]] or [[order_total]]"
        )
    if _LINK.search(model_words):
        problems.append("Don't type links: use [[payment_link]] for the payment link")
    if _PROMISES.search(model_words) or any(
        phrase.strip() and phrase.strip().lower() in model_words.lower() for phrase in never_promise
    ):
        problems.append(
            "Don't promise discounts, free items, offers or delivery times: ask the shop owner"
        )
    if _CHECK_WITH_SHOP.search(model_words) and not owner_asked:
        problems.append(
            "You told the customer you'll check with the shop: call ask_shop_owner first, so the "
            "owner actually gets the question"
        )
    if _HEALTH.search(model_words) and not health_fields_seen:
        problems.append(
            "Health and diet answers (eggless, allergens, ...) need get_product_details first"
        )

    filled, token_problems = _fill(text, values)
    problems.extend(token_problems)
    script_problem = _script_problem(filled, customer_text)
    if script_problem:
        problems.append(script_problem)
    if len(filled.encode()) > MAX_REPLY_BYTES:
        problems.append("The reply is too long: keep it to a few short sentences")
    if not filled.strip():
        problems.append("The reply is empty")
    return Check(not problems, filled.strip(), tuple(problems))


def _fill(text: str, values: TokenValues) -> tuple[str, list[str]]:
    problems: list[str] = []

    def replace(match: re.Match[str]) -> str:
        token = match.group(1).strip()
        value: str | None
        if token.startswith("price:"):
            value = values.prices.get(token.removeprefix("price:").strip())
        else:
            value = {
                "quote_total": values.quote_total,
                "order_total": values.order_total,
                "order_number": values.order_number,
                "payment_link": values.payment_link,
            }.get(token)
        if value is None:
            problems.append(f"[[{token}]] can't be used here (unknown, or nothing to fill it)")
            return match.group(0)
        return value

    return _TOKEN.sub(replace, text), problems


def _script_problem(reply: str, customer_text: str) -> str | None:
    customer = _script(customer_text)
    if customer is None:
        return None
    replied = _script(reply)
    if customer == "tamil" and not _TAMIL.search(reply):
        return "The customer writes in Tamil script: reply in Tamil script"
    if customer == "devanagari" and not _DEVANAGARI.search(reply):
        return "The customer writes in Devanagari: reply in Devanagari"
    if customer == "latin" and replied in ("tamil", "devanagari"):
        return "The customer writes in English letters: reply in English letters"
    return None


def _script(text: str) -> str | None:
    counts = {
        "tamil": len(_TAMIL.findall(text)),
        "devanagari": len(_DEVANAGARI.findall(text)),
        "latin": len(_LATIN.findall(text)),
    }
    script, count = max(counts.items(), key=lambda item: item[1])
    return script if count else None
