"""The v2 turn engine (agent-phase-2.md section 6.1).

A turn answers the latest customer message (or shop event). The model acts only through the
tools its stage allows, and the turn ends when send_reply succeeds. Budgets cap model calls,
tool calls and time; when the turn can't finish, code sends the holding message and asks the
shop owner, so the customer is never left without a reply.

Every model response and tool result is stored as a step. A retried turn (a crashed worker,
a failed job) replays the stored steps instead of running them again, so an order, a payment
link or a message is never created twice.
"""

import asyncio
import json
import time
import uuid
from dataclasses import dataclass
from datetime import UTC, date, datetime
from typing import Any

import structlog

from app.core import locks
from app.core.config import get_settings
from app.core.db import session_scope
from app.modules.agent import context, llm, memory, prompt_store, tracing
from app.modules.agent.guardrails import inbound
from app.modules.agent.tools import orders as order_tools
from app.modules.agent.tools import registry
from app.modules.agent.tools.registry import ToolResult, TurnContext
from app.modules.conversations import service as conversations
from app.modules.conversations.schemas import ChatLine, ConversationState
from app.modules.escalations import service as escalations
from app.modules.inventory import service as inventory
from app.modules.inventory.schemas import StockItem
from app.modules.merchants import service as merchants
from app.modules.merchants.schemas import MerchantInfo
from app.modules.orders import service as orders
from app.modules.orders.schemas import SavedQuote
from app.modules.shop_profile import service as shop_profile

log = structlog.get_logger()

FALLBACK_QUESTION = (
    "The assistant couldn't finish its reply to this customer. Please check the chat."
)
_REPLY_TRIGGERS = ("customer", "system")


# A turn takes at most agent_turn_deadline_seconds; waiting a little longer than that for a
# running copy to finish covers it.
TURN_LOCK_WAIT_SECONDS = 90.0


async def run_turn(conversation_id: uuid.UUID, *, shadow: bool = False) -> None:
    """Answer the chat's latest message. `shadow`: run without writing or sending anything.

    One copy of a chat's turn runs at a time. A second start (a redelivered job, the sweeper,
    the simulator running a turn the worker also picked up) waits for the first and then finds
    the message already answered; two copies at once sent the customer a real reply and then a
    contradictory holding message (live eval, 7 Nov).
    """
    async with locks.advisory_lock(
        "agent_turn_shadow" if shadow else "agent_turn",
        str(conversation_id),
        wait_seconds=TURN_LOCK_WAIT_SECONDS,
    ) as held:
        if not held:
            log.warning("agent.turn_busy", conversation_id=str(conversation_id))
            return  # the sweeper tries again if the message is still unanswered
        await _run_turn(conversation_id, shadow=shadow)


async def _run_turn(conversation_id: uuid.UUID, *, shadow: bool) -> None:
    started = time.monotonic()
    loaded = await _load(conversation_id, shadow=shadow)
    if loaded is None:
        return
    ctx, built, trace = loaded
    status, error = "fallback", None
    gate = await inbound.check(
        turn_id=trace.turn_id,
        merchant=ctx.merchant,
        conversation_id=conversation_id,
        customer_handle=ctx.customer_handle,
        trigger_text=ctx.trigger_text,
        now=ctx.now,
    )
    if gate.stop:
        status, error = "gated", gate.reason
        if ctx.mode != "shadow":
            await _gated(ctx, gate)
    else:
        try:
            status = await _loop(ctx, built, trace, started)
        except llm.LLMError as exc:
            log.error(
                "agent.model_unavailable", conversation_id=str(conversation_id), error=str(exc)
            )
            error = str(exc)[:500]
    if status == "fallback" and ctx.mode != "shadow":
        await _fall_back(ctx)
    await tracing.finish(
        trace,
        status,
        stage_after=ctx.stage,
        playbook=built.playbook,
        prompt_refs=ctx.prompt_refs,
        latency_ms=round((time.monotonic() - started) * 1000),
        error=error,
        would_send=ctx.would_send,
    )
    if ctx.mode != "shadow":
        await conversations.deliver_outbox(conversation_id)
    log.info("agent.turn_finished", conversation_id=str(conversation_id), status=status)


