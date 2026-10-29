"""Tools that bring in the shop owner: ask_shop_owner, hand_off_to_owner."""

from typing import Literal

from pydantic import BaseModel, Field

from app.core.db import session_scope
from app.modules.agent import prompt_store
from app.modules.agent.tools.registry import Tool, ToolResult, TurnContext, register
from app.modules.conversations import service as conversations
from app.modules.escalations import service as escalations


class AskShopOwnerArgs(BaseModel):
    question: str = Field(min_length=3, max_length=500)
    category: str = Field(default="other", max_length=40)
    suggested_answers: list[str] = Field(default_factory=list, max_length=3)


class AskShopOwner(Tool):
    name = "ask_shop_owner"
    Args = AskShopOwnerArgs
    writes = True

    async def run(self, ctx: TurnContext, args: AskShopOwnerArgs) -> ToolResult:
        question = args.question.strip()
        if args.suggested_answers:
            question += "\nSuggested answers: " + " / ".join(args.suggested_answers)
        async with session_scope() as session:
            asked = await escalations.open_escalation(
                session,
                merchant_id=ctx.merchant.id,
                conversation_id=ctx.conversation_id,
                question=question,
                trigger_message_id=ctx.trigger_message_id,
            )
        ctx.owner_asked = True
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
