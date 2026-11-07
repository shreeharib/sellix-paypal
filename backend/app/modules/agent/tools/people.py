"""Tools that bring in the shop owner: ask_shop_owner, hand_off_to_owner."""

import re
from typing import Literal

from pydantic import BaseModel, Field

from app.core.config import get_settings
from app.core.db import session_scope
from app.modules.agent import prompt_store
from app.modules.agent.tools.registry import Tool, ToolResult, TurnContext, register
from app.modules.conversations import service as conversations
from app.modules.escalations import service as escalations


class AskShopOwnerArgs(BaseModel):
    question: str = Field(min_length=3, max_length=500)
    category: str = Field(default="other", max_length=40)
    suggested_answers: list[str] = Field(default_factory=list, max_length=3)
    # How sure the model is that it could answer without the owner (0-100). Left out: unsure.
    confidence: int | None = Field(default=None, ge=0, le=100)


class AskShopOwner(Tool):
    name = "ask_shop_owner"
    Args = AskShopOwnerArgs
    writes = True

    async def run(self, ctx: TurnContext, args: AskShopOwnerArgs) -> ToolResult:
        refusal = _answerable_without_owner(ctx, args)
        if refusal is not None and ctx.ask_refusals < MAX_ASK_REFUSALS:
            ctx.ask_refusals += 1
            return ToolResult.fail(
                "answer_yourself", refusal, "Answer the customer with send_reply"
            )
        async with session_scope() as session:
            asked = await escalations.open_escalation(
                session,
                merchant_id=ctx.merchant.id,
                conversation_id=ctx.conversation_id,
                question=args.question.strip(),
                trigger_message_id=ctx.trigger_message_id,
                suggested_answers=args.suggested_answers,
            )
        ctx.owner_asked = True
        ctx.asked_owner_this_turn = True
        return ToolResult(
            True,
            {
                "question_id": str(asked.id),
                "next": "Tell the customer you'll check with the shop and get back to them. "
                "Don't answer the question yourself.",
            },
        )

    def replay(self, ctx: TurnContext, result: ToolResult) -> None:
        if result.ok:
            ctx.owner_asked = True
            ctx.asked_owner_this_turn = True


MAX_ASK_REFUSALS = 2  # per turn: after that the question goes through, so nothing loops

# A question about a listed pre-order item is only a question for the owner when it asks for
# something beyond the listing.
_ABOUT_AVAILABILITY = re.compile(
    r"availab|pre-?order|open for|offer|take (?:the |an? )?order|book|do we have|in stock|listed",
    re.IGNORECASE,
)
_BEYOND_THE_LISTING = re.compile(
    r"\bcustom(?:i[sz]e[ds]?|[- ]made|[- ]order)?\b|personali[sz]|photo|name on|message on|design"
    r"|engrav|bulk|more than|larger|bigger"
    r"|another (?:day|date)|different (?:day|date)|size|flavou?r|colou?r|egg|allerg|discount"
    r"|deliver|tier|ingredient|price",
    re.IGNORECASE,
)


def _answerable_without_owner(ctx: TurnContext, args: AskShopOwnerArgs) -> str | None:
    """Why the model should answer itself, or None if the owner is the right one to ask.

    Two checks, so the owner is asked only when the shop's own data can't answer:
    - the facts: a listed pre-order item with stock left is on sale; asking whether it is
      available (and nothing more) is not a question for the owner;
    - the model's own confidence, when it says it is sure.
    """
    text = args.question.lower()
    if _ABOUT_AVAILABILITY.search(text) and not _BEYOND_THE_LISTING.search(text):
        for day, stock in sorted(ctx.upcoming.items()):
            for item in stock:
                if item.available > 0 and item.product.lower() in text:
                    last = (
                        f", last day to order {item.order_by_date:%d %b}"
                        if item.order_by_date
                        else ""
                    )
                    return (
                        f"{item.label} is listed for {day:%a %d %b} with {item.available} left"
                        f"{last}: it is open for pre-order. Tell the customer so and take the order"
                    )
    threshold = get_settings().agent_self_answer_confidence
    if args.confidence is not None and args.confidence >= threshold:
        return (
            f"You said you're {args.confidence}% sure you can answer this yourself. Use the menu, "
            "the Coming up list, the shop profile and your tool results to answer"
        )
    return None


class HandOffToOwnerArgs(BaseModel):
    reason: Literal["asked_for_person", "complaint", "abuse", "stuck", "data_request"]


class HandOffToOwner(Tool):
    name = "hand_off_to_owner"
    Args = HandOffToOwnerArgs
    writes = True

    async def run(self, ctx: TurnContext, args: HandOffToOwnerArgs) -> ToolResult:
        async with session_scope() as session:
            await conversations.hand_off(session, ctx.conversation_id, args.reason)
            await escalations.open_escalation(
                session,
                merchant_id=ctx.merchant.id,
                conversation_id=ctx.conversation_id,
                question=f"This chat is now yours ({args.reason.replace('_', ' ')}). The "
                "assistant has stopped replying to this customer.",
                trigger_message_id=ctx.trigger_message_id,
            )
            await conversations.queue_message(
                session,
                conversation_id=ctx.conversation_id,
                text=prompt_store.text("handed_off", ctx.language),
                key=f"turn:{ctx.turn_id}:handed_off",
                details={"kind": "handed_off", "language": ctx.language},
            )
        ctx.stage = "handed_off"
        ctx.handed_off = True
        return ToolResult(True, {"handed_off": True})

    def replay(self, ctx: TurnContext, result: ToolResult) -> None:
        if result.ok:
            ctx.stage = "handed_off"
            ctx.handed_off = True


register(AskShopOwner())
register(HandOffToOwner())
