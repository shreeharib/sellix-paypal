"""Order tools: update_order_draft, create_quote, confirm_order (sections 5.2 and 6.4).

Code prices every quote and sends the quote card itself. An order exists only when a quote
whose card was delivered is confirmed by a later tap or "yes", before the quote expired.
"""

import uuid
from datetime import date, datetime, time, timedelta
from typing import Any, Literal
from zoneinfo import ZoneInfo

import structlog
from pydantic import BaseModel, Field

from app.core.config import get_settings
from app.core.db import session_scope
from app.core.money import format_money
from app.modules.agent import affirmation, context, items, prompt_store
from app.modules.agent.tools.registry import Tool, ToolResult, TurnContext, register
from app.modules.conversations import service as conversations
from app.modules.escalations import service as escalations
from app.modules.orders import service as orders
from app.modules.orders.schemas import (
    OrderLineRequest,
    OrderRequest,
    PlacedOrder,
    QuoteRefused,
    SavedQuote,
)
from app.modules.payments import service as payments
from app.modules.shop_profile import service as shop_profile

log = structlog.get_logger()

QUOTE_LIFETIME = timedelta(hours=2)
DRAFT_STAGES = frozenset({"browsing", "collecting_details", "awaiting_confirmation"})


class DraftItem(BaseModel):
    item_id: str = Field(min_length=2, max_length=20)
    quantity: int = Field(ge=1, le=1000)
    options: str | None = Field(default=None, max_length=200)


class UpdateOrderDraftArgs(BaseModel):
    items: list[DraftItem] | None = Field(default=None, max_length=30)
    fulfilment: Literal["pickup", "delivery"] | None = None
    delivery_address: str | None = Field(default=None, max_length=500)
    needed_by: str | None = Field(default=None, max_length=200)
    notes: str | None = Field(default=None, max_length=500)
    date: str | None = Field(
        default=None, description="Pickup or delivery day, YYYY-MM-DD (default: today)"
    )


class UpdateOrderDraft(Tool):
    name = "update_order_draft"
    Args = UpdateOrderDraftArgs
    stages = DRAFT_STAGES
    writes = True

    async def run(self, ctx: TurnContext, args: UpdateOrderDraftArgs) -> ToolResult:
        if args.date is not None:
            problem = _date_problem(ctx, args.date)
            if problem is not None:
                return problem
        known = ctx.all_items()
        if args.items is not None:
            unknown = [i.item_id for i in args.items if items.resolve(i.item_id, known) is None]
            if unknown:
                return ToolResult.fail(
                    "unknown_item",
                    f"Not in today's menu: {', '.join(unknown)}",
                    "Use the ids from search_catalog or today's menu",
                )
        async with session_scope() as session:
            state = await conversations.load_state(session, ctx.conversation_id, lock=True)
            if state is None:
                return ToolResult.fail("no_conversation", "The conversation is gone")
            draft = dict(state.draft)
            if args.items is not None:
                draft["items"] = [i.model_dump(exclude_none=True) for i in args.items]
            for field in ("fulfilment", "delivery_address", "needed_by", "notes", "date"):
                value = getattr(args, field)
                if value is not None:
                    draft[field] = value
            if state.stage == "awaiting_confirmation":
                await orders.supersede_quotes(session, ctx.conversation_id)
            await conversations.set_stage(
                session, ctx.conversation_id, "collecting_details", draft=draft
            )
        ctx.stage = "collecting_details"
        missing, problems = _check(draft, ctx)
        return ToolResult(
            True,
            {
                "draft": _summary(draft, ctx),
                "missing": missing,
                "stock_problems": problems,
                "next": "create_quote" if not missing and not problems else "ask the customer",
            },
        )

    def replay(self, ctx: TurnContext, result: ToolResult) -> None:
        if result.ok:
            ctx.stage = "collecting_details"


class CreateQuoteArgs(BaseModel):
    language: str | None = Field(default=None, max_length=16)


