"""Output guardrails: every reply is checked before it can reach a customer (section 15).

The model never types an amount, link or order number. It writes tokens such as
`[[price:i3f9a2c]]`, `[[quote_total]]` or `[[payment_link]]`, and code fills them from the
database. Because code fills every amount, the checks on what the model typed can be strict:
any amount, link or promise in the model's own words is rejected.
"""

import re
from collections.abc import Sequence
from dataclasses import dataclass, field
from difflib import SequenceMatcher

MAX_REPLY_BYTES = 2000  # the outbox sends at most two 1,000-byte messages
REPEAT_RATIO = 0.85  # this similar to our last message counts as saying it again

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
# Replies read like a person on the shop's team. Announcing "I am the shop's assistant" or
# "as an AI" is for when a customer asks what they are talking to (see _ASKS_WHAT_IT_IS).
_SELF_INTRO = re.compile(
    r"\b(?:i am|i'm|i’m|im|this is)\b[^.!?\n]{0,40}\b(?:assistant|chat[\s-]?bot|bot|a\.?i\.?)\b",
    re.IGNORECASE,
)
_AI_TALK = re.compile(
    r"\bas an? (?:ai|a\.i\.|virtual assistant)\b|\blanguage model\b|\bchat[\s-]?bot\b"
    r"|\bartificial intelligence\b",
    re.IGNORECASE,
)
_ASKS_WHAT_IT_IS = re.compile(
    r"\b(?:bots?|robots?|a\.?i\.?|humans?|machine|automated|automatic|computer|chat[\s-]?gpt"
    r"|real\s+(?:person|human|people)|(?:a|any)\s+person|who\s+(?:are|r)\s+(?:you|u))\b"
    r"|ரோபோ|மனிதன்|இயந்திர|रोबोट|बॉट|इंसान|मशीन|असली",
    re.IGNORECASE,
)
_STIFF = re.compile(
    r"\bsir\b|\bmadam\b|\bma['’]?am\b|\bkindly\b|\bdo the needful\b|\bplease revert\b",
    re.IGNORECASE,
)
# "I'll check with the shop": a promise only an open Ask me question can keep.
_CHECK_WITH_SHOP = re.compile(
    r"(?:check|confirm|ask)(?:ing)? with the (?:shop|owner|team)|ask(?:ed|ing)? the (?:shop|owner)"
    r"|shop[\s-]*(?:kitta|kitte|la|il)\s+(?:check|kettu|confirm)"
    r"|shop\s+se\s+(?:pooch|puch|check|confirm)|கடையில்\s+கேட்டு|दुकान\s+से\s+पूछ",
    re.IGNORECASE,
)
# An item id ("i3f9a2c"): for tool calls only, never for the customer.
_ITEM_ID = re.compile(r"\bi(?=[0-9a-f]*\d)[0-9a-f]{6}\b", re.IGNORECASE)
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
    # Only tone slipped (an introduction, "madam"), and this is the reply without them. The
    # sender uses it once the model has had its chance to fix the slip: a good reply with a stiff
    # word beats the holding message.
    sanitized: str | None = None


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
    previous_reply: str | None = None,
    expects_new: bool = False,
    mention_one_of: Sequence[str] = (),
) -> Check:
    problems: list[str] = []
    style: list[str] = []  # slips of tone that code can clean up if the model won't
    model_words = _TOKEN.sub(" ", text)  # what the model typed itself

    if _RAW_AMOUNT.search(model_words):
        problems.append(
            "Don't type amounts: use [[price:<item id>]], [[quote_total]] or [[order_total]]"
        )
    if _ITEM_ID.search(model_words) or any(
        re.search(rf"\b{re.escape(item_id)}\b", model_words, re.IGNORECASE)
        for item_id in values.prices
    ):
        problems.append(
            "Don't write item ids (like i3f9a2c) to the customer: write the item's name as "
            "listed. Ids are for tools; prices still use [[price:<item id>]]"
        )
    if not _ASKS_WHAT_IT_IS.search(customer_text) and (
        _SELF_INTRO.search(model_words) or _AI_TALK.search(model_words)
    ):
        style.append(
            "Don't introduce yourself or say what you are (assistant, bot, AI): the customer "
            "didn't ask. Answer like a person on the shop's team"
        )
    if _STIFF.search(model_words):
        style.append(
            "Don't call the customer sir/madam (you don't know who they are) and drop stiff "
            'phrases like "kindly": talk like a person'
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
    # Diet words are fine in a reply that hands the question to the shop (the listing is empty,
    # so asking is the right answer) but not as a claim the shop's data doesn't back.
    defers_to_shop = owner_asked and bool(_CHECK_WITH_SHOP.search(model_words))
    if _HEALTH.search(model_words) and not health_fields_seen and not defers_to_shop:
        problems.append(
            "Health and diet answers (eggless, allergens, ...) need get_product_details first. "
            "If the shop hasn't listed them, call ask_shop_owner and tell the customer you've "
            "asked the shop"
        )

    filled, token_problems = _fill(text, values)
    problems.extend(token_problems)
    script_problem = _script_problem(filled, customer_text)
    if script_problem:
        problems.append(script_problem)
    if expects_new and previous_reply and _repeats(filled, previous_reply):
        problems.append(
            "This repeats your last message. A shop event (the owner's answer, a payment) is "
            "new information for the customer: pass it on instead, and don't answer their "
            "earlier messages again"
        )
    if len(filled.encode()) > MAX_REPLY_BYTES:
        problems.append("The reply is too long: keep it to a few short sentences")
    if not filled.strip():
        problems.append("The reply is empty")
    # A menu answer should also tell the customer about the pre-orders on offer. The model gets
    # one chance to add them; after that the reply goes as it is rather than becoming a holding
    # message.
    if (
        mention_one_of
        and not problems
        and not any(name.lower() in filled.lower() for name in mention_one_of)
    ):
        style.append(
            "Also tell the customer about the pre-orders they can book now: "
            + ", ".join(mention_one_of[:3])
        )
    sanitized = None
    if style and not problems:
        candidate = tidy_style(filled)
        if candidate and not _style_slips(candidate, customer_text):
            sanitized = candidate
    return Check(not (problems or style), filled.strip(), tuple(problems + style), sanitized)


_INTRO_SENTENCE = re.compile(
    r"(?:\b(?:hi|hello|hey|hii+)\b[,!.\s]*)?(?:\bi am\b|\bi'm\b|\bi’m\b|\bim\b|\bthis is\b)"
    r"[^.!?\n]{0,60}\b(?:assistant|chat[\s-]?bot|bot|a\.?i\.?)\b[^.!?\n]*[.!?]?\s*",
    re.IGNORECASE,
)
_ADDRESS = re.compile(
    r"[,\s]*\b(?:sir\s*/\s*madam|madam\s*/\s*sir|sir\s+or\s+madam|sir|madam|ma['’]?am)\b",
    re.IGNORECASE,
)
_OFFICE_SPEAK = re.compile(
    r"\bkindly\s+|\bdo the needful\b[,.]?\s*|\bplease revert\b", re.IGNORECASE
)


def tidy_style(text: str) -> str:
    """The reply without a self-introduction, sir/madam or office-speak, punctuation mended."""
    greeted = bool(re.match(r"\s*(?:hi|hello|hey|hii+)\b", text, re.IGNORECASE))
    text = _INTRO_SENTENCE.sub("Hi! " if greeted else "", text, count=1)
    text = _ADDRESS.sub("", text)
    text = _OFFICE_SPEAK.sub("", text)
    text = re.sub(r"\s+([,.!?])", r"\1", text)
    text = re.sub(r",\s*([.!?])", r"\1", text)
    text = re.sub(r"[ \t]{2,}", " ", text).strip()
    return text[:1].upper() + text[1:]


def _style_slips(text: str, customer_text: str) -> bool:
    asked = bool(_ASKS_WHAT_IT_IS.search(customer_text))
    return bool(
        (not asked and (_SELF_INTRO.search(text) or _AI_TALK.search(text))) or _STIFF.search(text)
    )


def _repeats(reply: str, previous: str) -> bool:
    """Is this reply (nearly) what we already told the customer?"""

    def words(text: str) -> str:
        return " ".join(text.lower().split())

    return SequenceMatcher(None, words(reply), words(previous)).ratio() >= REPEAT_RATIO


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
