"""send_reply: the only way a turn ends (section 5.2). The reply passes the output guardrails,
code fills in its tokens, then it goes to the outbox.
"""

from pydantic import BaseModel, Field

from app.core.db import session_scope
from app.core.money import format_money
from app.modules.agent import items
from app.modules.agent.guardrails import output
from app.modules.agent.tools.registry import Tool, ToolResult, TurnContext, register
from app.modules.conversations import service as conversations
from app.modules.orders import service as orders


class SendReplyArgs(BaseModel):
    text: str = Field(min_length=1, max_length=2000)
    language: str = Field(min_length=2, max_length=16)
    choices: list[str] = Field(default_factory=list, max_length=13)
    reply_to_message_id: str | None = Field(default=None, max_length=64)


class SendReply(Tool):
    name = "send_reply"
    Args = SendReplyArgs
    writes = True

    async def run(self, ctx: TurnContext, args: SendReplyArgs) -> ToolResult:
        check = output.check_reply(
            args.text,
            values=await token_values(ctx),
            customer_text=ctx.customer_text,
            health_fields_seen=ctx.health_fields_seen,
            never_promise=ctx.merchant.never_promise,
            owner_asked=ctx.owner_asked,
        )
        if not check.ok:
            ctx.reply_rejections += 1
            return ToolResult.fail(
                "reply_rejected",
                "; ".join(check.problems),
                "Fix these and call send_reply again",
            )
        if ctx.mode == "shadow":
            ctx.would_send = check.text
        else:
            async with session_scope() as session:
                await conversations.queue_message(
                    session,
                    conversation_id=ctx.conversation_id,
                    text=check.text,
                    key=f"turn:{ctx.turn_id}:reply",
                    details={"language": args.language, "turn_id": str(ctx.turn_id)},
                    quick_replies=tuple((choice, f"CHOICE:{choice}") for choice in args.choices),
                    draft=ctx.mode == "draft",
                )
        ctx.replied = True
        ctx.language = args.language
        return ToolResult(True, {"sent": True}, private={"would_send": ctx.would_send})

    def replay(self, ctx: TurnContext, result: ToolResult) -> None:
        if result.ok:
            ctx.replied = True
            ctx.would_send = result.private.get("would_send")
        else:
            ctx.reply_rejections += 1


async def token_values(ctx: TurnContext) -> output.TokenValues:
    """What [[...]] tokens mean in this turn, read fresh from the database."""
    async with session_scope() as session:
        quote = await orders.current_quote(session, ctx.conversation_id)
        order = await orders.latest_order(session, ctx.conversation_id)
    return output.TokenValues(
        prices={
            items.ref(item.variant_id): format_money(item.price_minor, item.currency)
            for item in ctx.all_items()
            if item.variant_id
        },
        quote_total=format_money(quote.total_minor, quote.currency) if quote else None,
        order_total=format_money(order.total_minor, order.currency) if order else None,
        order_number=f"#{order.number}" if order else None,
        payment_link=ctx.payment_link,
    )


register(SendReply())
