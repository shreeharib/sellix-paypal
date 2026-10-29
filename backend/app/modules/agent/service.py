"""Public interface of the agent module."""

import uuid
from datetime import UTC, datetime, timedelta
from typing import Any

import structlog

from app.core.db import session_scope
from app.modules.agent import customer_agent, llm, prompt_store
from app.modules.agent.models import AiUsage
from app.modules.agent.schemas import ChatMessage, CustomerReply
from app.modules.inventory import service as inventory
from app.modules.merchants import service as merchants
from app.modules.shop_profile import service as shop_profile

log = structlog.get_logger()

MAX_ATTEMPTS = 2  # one repair attempt when the model's output isn't valid
# Where the agent puts a payment link it can't see; the turn replaces it with the real link.
PAYMENT_LINK_PLACEHOLDER = customer_agent.PAYMENT_LINK_PLACEHOLDER


class AgentUnavailable(RuntimeError):
    """The model failed, or returned unusable output on every attempt."""


def system_note(text: str) -> str:
    """A note from the shop's system in the conversation (not from the customer)."""
    return customer_agent.system_note(text)


async def run_turn(conversation_id: uuid.UUID, *, shadow: bool = False) -> None:
    """Answer the conversation's latest message with the v2 engine (tools, guardrails, outbox).

    `shadow`: run without writing or sending anything (v1 is answering; section 19).
    """
    from app.modules.agent import engine  # the engine needs conversations; keep imports one-way

    await engine.run_turn(conversation_id, shadow=shadow)


async def shadow_report(merchant_id: uuid.UUID, *, days: int = 1) -> list[dict[str, Any]]:
    """What v1 said and what v2 would have said, side by side (shadow mode)."""
    from app.modules.agent import tracing
    from app.modules.conversations import service as conversations

    since = datetime.now(UTC) - timedelta(days=days)
    rows: list[dict[str, Any]] = []
    for turn in await tracing.shadow_turns(merchant_id, since):
        async with session_scope() as session:
            customer = await conversations.message_body(session, turn.trigger_message_id)
            v1 = await conversations.reply_after(
                session, turn.conversation_id, turn.trigger_message_id
            )
        rows.append(
            {
                "turn_id": str(turn.id),
                "customer": customer,
                "v1": v1,
                "v2": turn.would_send,
                "v2_status": turn.status,
            }
        )
    return rows


async def stalled_turn_conversations(older_than: timedelta) -> list[uuid.UUID]:
    """Chats whose v2 turn was left running (a crashed worker): run_turn resumes them."""
    from app.modules.agent import tracing

    return await tracing.stalled_conversations(older_than)


async def customer_memory(merchant_id: uuid.UUID, customer_id: uuid.UUID) -> list[Any]:
    """What the agent remembers about a customer (the merchant can view it in Chats)."""
    from app.modules.agent import memory

    async with session_scope() as session:
        return list(await memory.facts(session, merchant_id, customer_id))


async def forget_customer_fact(merchant_id: uuid.UUID, customer_id: uuid.UUID, key: str) -> bool:
    from app.modules.agent import memory

    async with session_scope() as session:
        return await memory.forget(session, merchant_id, customer_id, key)


async def save_rule(
    *, merchant_id: uuid.UUID, question: str, answer: str, source_escalation_id: uuid.UUID
) -> None:
    """ "Always answer this way": the agent gives this answer from now on."""
    from app.modules.agent import memory

    async with session_scope() as session:
        await memory.save_rule(
            session,
            merchant_id=merchant_id,
            question=question,
            answer=answer,
            source_escalation_id=source_escalation_id,
        )


async def summarise_long_conversations() -> int:
    from app.modules.agent import memory

    return await memory.summarise_long_conversations()


def item_ref(variant_id: uuid.UUID) -> str:
    """The short id the assistant uses for an item (see items.py)."""
    from app.modules.agent import items

    return items.ref(variant_id)


async def variants_for_refs(merchant_id: uuid.UUID, refs: list[str]) -> list[uuid.UUID] | None:
    """Map item ids back to today's variants; None if any is unknown."""
    from app.modules.agent import items
    from app.modules.inventory import service as inventory
    from app.modules.merchants import service as merchants

    async with session_scope() as session:
        merchant = await merchants.get_merchant(session, merchant_id)
        stock = await inventory.today_stock(session, merchant_id, merchants.business_date(merchant))
    found = [items.resolve(ref, stock) for ref in refs]
    if any(item is None or item.variant_id is None for item in found):
        return None
    return [item.variant_id for item in found if item and item.variant_id]


async def last_turn(conversation_id: uuid.UUID) -> dict[str, Any] | None:
    """The latest v2 turn of a chat: status, stages, playbook, tools used, cost."""
    from app.modules.agent import tracing

    return await tracing.last_turn(conversation_id)


async def replay_turn(turn_id: uuid.UUID) -> dict[str, Any]:
    """Re-run a past turn's first model call with today's prompts and model (nothing is written)."""
    from app.modules.agent import engine

    return await engine.replay_turn(turn_id)


def prompt(prompt_id: str, **values: Any) -> str:
    """A prompt file from agent/prompts/, filled with code-produced values."""
    return prompt_store.render(prompt_id, **values)


def fixed_text(template_id: str, language: str, **values: Any) -> str:
    """A fixed customer-facing message from agent/prompts/templates/, in the given language."""
    return prompt_store.text(template_id, language, **values)


def load_prompts() -> None:
    """Load and check every prompt file; called at startup so a broken file fails fast."""
    prompt_store.load()


async def reply_to_customer(
    *, merchant_id: uuid.UUID, conversation_id: uuid.UUID, history: list[ChatMessage]
) -> CustomerReply:
    """Next reply in a customer conversation, from the shop profile and today's stock."""
    async with session_scope() as session:
        merchant = await merchants.get_merchant(session, merchant_id)
        profile = await shop_profile.latest_profile(session, merchant_id)
        stock = await inventory.today_stock(session, merchant_id, merchants.business_date(merchant))

    messages = [
        ChatMessage("system", customer_agent.build_system_prompt(profile, stock)),
        *history,
    ]
    for _ in range(MAX_ATTEMPTS):
        try:
            completion = await llm.complete(messages, json_output=True)
        except llm.LLMError as exc:
            log.error("agent.model_failed", conversation_id=str(conversation_id), error=str(exc))
            raise AgentUnavailable(str(exc)) from exc
        try:
            reply = customer_agent.parse_output(completion.content)
        except customer_agent.AgentOutputError as exc:
            await _record_usage(merchant_id, conversation_id, completion, succeeded=False)
            log.warning("agent.invalid_output", conversation_id=str(conversation_id))
            messages = [
                *messages,
                ChatMessage("assistant", completion.content),
                ChatMessage("user", customer_agent.repair_instruction(exc)),
            ]
            continue
        await _record_usage(merchant_id, conversation_id, completion, succeeded=True)
        return reply
    raise AgentUnavailable("The model returned unusable output on every attempt")


async def _record_usage(
    merchant_id: uuid.UUID,
    conversation_id: uuid.UUID,
    completion: llm.Completion,
    *,
    succeeded: bool,
) -> None:
    async with session_scope() as session:
        session.add(
            AiUsage(
                merchant_id=merchant_id,
                conversation_id=conversation_id,
                purpose="customer_reply",
                model=completion.model,
                input_tokens=completion.input_tokens,
                output_tokens=completion.output_tokens,
                latency_ms=completion.latency_ms,
                succeeded=succeeded,
            )
        )
