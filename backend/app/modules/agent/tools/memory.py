"""Memory and housekeeping tools: remember_customer_fact, get_customer_profile,
log_missed_demand, load_playbook.
"""

import json
from typing import Any, Literal

from pydantic import BaseModel, Field

from app.core.db import session_scope
from app.modules.agent import items, memory, prompt_store
from app.modules.agent.tools.registry import ACTIVE_STAGES, Tool, ToolResult, TurnContext, register
from app.modules.conversations import service as conversations
from app.modules.insights import service as insights
from app.modules.orders import service as orders

PlaybookName = Literal[
    "new_order",
    "custom_or_future_order",
    "story_or_photo",
    "payment_problem",
    "order_status",
    "product_question",
    "complaint",
    "small_talk",
    "abuse_or_off_topic",
]


class RememberCustomerFactArgs(BaseModel):
    key: memory.FactKey
    value: str | list[Any] | dict[str, Any] = Field(description="What to remember")


class RememberCustomerFact(Tool):
    name = "remember_customer_fact"
    Args = RememberCustomerFactArgs
    writes = True

    async def run(self, ctx: TurnContext, args: RememberCustomerFactArgs) -> ToolResult:
        if len(json.dumps(args.value, ensure_ascii=False)) > 300:
            return ToolResult.fail("too_long", "Keep a fact under 300 characters")
        async with session_scope() as session:
            await memory.remember(
                session,
                merchant_id=ctx.merchant.id,
                customer_id=ctx.customer_id,
                key=args.key,
                value=args.value,
                source_message_id=ctx.trigger_message_id,
            )
        return ToolResult(True, {"remembered": args.key})


class GetCustomerProfileArgs(BaseModel):
    pass


class GetCustomerProfile(Tool):
    name = "get_customer_profile"
    Args = GetCustomerProfileArgs

    async def run(self, ctx: TurnContext, args: GetCustomerProfileArgs) -> ToolResult:
        async with session_scope() as session:
            known = await memory.facts(session, ctx.merchant.id, ctx.customer_id)
            recent = await orders.customer_orders(session, ctx.merchant.id, ctx.customer_id)
            last = await orders.last_order_lines(session, ctx.merchant.id, ctx.customer_id)
        profile: dict[str, Any] = {fact.key: fact.value for fact in known}
        profile["past_orders"] = len(recent)
        profile["unpaid_orders"] = sum(order.status == "awaiting_payment" for order in recent)
        if last is not None:
            lines, fulfilment, address = last
            in_stock = {item.variant_id: item for item in ctx.stock}
            profile["last_order"] = {
                "items": [
                    {
                        "item_id": items.ref(variant_id),
                        "name": in_stock[variant_id].label if variant_id in in_stock else None,
                        "quantity": quantity,
                        "available_today": in_stock[variant_id].available
                        if variant_id in in_stock
                        else 0,
                    }
                    for variant_id, quantity in lines
                ],
                "fulfilment": fulfilment,
                "delivery_address": address,
            }
        return ToolResult(True, profile)


class LogMissedDemandArgs(BaseModel):
    wanted_text: str = Field(min_length=1, max_length=150)
    reason: Literal["sold_out", "not_stocked", "shop_closed", "other"]


class LogMissedDemand(Tool):
    name = "log_missed_demand"
    Args = LogMissedDemandArgs
    stages = ACTIVE_STAGES
    writes = True

    async def run(self, ctx: TurnContext, args: LogMissedDemandArgs) -> ToolResult:
        async with session_scope() as session:
            await insights.log_missed_demand(
                session,
                merchant_id=ctx.merchant.id,
                conversation_id=ctx.conversation_id,
                wanted=args.wanted_text,
                reason=args.reason,
            )
        return ToolResult(True, {"logged": True})


class LoadPlaybookArgs(BaseModel):
    name: PlaybookName


class LoadPlaybook(Tool):
    name = "load_playbook"
    Args = LoadPlaybookArgs

    async def run(self, ctx: TurnContext, args: LoadPlaybookArgs) -> ToolResult:
        if ctx.playbook_loaded:
            return ToolResult.fail("already_loaded", "A playbook can be loaded only once per turn")
        ctx.playbook_loaded = True
        prompt_id = f"playbook.{args.name}"
        ctx.prompt_refs.add(prompt_store.ref(prompt_id))
        return ToolResult(True, {"playbook": prompt_store.render(prompt_id)})

    def replay(self, ctx: TurnContext, result: ToolResult) -> None:
        if result.ok:
            ctx.playbook_loaded = True


register(RememberCustomerFact())
register(GetCustomerProfile())
register(LogMissedDemand())
register(LoadPlaybook())

__all__ = ["conversations"]
