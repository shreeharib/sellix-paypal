"""Does a typed reply to a quote card place the order? (agent-phase-2.md section 6.4, step 4)

A typed reply places an order only when it clearly asks for it ("confirm", "place the order",
"book it", "confirm pannunga", "order kar do"). A plain acknowledgement ("ok", "sure", "seri",
"haan", a thumbs-up) is "unclear": the customer may be answering something else, so the agent
points them to the Confirm button. Messages the code can't read go to a small model call.
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
# Words that ask for the order to be placed.
_STRONG = re.compile(
    r"\b(?:confirm|confirmed|go ahead"
    r"|place (?:the |my |this |that )?order"
    r"|book (?:it|that|this|them|pannunga|pannu|pannidunga|karo|kar do|kardo|kar dijiye)"
    r"|order (?:pannunga|pannu|pannidunga|pannirunga|podunga|podu"
    r"|karo|kar do|kardo|kar dijiye|kardijiye)"
    r"|uruthi)\b"
    r"|உறுதி|கன்பார்ம்|கன்ஃபர்ம்|ஆர்டர் பண்ணுங்க|ஆர்டர் போடுங்க|कन्फर्म|ऑर्डर कर|बुक कर",
    re.IGNORECASE,
)
# A strong word next to one of these isn't a clear request ("not confirm yet", "how do I
# confirm?"): the model decides.
_HOLD = re.compile(
    r"\b(?:not|yet|wait|later|illa|ila|mat|how|why|what|when|should|shall|can i|do i"
    r"|kaise|kya|eppadi|epdi|enna)\b|\?",
    re.IGNORECASE,
)
# Acknowledgements: fine as an answer, never enough to place an order.
_WEAK = re.compile(
    r"\b(?:ok|okay|okk|k|kk|yes|yeah|yep|yup|ya|sure|fine|done|alright|cool|great|perfect"
    r"|sounds good|looks good|seri|sari|sariya|haan|han|ha|theek|thik|chalega|podunga|pannunga)\b"
    r"|👍|👌|சரி|ஆமா|हाँ|हां|ठीक",
    re.IGNORECASE,
)


async def classify(text: str) -> Affirmation:
    if _NO.search(text):
        return "no"
    if _CHANGE.search(text):
        return "change"
    if _STRONG.search(text) and not _HOLD.search(text):
        return "yes"
    if _WEAK.search(text):
        return "unclear"
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