class CreateQuote(Tool):
    name = "create_quote"
    Args = CreateQuoteArgs
    stages = frozenset({"collecting_details"})
    writes = True

    async def run(self, ctx: TurnContext, args: CreateQuoteArgs) -> ToolResult:
        language = args.language or ctx.language
        async with session_scope() as session:
            state = await conversations.load_state(session, ctx.conversation_id, lock=True)
            if state is None:
                return ToolResult.fail("no_conversation", "The conversation is gone")
            missing, problems = _check(state.draft, ctx)
            if missing or problems:
                return ToolResult.fail(
                    "incomplete_draft",
                    "; ".join([*(f"missing {m}" for m in missing), *problems]),
                    "Ask the customer, then update_order_draft",
                )
            saved = await orders.save_quote(
                session,
                merchant_id=ctx.merchant.id,
                conversation_id=ctx.conversation_id,
                customer_id=ctx.customer_id,
                business_date=ctx.business_date,
                request=_request(state.draft, ctx),
                expires_at=_expiry(ctx),
                business_date_override=_day(state.draft) or ctx.business_date,
            )
            if not isinstance(saved, SavedQuote):
                return ToolResult.fail("cannot_quote", "; ".join(saved.problems))
            await conversations.queue_message(
                session,
                conversation_id=ctx.conversation_id,
                text=_card_text(saved, language, ctx.business_date),
                key=f"quote:{saved.id}:card",
                details={"quote_id": str(saved.id), "kind": "quote_card", "language": language},
                quick_replies=(
                    (prompt_store.text("quote_card.confirm", language), f"CONFIRM:{saved.id}"),
                    (prompt_store.text("quote_card.change", language), f"CHANGE:{saved.id}"),
                ),
            )
            await conversations.set_stage(session, ctx.conversation_id, "awaiting_confirmation")
        ctx.stage = "awaiting_confirmation"
        ctx.prompt_refs.add(prompt_store.ref("quote_card"))
        return ToolResult(
            True,
            {
                "quote_id": str(saved.id),
                "total": "[[quote_total]]",
                "expires_at": saved.expires_at.isoformat(),
                "card": "Being sent: the items, the total and Confirm / Change buttons. Don't "
                "repeat the items; one short line asking them to confirm is enough.",
            },
        )

    def replay(self, ctx: TurnContext, result: ToolResult) -> None:
        if result.ok:
            ctx.stage = "awaiting_confirmation"


class ConfirmOrderArgs(BaseModel):
    quote_id: str = Field(min_length=1, max_length=64)
    customer_message_id: str | None = Field(default=None, max_length=64)


class ConfirmOrder(Tool):
    name = "confirm_order"
    Args = ConfirmOrderArgs
    stages = frozenset({"awaiting_confirmation"})
    writes = True

    async def run(self, ctx: TurnContext, args: ConfirmOrderArgs) -> ToolResult:
        return await confirm(ctx, args.quote_id, tapped=False)

    def replay(self, ctx: TurnContext, result: ToolResult) -> None:
        if result.ok:
            ctx.stage = "payment_pending"
            ctx.payment_link = result.private.get("payment_link")