async def _loop(
    ctx: TurnContext, built: context.Context, trace: tracing.Trace, started: float
) -> str:
    settings = get_settings()
    messages = list(built.messages)
    await _apply_tap(ctx, trace, messages)
    corrected = False
    tool_calls = 0
    for step in range(settings.agent_max_model_calls):
        if time.monotonic() - started > settings.agent_turn_deadline_seconds:
            log.warning("agent.turn_deadline", turn_id=str(trace.turn_id))
            return "fallback"
        completion = await _model_step(
            ctx, trace, step, messages, deadline=started + settings.agent_turn_deadline_seconds
        )
        if not completion.tool_calls:
            if corrected:
                return "fallback"
            corrected = True
            messages.append(llm.Message("user", _prompt(ctx, "engine.end_with_send_reply")))
            continue
        messages.append(llm.Message("assistant", completion.content, completion.tool_calls))
        for index, call in enumerate(completion.tool_calls):
            tool_calls += 1
            if tool_calls > settings.agent_max_tool_calls:
                return "fallback"
            result = await _tool_step(ctx, trace, step, index, call)
            messages.append(
                llm.Message(
                    "tool",
                    _json(result.for_model()),
                    tool_call_id=call.id,
                    name=call.name,
                )
            )
            if ctx.handed_off:
                return "handed_off"
            if ctx.replied:
                return "replied"
            if ctx.reply_rejections > settings.agent_repair_attempts:
                return "fallback"
    return "fallback"


async def _model_step(
    ctx: TurnContext,
    trace: tracing.Trace,
    step: int,
    messages: list[llm.Message],
    *,
    deadline: float,
) -> llm.Completion:
    key = f"{trace.turn_id}:{step}:model"
    stored = trace.steps.get(key)
    if stored is not None:
        return _completion(stored)
    # The gateway retries a slow model (timeout x retries can be minutes); the turn's own time
    # limit still holds, so a stalled model costs the customer seconds, not minutes.
    try:
        async with asyncio.timeout(max(deadline - time.monotonic(), 1.0)):
            completion = await llm.generate(messages, tools=registry.offered(ctx))
    except TimeoutError as exc:
        raise llm.LLMError("The model didn't answer within the turn's time limit") from exc
    await tracing.record(
        trace,
        step=step,
        kind="model",
        name=completion.model,
        key=key,
        request={"messages": len(messages), "stage": ctx.stage},
        result={
            "content": completion.content,
            "model": completion.model,
            "cost_usd": completion.cost_usd,
            "tool_calls": [
                {
                    "id": c.id,
                    "name": c.name,
                    "arguments": c.arguments,
                    "arguments_error": c.arguments_error,
                }
                for c in completion.tool_calls
            ],
        },
        input_tokens=completion.input_tokens,
        output_tokens=completion.output_tokens,
        latency_ms=completion.latency_ms,
    )
    return completion


async def _tool_step(
    ctx: TurnContext, trace: tracing.Trace, step: int, index: int, call: llm.ToolCall
) -> ToolResult:
    key = f"{trace.turn_id}:{step}:{index}:{call.name}"
    stored = trace.steps.get(key)
    if stored is not None:
        result = ToolResult.from_stored(stored)
        registry.replay(ctx, call.name, result)
        return result
    began = time.monotonic()
    result = await registry.execute(ctx, call)
    await tracing.record(
        trace,
        step=step,
        kind="tool",
        name=call.name,
        key=key,
        request={"arguments": call.arguments},
        result=result.stored(),
        latency_ms=round((time.monotonic() - began) * 1000),
    )
    return result


