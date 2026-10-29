"""Does a typed reply to a quote card mean yes? (agent-phase-2.md section 6.4, step 4)

Common answers are recognised by code; anything else goes to a small model call. Only "yes"
can confirm an order: "unclear" makes the agent ask again.
"""

import json
import re
from typing import Literal

import structlog

from app.modules.agent import llm, prompt_store
from app.modules.agent.schemas import ChatMessage

log = structlog.get_logger()

Affirmation = Literal["yes", "no", "change", "unclear"]

_NO = re.compile(
    r"\b(?:no|nope|nah|venam|vendam|venaam|vendaam|nahi|nahin|cancel|don'?t)\b|வேண்டாம்|नहीं",
    re.IGNORECASE,
)
_CHANGE = re.compile(
    r"\b(?:change|maathu|maathanum|maatha|badal|badlo|badlna|instead|add|remove)\b|மாற்ற|बदल",
    re.IGNORECASE,
)
_YES = re.compile(
    r"\b(?:ok|okay|okk|yes|yeah|yep|yup|sure|confirm|confirmed|done|seri|sari|sariya|haan|han"
    r"|theek|thik|chalega|podunga|pannunga)\b|👍|சரி|ஆமா|हाँ|हां|ठीक",
    re.IGNORECASE,
)


async def classify(text: str) -> Affirmation:
    if _NO.search(text):
        return "no"
    if _CHANGE.search(text):
        return "change"
    if _YES.search(text):
        return "yes"
    try:
        completion = await llm.complete(
            [
                ChatMessage("system", prompt_store.render("classifier.affirmation")),
                ChatMessage("user", text[:500]),
            ],
            json_output=True,
        )
        answer = json.loads(completion.content).get("answer")
    except (llm.LLMError, ValueError, AttributeError):
        log.warning("agent.affirmation_unavailable")
        return "unclear"
    return answer if answer in ("yes", "no", "change") else "unclear"
