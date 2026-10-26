"""Fixed messages code sends a customer without the model, in the customer's language."""

from app.modules.agent.validator import dominant_script

# Sent instead of a reply that couldn't be checked or repaired.
_HOLDING = {
    "ta": "கடையிடம் கேட்டுவிட்டு விரைவில் பதில் சொல்கிறேன்.",
    "ta-en": "Shop-la check panni seekiram solren.",
    "hi": "दुकान से पूछकर जल्द ही जवाब देते हैं।",
    "hi-en": "Shop se check karke jaldi batate hain.",
    "en": "Let me check with the shop and get back to you shortly.",
}
# Sent once when the customer has waited a while for the merchant's answer.
_FOLLOW_UP = {
    "ta": "காத்திருக்க வைத்ததற்கு மன்னிக்கவும்! கடை இப்போது கொஞ்சம் பிஸியாக உள்ளது, பதில் வந்ததும் உடனே சொல்கிறேன்.",
    "ta-en": "Wait panna vachathukku sorry! Shop konjam busy-a irukku, avanga reply pannadhum "
    "udane solren.",
    "hi": "इंतज़ार के लिए माफ़ कीजिए! दुकान अभी थोड़ी व्यस्त है, जवाब आते ही बताते हैं।",
    "hi-en": "Wait karwane ke liye sorry! Shop abhi thoda busy hai, jawab aate hi batate hain.",
    "en": "Sorry for the wait! The shop is a little busy right now. We'll reply as soon as they "
    "get back to us.",
}


def holding_message(language: str | None, customer_text: str) -> str:
    return _in_language(_HOLDING, language, customer_text)


def follow_up_message(language: str | None, customer_text: str) -> str:
    return _in_language(_FOLLOW_UP, language, customer_text)


def _in_language(texts: dict[str, str], language: str | None, customer_text: str) -> str:
    """The customer's script decides first; then the language the agent last replied in."""
    script = dominant_script(customer_text)
    if script == "Tamil":
        return texts["ta"]
    if script == "Devanagari":
        return texts["hi"]
    return texts.get((language or "").lower(), texts["en"])
