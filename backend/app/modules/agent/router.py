"""Which playbook a turn follows, chosen by a small model call (agent-phase-2.md section 6.3).

Regex rules over the customer's words missed real situations ("what else do you have" never
reached the menu playbook), so a short model call now reads the stage and the latest messages and
picks one playbook, using each playbook's `applies_when` line as its description.

- The owner's answer is data, not words: it always gets `owner_answer`, with no model call.
- The customer's words go in a user message, never in the system prompt.
- If the call fails, takes too long or names a playbook it wasn't offered, the rules in
  `context.choose_playbook` decide, so routing never costs a customer their reply.
- AGENT_PLAYBOOK_ROUTER=rules switches back to the rules alone; LLM_ROUTER_MODEL can name a
  cheaper, faster model for this call.
"""

import asyncio
import json
from dataclasses import dataclass
from typing import Literal

import structlog

from app.core.config import get_settings
from app.modules.agent import context, llm, prompt_store
from app.modules.agent.guardrails import inbound
from app.modules.agent.schemas import ChatMessage
from app.modules.conversations.schemas import ChatLine

log = structlog.get_logger()

PROMPT_ID = "router.playbook"
RECENT_MESSAGES = 6  # the latest messages the router reads, the trigger included
MESSAGE_CHARS = 400  # each one cut to this length
CODE_ONLY = frozenset({"owner_answer"})  # chosen by code from the event, never offered


@dataclass(frozen=True)
class Choice:
    playbook: str
    by: Literal["event", "model", "rules"]
    completion: llm.Completion | None = None  # the router's model call, if one answered


def routable() -> list[str]:
    """The playbooks the router may choose from."""
    names = [prompt_id.removeprefix("playbook.") for prompt_id in prompt_store.ids("playbook.")]
    return [name for name in names if name not in CODE_ONLY]


async def choose(
    *, stage: str, history: list[ChatLine], trigger: ChatLine, customer_text: str
) -> Choice:
    """The playbook for a turn that answers `trigger` (the last line of `history`)."""
    if context.event_name(trigger) == "owner_answered":
        return Choice("owner_answer", "event")
    rules = context.choose_playbook(stage, customer_text, trigger.details)
    settings = get_settings()
    if settings.agent_playbook_router != "model":
        return Choice(rules, "rules")
    names = routable()
    media = trigger.sender == "customer" and bool(
        trigger.details.get("story_reply_url") or trigger.details.get("attachments")
    )
    messages = [
        ChatMessage(
            "system",
            prompt_store.render(
                PROMPT_ID,
                stage=stage,
                media=media,
                playbooks=[
                    {"name": name, "applies_when": prompt_store.applies_when(f"playbook.{name}")}
                    for name in names
                ],
            ),
        ),
        ChatMessage("user", transcript(history)),
    ]
    chain = [settings.llm_router_model] if settings.llm_router_model else None
    try:
        async with asyncio.timeout(settings.agent_router_timeout_seconds):
            completion = await llm.complete(messages, json_output=True, model_chain=chain)
    except (llm.LLMError, TimeoutError) as exc:
        log.warning("agent.router_unavailable", error=str(exc)[:200] or "timeout")
        return Choice(rules, "rules")
    name = _parse(completion.content)
    if name not in names:
        log.warning("agent.router_unusable", answer=completion.content[:200])
        return Choice(rules, "rules", completion)
    return Choice(name, "model", completion)


def transcript(history: list[ChatLine]) -> str:
    """The latest messages, one per line, as the router reads them."""
    lines: list[str] = []
    for line in history[-RECENT_MESSAGES:]:
        if line.sender == "customer":
            notes: list[str] = []
            if line.details.get("story") or line.details.get("story_reply_url"):
                notes.append("[replied to a story]")
            if line.details.get("attachments"):
                notes.append(f"[sent: {', '.join(map(str, line.details['attachments']))}]")
            text = _short(inbound.normalise(line.body))
            lines.append("Customer: " + " ".join([*notes, text]).strip())
        elif line.sender == "agent":
            lines.append(f"Shop: {_short(line.body)}")
        elif line.sender == "merchant":
            lines.append(f"Shop owner: {_short(line.body)}")
        else:
            order = context.event_order(line)
            event = context.event_name(line) or "shop_note"
            lines.append(f"[Shop event: {event}{f' {order}' if order else ''}]")
    return "\n".join(lines)


def _short(text: str) -> str:
    return inbound.shorten(text, MESSAGE_CHARS, "…")


def _parse(content: str) -> str | None:
    text = content.strip()
    if text.startswith("```"):
        text = text.strip("`").removeprefix("json").strip()
    try:
        data = json.loads(text)
    except ValueError:
        return None
    name = data.get("playbook") if isinstance(data, dict) else None
    return name.strip().removeprefix("playbook.") if isinstance(name, str) else None