async def _apply_tap(ctx: TurnContext, trace: tracing.Trace, messages: list[llm.Message]) -> None:
    """Layer 0: a Confirm or Change tap is acted on by code, without the model."""
    payload = str(ctx.tap or "")
    action, _, quote_id = payload.partition(":")
    if action not in ("CONFIRM", "CHANGE") or not quote_id:
        return
    name = "confirm_order" if action == "CONFIRM" else "change_quote"
    key = f"{trace.turn_id}:tap:{name}"
    stored = trace.steps.get(key)
    if stored is not None:
        result = ToolResult.from_stored(stored)
        registry.replay(ctx, "confirm_order", result)
    elif action == "CONFIRM" and ctx.stage == "awaiting_confirmation":
        result = await order_tools.confirm(ctx, quote_id, tapped=True)
        await tracing.record(
            trace,
            step=-1,
            kind="tool",
            name=name,
            key=key,
            request={"quote_id": quote_id, "tapped": True},
            result=result.stored(),
        )
    elif action == "CHANGE":
        result = await order_tools.change_from_tap(ctx, quote_id)
        await tracing.record(
            trace,
            step=-1,
            kind="tool",
            name=name,
            key=key,
            request={"quote_id": quote_id, "tapped": True},
            result=result.stored(),
        )
    else:
        return
    call = llm.ToolCall(f"tap_{trace.turn_id.hex[:12]}", name, {"quote_id": quote_id})
    messages.append(llm.Message("assistant", "", (call,)))
    messages.append(llm.Message("tool", _json(result.for_model()), tool_call_id=call.id, name=name))


async def _gated(ctx: TurnContext, gate: inbound.Gate) -> None:
    """No model call: a fixed template (if any) and, where needed, a question for the owner."""
    async with session_scope() as session:
        if gate.template:
            await conversations.queue_message(
                session,
                conversation_id=ctx.conversation_id,
                text=prompt_store.text(gate.template, ctx.language),
                key=f"turn:{ctx.turn_id}:gated",
                details={"kind": gate.reason, "language": ctx.language},
            )
            ctx.prompt_refs.add(prompt_store.ref(gate.template))
        if gate.question:
            await escalations.open_escalation(
                session,
                merchant_id=ctx.merchant.id,
                conversation_id=ctx.conversation_id,
                question=gate.question,
                trigger_message_id=ctx.trigger_message_id,
            )


async def _fall_back(ctx: TurnContext) -> None:
    """Never leave the customer silent: the holding message, and a question for the owner.

    If the turn was answering the owner's reply, the customer already waited for it: send the
    owner's own words instead, so the answer always reaches them even when the model failed.
    """
    if ctx.trigger_answer:
        async with session_scope() as session:
            await conversations.queue_message(
                session,
                conversation_id=ctx.conversation_id,
                text=prompt_store.text(
                    "owner_answer_relay", ctx.language, answer=ctx.trigger_answer
                ),
                key=f"turn:{ctx.turn_id}:owner_answer_relay",
                details={
                    "kind": "owner_answer_relay",
                    "language": ctx.language,
                    "trigger_id": str(ctx.trigger_message_id),
                },
            )
        ctx.prompt_refs.add(prompt_store.ref("owner_answer_relay"))
        return
    async with session_scope() as session:
        await conversations.queue_message(
            session,
            conversation_id=ctx.conversation_id,
            text=prompt_store.text("holding", ctx.language),
            key=f"turn:{ctx.turn_id}:holding",
            details={
                "kind": "holding",
                "language": ctx.language,
                "trigger_id": str(ctx.trigger_message_id),
            },
        )
        # Not when the owner already has this customer's question, and not again and again while
        # the model is down: one open "couldn't finish" per chat is enough.
        if not ctx.asked_owner_this_turn and not await escalations.has_open(
            session, ctx.conversation_id, FALLBACK_QUESTION
        ):
            await escalations.open_escalation(
                session,
                merchant_id=ctx.merchant.id,
                conversation_id=ctx.conversation_id,
                question=FALLBACK_QUESTION,
                trigger_message_id=ctx.trigger_message_id,
            )
    ctx.prompt_refs.add(prompt_store.ref("holding"))


async def _load(
    conversation_id: uuid.UUID, *, shadow: bool
) -> tuple[TurnContext, context.Context, tracing.Trace] | None:
    gathered = await _gather(conversation_id)
    if gathered is None:
        return None
    mode = "draft" if gathered.merchant.agent_engine == "draft" else "live"
    if shadow:
        mode = "shadow"
    trace = await tracing.start(
        merchant_id=gathered.merchant.id,
        conversation_id=conversation_id,
        trigger_message_id=gathered.trigger.id,
        stage=gathered.state.stage,
        mode=mode,
    )
    if trace is None:
        return None  # this message was already answered
    ctx, built = _build(gathered, trace.turn_id)
    ctx.mode = mode
    return ctx, built, trace


