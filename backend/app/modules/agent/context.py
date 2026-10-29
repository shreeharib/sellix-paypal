"""What the model sees in a turn (agent-phase-2.md sections 6.3 and 8.1).

1. system: base.md (stable, cached), the playbook for this turn, then the context block.
2. The conversation: the customer's messages as `user` messages (never in the system prompt),
   our replies as `assistant` messages, the merchant's own Instagram messages as `assistant`
   messages marked by code.
3. Shop events (payment received, hold expired, the owner's answer) as a synthetic `shop_event`
   tool call and its result: nothing a customer types can look like one.
"""

import json
import re
import uuid
from dataclasses import dataclass
from datetime import date, datetime
from zoneinfo import ZoneInfo

from app.core.config import get_settings
from app.modules.agent import items, llm, prompt_store
from app.modules.agent.guardrails import inbound
from app.modules.agent.tools.registry import TurnContext
from app.modules.conversations.schemas import ChatLine
from app.modules.orders.schemas import SavedQuote

SHOP_EVENT = "shop_event"

_COMPLAINT = re.compile(
    r"\b(?:complain|complaint|refund|bad|stale|worst|disappointed|wrong order|not happy|"
    r"mosam|kevalam|bekar|kharab)\b",
    re.IGNORECASE,
)
_STATUS = re.compile(
    r"\b(?:where is|status|when will|enga irukku|eppo varum|kab aayega|kahan hai)\b",
    re.IGNORECASE,
)
_PRODUCT = re.compile(
    r"\b(?:ingredient|allerg|egg|eggless|vegan|gluten|nut|sugar|jain|dairy|contain|size|"
    r"flavou?r)\w*",
    re.IGNORECASE,
)
_CUSTOM = re.compile(
    r"\b(?:custom|photo cake|birthday|anniversary|bulk|tomorrow|naalaikku|kal|saturday|sunday|"
    r"monday|tuesday|wednesday|thursday|friday)\b",
    re.IGNORECASE,
)
_GREETING = re.compile(
    r"^\W*(?:hi|hello|hey|hii+|vanakkam|namaste|good (?:morning|evening))\W*$", re.IGNORECASE
)
_PAYMENT_STAGES = ("payment_pending",)
_ORDER_STAGES = ("collecting_details", "awaiting_confirmation")


@dataclass(frozen=True)
class Context:
    messages: list[llm.Message]
    playbook: str


def choose_playbook(stage: str, text: str, details: dict[str, object]) -> str:
    """One playbook per turn, from the stage and cheap checks on the latest message."""
    if stage in _ORDER_STAGES:
        return "new_order"
    if details.get("story_reply_url") or details.get("attachments"):
        return "story_or_photo"
    if _COMPLAINT.search(text):
        return "complaint"
    if stage in _PAYMENT_STAGES:
        return "order_status" if _STATUS.search(text) else "payment_problem"
    if _STATUS.search(text):
        return "order_status"
    if _PRODUCT.search(text):
        return "product_question"
    if _CUSTOM.search(text):
        return "custom_or_future_order"
    if _GREETING.match(text):
        return "small_talk"
    return "new_order"


def build(
    ctx: TurnContext,
    *,
    history: list[ChatLine],
    profile: str | None,
    draft: dict[str, object],
    quote: SavedQuote | None,
    open_questions: list[str],
    window_closing: bool,
    trigger: ChatLine,
    facts: list[tuple[str, object]] = (),  # pyright: ignore[reportArgumentType]
    rules: list[tuple[str, str]] = (),  # pyright: ignore[reportArgumentType]
    glossary: list[tuple[str, str]] = (),  # pyright: ignore[reportArgumentType]
    summary: str | None = None,
) -> Context:
    playbook = choose_playbook(ctx.stage, ctx.customer_text, trigger.details)
    system = "\n\n".join(
        [
            _use(ctx, "base"),
            _use(ctx, f"playbook.{playbook}"),
            _use(
                ctx,
                "context",
                shop_name=ctx.merchant.name,
                profile=(profile or "").strip(),
                now=_local_now(ctx.now, ctx.merchant.timezone),
                menu=[
                    {
                        "name": item.label,
                        "id": items.ref(item.variant_id),
                        "available": item.available,
                    }
                    for item in ctx.stock
                    if item.variant_id
                ],
                stage=ctx.stage,
                coming_up=_coming_up(ctx),
                draft_date=_day_text(_draft_date(draft)),
                draft_lines=_draft_lines(draft, ctx),
                fulfilment=draft.get("fulfilment"),
                needed_by=draft.get("needed_by"),
                quote_id=str(quote.id) if quote and quote.status == "open" else None,
                quote_shown=bool(quote and quote.shown_message_id),
                open_questions=open_questions,
                window_closing=window_closing,
                facts=[{"key": key, "value": value} for key, value in facts],
                rules=[{"question": q, "answer": a} for q, a in rules],
                glossary=[{"term": t, "meaning": m} for t, m in glossary],
                summary=summary,
            ),
        ]
    )
    messages = [llm.Message("system", system)]
    customer_texts = _customer_texts(ctx, history)
    for line in history:
        if line.sender == "customer" and line.id not in customer_texts:
            continue  # cut from a long burst: the newest messages matter most
        messages.extend(_as_messages(ctx, line, customer_texts))
    return Context(messages, playbook)