async def confirm(ctx: TurnContext, quote_ref: str, *, tapped: bool) -> ToolResult:
    """Place the order from a quote: a Confirm tap (proof by itself) or a typed yes."""
    try:
        quote_id = uuid.UUID(quote_ref)
    except ValueError:
        return ToolResult.fail("unknown_quote", f"No quote {quote_ref}")
    async with session_scope() as session:
        quote = await orders.get_quote(session, quote_id, ctx.conversation_id)
    if quote is None:
        return ToolResult.fail("unknown_quote", f"No quote {quote_ref} in this conversation")
    if quote.shown_at is None or quote.shown_at >= ctx.trigger_created_at:
        return ToolResult.fail(
            "not_shown",
            "The customer hasn't received this quote card, so it can't be confirmed",
            "Tell the customer you'll send the quote again, or ask the shop owner",
        )
    if not tapped:
        answer = await affirmation.classify(ctx.customer_text)
        if answer == "no":
            return ToolResult.fail(
                "customer_declined", "The customer said no", "Ask what they'd like instead"
            )
        if answer == "change":
            return ToolResult.fail(
                "customer_wants_change",
                "The customer wants a change",
                "Use update_order_draft, then create_quote again",
            )
        if answer != "yes":
            return ToolResult.fail(
                "unclear", "It isn't clear the customer agreed", "Ask them to confirm"
            )
    try:
        async with session_scope() as session:
            await conversations.load_state(session, ctx.conversation_id, lock=True)
            placed = await orders.confirm_quote(
                session,
                quote_id=quote_id,
                conversation_id=ctx.conversation_id,
                hold_minutes=get_settings().payment_hold_minutes,
                now=ctx.now,
            )
            await conversations.set_stage(session, ctx.conversation_id, "payment_pending", draft={})
    except QuoteRefused as refused:
        return ToolResult.fail(refused.code, str(refused), "Make a new quote if they still want it")
    except orders.OrderProblem as problem:
        return ToolResult.fail(
            "stock_problem", "; ".join(problem.problems), "Suggest something else from the menu"
        )
    ctx.stage = "payment_pending"
    payment, link = await _send_payment(ctx, placed)
    ctx.payment_link = link
    return ToolResult(
        True,
        {
            "order_number": "[[order_number]]",
            "total": "[[order_total]]",
            "payment": payment,
            "hold_minutes": placed.hold_minutes,
            "next": "The payment message is on its way. Thank the customer in one short line.",
        },
        private={"order_id": str(placed.order_id), "payment_link": link},
    )


async def change_from_tap(ctx: TurnContext, quote_ref: str) -> ToolResult:
    """The customer tapped Change: the quote can't be confirmed any more."""
    async with session_scope() as session:
        state = await conversations.load_state(session, ctx.conversation_id, lock=True)
        if state is None or state.stage != "awaiting_confirmation":
            return ToolResult(True, {"note": "Nothing to change"})
        await orders.supersede_quotes(session, ctx.conversation_id)
        await conversations.set_stage(session, ctx.conversation_id, "collecting_details")
    ctx.stage = "collecting_details"
    return ToolResult(True, {"quote_id": quote_ref, "event": "customer_tapped_change"})


class GetOrderStatusArgs(BaseModel):
    order_number: int | None = Field(default=None, ge=1)


class GetOrderStatus(Tool):
    name = "get_order_status"
    Args = GetOrderStatusArgs

    async def run(self, ctx: TurnContext, args: GetOrderStatusArgs) -> ToolResult:
        async with session_scope() as session:
            found = await orders.customer_orders(session, ctx.merchant.id, ctx.customer_id)
        if args.order_number is not None:
            found = [order for order in found if order.number == args.order_number]
        if not found:
            return ToolResult(True, {"orders": []}, hint="No orders found for this customer")
        return ToolResult(
            True,
            {
                "orders": [
                    {
                        "number": f"#{order.number}",
                        "status": order.status,
                        "payment": order.payment_status,
                        "fulfilment": order.fulfilment_status,
                        "total": "[[order_total]]" if index == 0 else None,
                        "placed": order.created_at.date().isoformat(),
                    }
                    for index, order in enumerate(found)
                ]
            },
        )


class OrderArgs(BaseModel):
    order_id: str = Field(min_length=1, max_length=64)


class CancelOrderArgs(OrderArgs):
    reason: str = Field(min_length=1, max_length=200)


class CancelOrder(Tool):
    name = "cancel_order"
    Args = CancelOrderArgs
    stages = frozenset({"payment_pending"})
    writes = True

    async def run(self, ctx: TurnContext, args: CancelOrderArgs) -> ToolResult:
        order_id = await _own_unpaid_order(ctx, args.order_id)
        if order_id is None:
            return ToolResult.fail("unknown_order", "No unpaid order with that id in this chat")
        async with session_scope() as session:
            await orders.cancel_order(
                session,
                order_id,
                merchant_id=ctx.merchant.id,
                actor="customer",
                reason=args.reason,
            )
            await conversations.set_stage(session, ctx.conversation_id, "browsing", draft={})
        ctx.stage = "browsing"
        return ToolResult(True, {"cancelled": True, "stock": "released"})

    def replay(self, ctx: TurnContext, result: ToolResult) -> None:
        if result.ok:
            ctx.stage = "browsing"