async def replay_turn(turn_id: uuid.UUID) -> dict[str, Any]:
    """Rebuild a past turn's first model request with today's prompts and model, and compare.

    Nothing is written: no tool runs. Every bad production reply can become an eval case.
    """
    stored = await tracing.first_step(turn_id)
    if stored is None:
        raise LookupError(f"No turn {turn_id}")
    conversation_id, trigger_id, first_model_step = stored
    gathered = await _gather(conversation_id, trigger_id=trigger_id, for_replay=True)
    if gathered is None:
        raise LookupError(f"Turn {turn_id} can't be rebuilt (the chat or its message is gone)")
    ctx, built = _build(gathered, turn_id)
    completion = await llm.generate(built.messages, tools=registry.offered(ctx))
    return {
        "turn_id": str(turn_id),
        "playbook": built.playbook,
        "prompts": sorted(ctx.prompt_refs),
        "then": (first_model_step or {}).get("tool_calls"),
        "now": [{"name": c.name, "arguments": c.arguments} for c in completion.tool_calls],
        "model": completion.model,
    }


@dataclass(frozen=True)
class _Gathered:
    state: ConversationState
    merchant: MerchantInfo
    history: list[ChatLine]
    trigger: ChatLine
    business_date: date
    now: datetime
    stock: list[StockItem]
    upcoming: dict[date, list[StockItem]]
    profile: str | None
    quote: SavedQuote | None
    open_questions: list[str]
    window_closing: bool
    facts: list[tuple[str, Any]]
    rules: list[tuple[str, str]]
    glossary: list[tuple[str, str]]
    summary: str | None


async def _gather(
    conversation_id: uuid.UUID,
    *,
    trigger_id: uuid.UUID | None = None,
    for_replay: bool = False,
) -> _Gathered | None:
    """Everything a turn reads, in one transaction."""
    settings = get_settings()
    now = datetime.now(UTC)
    async with session_scope() as session:
        state = await conversations.load_state(session, conversation_id)
        if state is None:
            return None
        if not for_replay and (not state.agent_active or state.stage == "handed_off"):
            return None
        merchant = await merchants.find_merchant(session, state.merchant_id)
        if merchant is None or (not for_replay and not merchant.agent_enabled):
            return None
        history = await conversations.chat_history(
            session, conversation_id, limit=500 if for_replay else settings.history_messages
        )
        if not for_replay:
            history = causal_order(history)
        if trigger_id is None:
            trigger = _trigger(history)
        else:
            trigger = next((line for line in history if line.id == trigger_id), None)
        if trigger is None:
            return None
        seen = history[: history.index(trigger) + 1]  # what the turn answers, as it was then
        if for_replay:
            seen = seen[-settings.history_messages :]
        business_date = merchants.business_date(merchant, now)
        windows = await conversations.windows_for(session, {conversation_id})
        window = windows.get(conversation_id)
        return _Gathered(
            state=state,
            merchant=merchant,
            history=seen,
            trigger=trigger,
            business_date=business_date,
            now=now,
            stock=await inventory.today_stock(
                session, merchant.id, business_date, ordering_today=business_date
            ),
            upcoming=await inventory.upcoming_stock(
                session,
                merchant.id,
                business_date,
                settings.agent_order_days_ahead,
                ordering_today=business_date,
            ),
            profile=await shop_profile.latest_profile(session, merchant.id),
            quote=await orders.current_quote(session, conversation_id),
            open_questions=[
                q.question
                for q in await escalations.list_escalations(session, merchant.id, status="open")
                if q.conversation_id == conversation_id
            ],
            window_closing=bool(window and window.state == "closing"),
            facts=[
                (fact.key, fact.value)
                for fact in await memory.facts(session, merchant.id, state.customer_id)
            ],
            rules=await memory.rules(session, merchant.id),
            glossary=await memory.glossary(session, merchant.id),
            summary=await memory.latest_summary(session, conversation_id),
        )