def _customer_texts(ctx: TurnContext, history: list[ChatLine]) -> dict[uuid.UUID, str]:
    """Customer text as the model sees it: normalised, each message capped, and the latest
    burst (everything since our last reply) capped as a whole, oldest cut first."""
    settings = get_settings()
    marker = _use(ctx, "inbound.shortened")
    texts = {
        line.id: inbound.shorten(
            inbound.normalise(line.body), settings.inbound_max_message_chars, marker
        )
        for line in history
        if line.sender == "customer"
    }
    budget = settings.inbound_max_turn_chars
    for line in reversed(history):
        if line.sender in ("agent", "merchant"):
            break
        if line.sender != "customer":
            continue
        if budget <= 0:
            texts.pop(line.id)
            continue
        if len(texts[line.id]) > budget:
            texts[line.id] = inbound.shorten(texts[line.id], budget, marker)
        budget -= len(texts[line.id])
    return texts


def _as_messages(
    ctx: TurnContext, line: ChatLine, customer_texts: dict[uuid.UUID, str]
) -> list[llm.Message]:
    if line.sender == "customer":
        text = customer_texts[line.id]
        kinds = line.details.get("attachments") or []
        if kinds or line.details.get("story"):
            text = _use(
                ctx,
                "history.attachments",
                story=bool(line.details.get("story")),
                attachments=[f"{kind} a{n}" for n, kind in enumerate(kinds)],
                text=text,
            )
        return [llm.Message("user", text or "(no text)")]
    if line.sender == "agent":
        return [llm.Message("assistant", line.body)]
    if line.sender == "merchant":
        return [llm.Message("assistant", _use(ctx, "history.shop_owner", text=line.body))]
    event = line.details.get("event") or {"event": "shop_note", "text": line.body}
    call = llm.ToolCall(f"event_{line.id.hex[:12]}", SHOP_EVENT, {})
    return [
        llm.Message("assistant", "", (call,)),
        llm.Message(
            "tool", json.dumps(event, ensure_ascii=False), tool_call_id=call.id, name=SHOP_EVENT
        ),
    ]


def _draft_lines(draft: dict[str, object], ctx: TurnContext) -> list[str]:
    lines: list[str] = []
    stock = ctx.stock_on(_draft_date(draft))
    for line in draft.get("items") or []:  # pyright: ignore[reportGeneralTypeIssues]
        item = items.resolve(str(line["item_id"]), stock)  # pyright: ignore[reportIndexIssue]
        if item is not None:
            lines.append(f"{line['quantity']} x {item.label} ({line['item_id']})")  # pyright: ignore[reportIndexIssue]
    return lines


def _coming_up(ctx: TurnContext) -> list[dict[str, object]]:
    """Items on sale on the coming days, with how many are left each day."""
    by_item: dict[str, dict[str, object]] = {}
    for day, stock in sorted(ctx.upcoming.items()):
        for item in stock:
            if item.variant_id is None:
                continue
            entry = by_item.setdefault(
                items.ref(item.variant_id),
                {"name": item.label, "id": items.ref(item.variant_id), "days": []},
            )
            entry["days"].append(  # pyright: ignore[reportAttributeAccessIssue]
                f"{_day_text(day)}: {item.available} left"
                if item.available
                else f"{_day_text(day)}: sold out"
            )
    return list(by_item.values())


def _draft_date(draft: dict[str, object]) -> date | None:
    try:
        return date.fromisoformat(str(draft["date"])) if draft.get("date") else None
    except ValueError:
        return None


def day_text(day: date) -> str:
    """How a date is written to customers and the model: "Sat 1 Nov"."""
    return f"{day:%a} {day.day} {day:%b}"


def _day_text(day: date | None) -> str | None:
    return day_text(day) if day else None


def _local_now(now: datetime, timezone: str) -> str:
    return now.astimezone(ZoneInfo(timezone)).strftime("%a %d %b %Y, %I:%M %p")


def _use(ctx: TurnContext, prompt_id: str, **values: object) -> str:
    ctx.prompt_refs.add(prompt_store.ref(prompt_id))
    return prompt_store.render(prompt_id, **values)