class ResendPaymentLink(Tool):
    name = "resend_payment_link"
    Args = OrderArgs
    stages = frozenset({"payment_pending"})
    writes = True

    async def run(self, ctx: TurnContext, args: OrderArgs) -> ToolResult:
        order_id = await _own_unpaid_order(ctx, args.order_id)
        if order_id is None:
            return ToolResult.fail("unknown_order", "No unpaid order with that id in this chat")
        async with session_scope() as session:
            order = await orders.get_order(session, order_id, ctx.merchant.id)
        assert order is not None
        placed = PlacedOrder(
            order.id,
            order.number,
            order.currency,
            order.total_minor,
            get_settings().payment_hold_minutes,
        )
        # The same PayPal order (its request id is per order) or the same UPI link: never a
        # second payment for one order.
        payment, link = await _send_payment(ctx, placed, resend=True)
        ctx.payment_link = link
        return ToolResult(True, {"payment": payment}, private={"payment_link": link})

    def replay(self, ctx: TurnContext, result: ToolResult) -> None:
        ctx.payment_link = result.private.get("payment_link") or ctx.payment_link


async def _own_unpaid_order(ctx: TurnContext, order_ref: str) -> uuid.UUID | None:
    try:
        order_id = uuid.UUID(order_ref)
    except ValueError:
        return None
    async with session_scope() as session:
        order = await orders.get_order(session, order_id, ctx.merchant.id)
    if order is None or order.conversation_id != ctx.conversation_id:
        return None
    return order.id if order.status == "awaiting_payment" else None


async def _send_payment(
    ctx: TurnContext, placed: PlacedOrder, *, resend: bool = False
) -> tuple[str, str | None]:
    """Queue the payment message: UPI if the shop has a UPI id, PayPal, or details by hand."""
    total = format_money(placed.total_minor, placed.currency)
    async with session_scope() as session:
        onboarding = await shop_profile.get_onboarding(session, ctx.merchant.id)
    vpa = (onboarding.answers or {}).get("upi_id") if onboarding else None
    link: str | None = None
    if placed.currency == "INR" and vpa:
        link = payments.create_upi_checkout(placed, vpa=vpa, shop_name=ctx.merchant.name)
    elif payments.accepts(placed.currency):
        try:
            link = await payments.create_checkout(placed, shop_name=ctx.merchant.name)
        except payments.PaymentUnavailable as exc:
            log.error("agent.checkout_failed", order_id=str(placed.order_id), error=str(exc))
    values: dict[str, Any] = {"number": f"#{placed.number}", "total": total}
    async with session_scope() as session:
        if link:
            text = prompt_store.text(
                "payment_link", ctx.language, link=link, hold_minutes=placed.hold_minutes, **values
            )
        else:
            text = prompt_store.text("payment_offline", ctx.language, **values)
        if not link and not resend:
            await escalations.open_escalation(
                session,
                merchant_id=ctx.merchant.id,
                conversation_id=ctx.conversation_id,
                question=f"Order #{placed.number} ({total}) is confirmed. Online payment isn't "
                "available for it: please share payment details with the customer.",
                trigger_message_id=ctx.trigger_message_id,
            )
        await conversations.queue_message(
            session,
            conversation_id=ctx.conversation_id,
            text=text,
            key=f"order:{placed.order_id}:link" + (f":resend:{ctx.turn_id}" if resend else ""),
            details={"order_id": str(placed.order_id), "kind": "payment"},
        )
    return ("link_sent" if link else "shop_will_share_payment_details"), link