def _build(gathered: _Gathered, turn_id: uuid.UUID) -> tuple[TurnContext, context.Context]:
    seen, trigger, state = gathered.history, gathered.trigger, gathered.state
    customer = next((line for line in reversed(seen) if line.sender == "customer"), None)
    by_customer = trigger.sender == "customer"
    ctx = TurnContext(
        turn_id=turn_id,
        merchant=gathered.merchant,
        conversation_id=state.id,
        customer_id=state.customer_id,
        trigger_message_id=trigger.id,
        trigger_created_at=trigger.created_at,
        customer_text=customer.body if customer else "",
        business_date=gathered.business_date,
        now=gathered.now,
        stock=gathered.stock,
        stage=state.stage,
        language=_language(seen),
        tap=trigger.details.get("quick_reply") if by_customer else None,
        trigger_text=trigger.body if by_customer else "",
        trigger_details=dict(trigger.details) if by_customer else {},
        customer_handle=state.customer_handle,
        owner_asked=bool(gathered.open_questions),
        upcoming=gathered.upcoming,
        trigger_event=None if by_customer else context.event_name(trigger),
        trigger_answer=None if by_customer else context.owner_answer(trigger),
        last_agent_reply=next(
            (line.body for line in reversed(seen) if line.sender == "agent"), None
        ),
    )
    built = context.build(
        ctx,
        history=seen,
        profile=gathered.profile,
        draft=state.draft,
        quote=gathered.quote,
        open_questions=gathered.open_questions,
        window_closing=gathered.window_closing,
        trigger=trigger,
        facts=gathered.facts,
        rules=gathered.rules,
        glossary=gathered.glossary,
        summary=gathered.summary,
    )
    ctx.playbook = built.playbook
    return ctx, built


def causal_order(history: list[ChatLine]) -> list[ChatLine]:
    """The chat in the order the replies were written, not the order they were stored.

    A reply is written for the message that triggered it. If the customer wrote more while that
    turn was running, the reply is stored after their newer message, but it never saw it. Read
    in storage order, the next turn would not know it was already said (live run, 7 Nov: an
    owner's answer was passed on, then the customer's "okay" got the same answer again). Each
    reply moves up to just after its own trigger, so the newer message reads as the answer to it.
    """
    position = {line.id: index for index, line in enumerate(history)}
    moved: dict[uuid.UUID, list[ChatLine]] = {}
    for index, line in enumerate(history):
        if line.sender != "agent":
            continue
        raw = line.details.get("trigger_id")
        try:
            trigger = uuid.UUID(str(raw)) if raw else None
        except ValueError:
            trigger = None
        if trigger is None or position.get(trigger, index) >= index:
            continue
        between = history[position[trigger] + 1 : index]
        if any(other.sender in ("customer", "system") for other in between):
            moved.setdefault(trigger, []).append(line)
    if not moved:
        return history
    skipped = {line.id for lines in moved.values() for line in lines}
    ordered: list[ChatLine] = []
    for line in history:
        if line.id in skipped:
            continue
        ordered.append(line)
        ordered.extend(moved.get(line.id, []))
    return ordered


def _trigger(history: list[ChatLine]) -> ChatLine | None:
    """The latest customer message or shop event, unless the merchant has replied since."""
    for line in reversed(history):
        if line.sender == "merchant":
            return None
        if line.sender in _REPLY_TRIGGERS:
            return line
    return None


def _language(history: list[ChatLine]) -> str:
    """The customer's language: what our last reply used, else a guess from their script."""
    for line in reversed(history):
        if line.sender == "agent" and line.details.get("language"):
            return str(line.details["language"])
    text = next((line.body for line in reversed(history) if line.sender == "customer"), "")
    if any("஀" <= ch <= "௿" for ch in text):
        return "ta"
    if any("ऀ" <= ch <= "ॿ" for ch in text):
        return "hi"
    return "en"


def _completion(stored: dict[str, Any]) -> llm.Completion:
    return llm.Completion(
        content=str(stored.get("content") or ""),
        model=str(stored.get("model") or ""),
        input_tokens=None,
        output_tokens=None,
        latency_ms=0,
        tool_calls=tuple(
            llm.ToolCall(c["id"], c["name"], c.get("arguments") or {}, c.get("arguments_error"))
            for c in stored.get("tool_calls") or []
        ),
    )


def _prompt(ctx: TurnContext, prompt_id: str) -> str:
    ctx.prompt_refs.add(prompt_store.ref(prompt_id))
    return prompt_store.render(prompt_id)


def _json(data: dict[str, Any]) -> str:
    return json.dumps(data, ensure_ascii=False, default=str)
