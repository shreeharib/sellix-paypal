"""Public interface of the agent module."""

import uuid
from datetime import UTC, datetime

import structlog

from app.core.db import session_scope
from app.modules.agent import customer_agent, llm
from app.modules.agent.models import AiUsage
from app.modules.agent.schemas import ChatMessage, CustomerReply, TurnBrief
from app.modules.inventory import service as inventory
from app.modules.merchants import hours
from app.modules.merchants import service as merchants
from app.modules.shop_profile import service as shop_profile

log = structlog.get_logger()

MAX_ATTEMPTS = 2  # one repair attempt when the model's output isn't valid
# Where the agent puts a payment link it can't see; the turn replaces it with the real link.
PAYMENT_LINK_PLACEHOLDER = customer_agent.PAYMENT_LINK_PLACEHOLDER


class AgentUnavailable(RuntimeError):
    """The model failed, or returned unusable output on every attempt."""


def new_turn_brief(*, order: str) -> TurnBrief:
    return TurnBrief(system_tag=customer_agent.new_system_tag(), order=order)


def system_note(text: str, brief: TurnBrief) -> str:
    """A note from the shop's system in the conversation (not from the customer)."""
    return customer_agent.system_note(text, brief.system_tag)


def customer_text(text: str) -> str:
    """A customer's message as the agent sees it: never mistakable for a system note."""
    return customer_agent.neutralise_customer_text(text)


async def reply_to_customer(
    *,
    merchant_id: uuid.UUID,
    conversation_id: uuid.UUID,
    history: list[ChatMessage],
    brief: TurnBrief,
) -> CustomerReply:
    """Next reply in a customer conversation, from the shop profile and today's stock."""
    now = datetime.now(UTC)
    async with session_scope() as session:
        merchant = await merchants.get_merchant(session, merchant_id)
        profile = await shop_profile.latest_profile(session, merchant_id)
        today = merchants.business_date(merchant, now)
        stock = await inventory.today_stock(session, merchant_id, today)
    opening = merchants.opening_hours(merchant)
    clock = customer_agent.ShopClock(
        now=hours.describe_now(opening, merchant.timezone, now),
        week=hours.describe_week(opening, today),
    )

    messages = [
        ChatMessage("system", customer_agent.build_system_prompt(profile, stock, brief, clock)),
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