def _date_problem(ctx: TurnContext, value: str) -> ToolResult | None:
    try:
        day = date.fromisoformat(value)
    except ValueError:
        return ToolResult.fail("invalid_date", f"{value!r} isn't a date: use YYYY-MM-DD")
    if day < ctx.business_date:
        return ToolResult.fail("invalid_date", "That day has passed", "Ask which day they mean")
    if day > ctx.business_date + timedelta(days=get_settings().agent_order_days_ahead):
        return ToolResult.fail(
            "too_far_ahead",
            "Orders can only be taken for the next two weeks",
            "Ask the shop owner about orders further ahead",
        )
    return None


def _day(draft: dict[str, Any]) -> date | None:
    return date.fromisoformat(draft["date"]) if draft.get("date") else None


def _check(draft: dict[str, Any], ctx: TurnContext) -> tuple[list[str], list[str]]:
    missing: list[str] = []
    problems: list[str] = []
    day = _day(draft)
    stock = ctx.stock_on(day)
    if not draft.get("items"):
        missing.append("items")
    if not draft.get("fulfilment"):
        missing.append("pickup or delivery")
    elif draft["fulfilment"] == "delivery" and not draft.get("delivery_address"):
        missing.append("delivery address")
    for line in draft.get("items", []):
        item = items.resolve(line["item_id"], stock)
        if item is None:
            when = f"on {context.day_text(day)}" if day else "today"
            problems.append(f"{line['item_id']} isn't available {when}")
        elif item.available < line["quantity"]:
            problems.append(
                f"{item.label}: only {item.available} left"
                if item.available
                else f"{item.label} is sold out"
            )
    return missing, problems


def _summary(draft: dict[str, Any], ctx: TurnContext) -> dict[str, Any]:
    lines = []
    stock = ctx.stock_on(_day(draft))
    for line in draft.get("items", []):
        item = items.resolve(line["item_id"], stock)
        lines.append(
            {
                "id": line["item_id"],
                "name": item.label if item else None,
                "quantity": line["quantity"],
                "price": f"[[price:{line['item_id']}]]",
            }
        )
    day = _day(draft)
    return {
        "items": lines,
        **{k: draft.get(k) for k in ("fulfilment", "delivery_address", "needed_by", "notes")},
        "date": context.day_text(day) if day else "today",
    }


def _request(draft: dict[str, Any], ctx: TurnContext) -> OrderRequest:
    lines = []
    stock = ctx.stock_on(_day(draft))
    for line in draft["items"]:
        item = items.resolve(line["item_id"], stock)
        assert item is not None  # checked by _check
        lines.append(OrderLineRequest(item.product, item.variant, int(line["quantity"])))
    return OrderRequest(
        lines=tuple(lines),
        fulfilment=draft.get("fulfilment"),
        delivery_address=draft.get("delivery_address"),
        needed_by=draft.get("needed_by"),
        notes=draft.get("notes"),
        scheduled_date=_day(draft),
    )


def _expiry(ctx: TurnContext) -> datetime:
    """The earlier of two hours from now and the end of the shop's business day."""
    zone = ZoneInfo(ctx.merchant.timezone)
    end_of_day = datetime.combine(ctx.business_date + timedelta(days=1), time(0), zone)
    return min(ctx.now + QUOTE_LIFETIME, end_of_day)


def _card_text(quote: SavedQuote, language: str, today: date) -> str:
    return prompt_store.text(
        "quote_card",
        language,
        lines=[
            {
                "quantity": line.quantity,
                "label": line.label,
                "subtotal": format_money(line.subtotal_minor, line.currency),
            }
            for line in quote.lines
        ],
        total=format_money(quote.total_minor, quote.currency),
        fulfilment=quote.fulfilment,
        address=quote.delivery_address,
        needed_by=quote.needed_by,
        date_text=context.day_text(quote.business_date) if quote.business_date != today else None,
    )


register(UpdateOrderDraft())
register(CreateQuote())
register(ConfirmOrder())
register(GetOrderStatus())
register(CancelOrder())
register(ResendPaymentLink())
