"""Checks every reply before it reaches the customer. Unchecked text is never sent.

Each problem is phrased as an instruction, so the agent can repair its reply once. A reply
that still fails is replaced by a holding message (templates.holding_message).
"""

import re
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation

MAX_TEXT_LENGTH = 1000  # Instagram's limit for one message

_NUMBER = r"\d[\d,]*(?:\.\d{1,2})?"
_CURRENCY_BEFORE = re.compile(rf"(?:₹|\brs\.?|\binr|\brupees?|\$|\busd)\s*({_NUMBER})", re.I)
_CURRENCY_AFTER = re.compile(
    rf"({_NUMBER})\s*(?:₹|rs\b\.?|rupees?\b|inr\b|/-|usd\b|dollars?\b)", re.I
)
_LINK = re.compile(
    r"https?://|www\.|\b[\w-]+\.(?:com|in|net|org|io|me|ly|co|link|app|shop|store)\b(?:/\S*)?",
    re.I,
)
# Promises the agent may never make: code and the merchant decide these.
_PROMISES = (
    (re.compile(r"\b\d{1,2}\s?%\s?(?:off|discount|kammi|less|thallupadi)\b", re.I), "discounts"),
    (re.compile(r"\bfree\s+(?:home\s+)?deliver", re.I), "free delivery"),
    (
        re.compile(
            r"\b(?:deliver\w*|reach\w*|arriv\w*)\b[^.!?\n]{0,20}\b(?:with)?in\s+\d+\s*"
            r"(?:min\w*|hr\w*|hour\w*)",
            re.I,
        ),
        "delivery times",
    ),
)
_SCRIPTS = {"Tamil": (0x0B80, 0x0BFF), "Devanagari": (0x0900, 0x097F)}


@dataclass(frozen=True)
class ReplyFacts:
    """What code knows this turn, to check the reply against."""

    # Every amount code produced: today's prices, quote lines and totals, amounts in genuine
    # shop-system notes. In minor units (paise, cents).
    amounts_minor: frozenset[int]
    customer_text: str  # the customer's latest message


def check(reply: str, facts: ReplyFacts) -> list[str]:
    problems = []
    if len(reply) > MAX_TEXT_LENGTH - 200:  # room for the payment link
        problems.append("The reply is too long: keep it to 1-3 short sentences.")
    if _LINK.search(reply.replace("{payment_link}", "")):
        problems.append(
            "Don't write links or web addresses: the system adds the payment link where "
            "{payment_link} is."
        )
    unknown = sorted({amount for amount in amounts_in(reply) if amount not in facts.amounts_minor})
    if unknown:
        listed = ", ".join(_plain(amount) for amount in unknown)
        problems.append(
            f"The amount(s) {listed} aren't prices or totals from today's stock or the shop "
            "system: use only those, or leave amounts out."
        )
    for pattern, topic in _PROMISES:
        if pattern.search(reply):
            problems.append(
                f"Don't promise {topic}: only the shop can. Say you'll check with the shop."
            )
    wanted = dominant_script(facts.customer_text)
    if wanted is not None and _letters(reply, wanted) == 0 and _latin_letters(reply) >= 4:
        problems.append(f"The customer writes in {wanted} script: reply in {wanted} script too.")
    return problems


def amounts_in(text: str) -> set[int]:
    """Money amounts written with a currency, in minor units."""
    found = set()
    for pattern in (_CURRENCY_BEFORE, _CURRENCY_AFTER):
        for match in pattern.finditer(text):
            try:
                value = Decimal(match.group(1).replace(",", ""))
            except InvalidOperation:
                continue
            found.add(int(value * 100))
    return found


def dominant_script(text: str) -> str | None:
    """Tamil or Devanagari when most of the letters are in it; None for Latin or unclear."""
    letters = sum(1 for char in text if char.isalpha())
    for name in _SCRIPTS:
        count = _letters(text, name)
        if count >= 3 and count >= 0.6 * letters:
            return name
    return None


def _letters(text: str, script: str) -> int:
    low, high = _SCRIPTS[script]
    return sum(1 for char in text if low <= ord(char) <= high and char.isalpha())


def _latin_letters(text: str) -> int:
    return sum(1 for char in text if char.isascii() and char.isalpha())


def _plain(amount_minor: int) -> str:
    whole, cents = divmod(amount_minor, 100)
    return f"{whole}.{cents:02d}" if cents else str(whole)
