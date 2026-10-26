"""Carrying out the agent's actions inside a customer turn: quotes and placing orders.

Each action returns a note for the agent (prices, totals and order numbers come from here,
never from the model) and, for a placed order, the payment link to put in the reply.

Code keeps the chat's order stage, and it alone decides what the agent may do next:
browsing -> collecting_details (a draft that can't be quoted yet) -> awaiting_confirmation (a
saved quote) -> payment_pending (an order) -> browsing once that order is paid, expired or
cancelled. An order is placed only from the current quote, only after the customer has seen
it and answered, and only once.
"""

import uuid
from dataclasses import dataclass
from datetime import date, datetime
from typing import Any

import structlog
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.db import session_scope
from app.core.money import format_money
from app.modules.agent.schemas import AgentAction, OrderDraft
from app.modules.conversations.models import Conversation, Message
from app.modules.escalations import service as escalations
from app.modules.orders import service as orders
from app.modules.orders.schemas import (
    OrderLineRequest,
    OrderRequest,
    Quote,
    QuoteLine,
    StoredQuote,
)
from app.modules.payments import service as payments

log = structlog.get_logger()


@dataclass(frozen=True)
class TurnContext:
    conversation_id: uuid.UUID
    merchant_id: uuid.UUID
    shop_name: str
    customer_id: uuid.UUID
    customer_external_id: str
    channel_connection_id: uuid.UUID
    business_date: date
    trigger_message_id: uuid.UUID


@dataclass(frozen=True)
class ActionOutcome:
    note: str  # for the agent, as a shop-system note
    payment_link: str | None = None
    order_id: uuid.UUID | None = None
    # Sent instead of the agent's message if the agent fails after the order was placed.
    fallback_text: str | None = None


async def perform(context: TurnContext, action: AgentAction) -> ActionOutcome:
    if action.type == "quote_order" and action.order is not None:
        return await _quote(context, action.order)
    return await _place(context, (action.quote_id or "").strip().lower())


async def order_summary(session: AsyncSession, conversation: Conversation) -> str:
    """Where the chat's order stands, in a few lines for the agent."""
    await _settle(session, conversation)
    if conversation.order_stage == "payment_pending" and conversation.current_order_id:
        state = await orders.order_state(session, conversation.current_order_id)
        if state is not None:
            return (
                f"Order #{state.number} (total {format_money(state.total_minor, state.currency)})"
                " is placed and waiting for payment; the payment details have been sent. Don't "
                "place it again. A new order can be quoted once it's paid or released."
            )
    if conversation.order_stage == "awaiting_confirmation" and conversation.current_quote_id:
        saved = await orders.get_quote(session, conversation.current_quote_id)
        if saved is not None:
            shown = await _customer_answered(session, conversation.id, saved.created_at)
            return (
                f"Quote {saved.code}: {_quote_lines(saved.lines)}. Total "
                f"{format_money(saved.total_minor, saved.currency)}.{_details(saved)} "
                + (
                    "The customer has seen it and replied: if they agreed to it, request "
                    f'place_order with quote_id "{saved.code}"; if they changed anything, '
                    "request quote_order again."
                    if shown
                    else "Not yet confirmed by the customer: show it with the total and ask them "
                    "to confirm."
                )
            )
    if conversation.order_stage == "collecting_details" and conversation.order_draft:
        return _draft_summary(conversation.order_draft)
    return "No order in progress."


async def _quote(context: TurnContext, draft: OrderDraft) -> ActionOutcome:
    request = _order_request(draft)
    async with session_scope() as session:
        conversation = await _locked(session, context.conversation_id)
        await _settle(session, conversation)
        if conversation.order_stage == "payment_pending":
            return ActionOutcome(
                note="An order in this chat is still waiting for payment, so a new one can't be "
                "quoted yet. If the customer wants to change it, tell them you'll check with the "
                "shop and set needs_owner."
            )
        offer = await orders.quote(
            session,
            merchant_id=context.merchant_id,
            business_date=context.business_date,
            request=request,
        )
        conversation.order_draft = draft.model_dump(mode="json", exclude_none=True)
        if not offer.ok or offer.currency is None:
            await orders.supersede_quotes(session, conversation.id)
            conversation.order_stage = "collecting_details"
            conversation.current_quote_id = None
            return ActionOutcome(note=_no_quote_note(offer))
        saved = await orders.save_quote(
            session,
            merchant_id=context.merchant_id,
            conversation_id=conversation.id,
            offer=offer,
            request=request,
        )
        conversation.order_stage = "awaiting_confirmation"
        conversation.current_quote_id = saved.id
    return ActionOutcome(note=_quote_note(saved))


async def _place(context: TurnContext, quote_code: str) -> ActionOutcome:
    async with session_scope() as session:
        conversation = await _locked(session, context.conversation_id)
        await _settle(session, conversation)
        refusal, saved = await _placeable(session, conversation, quote_code)
        if refusal is not None or saved is None:
            log.warning(
                "conversations.place_refused",
                conversation_id=str(conversation.id),
                quote=quote_code,
                stage=conversation.order_stage,
            )
            return ActionOutcome(note=refusal or "There's no quote to place.")
        try:
            async with session.begin_nested():  # a failed placement releases its holds
                placed = await orders.place_quote(
                    session,
                    quote_id=saved.id,
                    customer_id=context.customer_id,
                    business_date=context.business_date,
                    hold_minutes=get_settings().payment_hold_minutes,
                )
        except orders.OrderProblem as problem:
            await orders.supersede_quotes(session, conversation.id)
            conversation.order_stage = "collecting_details"
            conversation.current_quote_id = None
            return ActionOutcome(
                note=f"The order couldn't be placed: {'; '.join(problem.problems)}. Tell the "
                "customer and suggest alternatives from today's stock, then quote again."
            )
        conversation.order_stage = "payment_pending"
        conversation.current_order_id = placed.order_id

    total = format_money(placed.total_minor, placed.currency)
    if payments.accepts(placed.currency):
        try:
            link = await payments.create_checkout(placed, shop_name=context.shop_name)
        except payments.PaymentUnavailable as exc:
            log.error(
                "conversations.checkout_failed", order_id=str(placed.order_id), error=str(exc)
            )
        else:
            return ActionOutcome(
                note=f"Order #{placed.number} is placed, total {total}. The items are held for "
                f"{placed.hold_minutes} minutes. A PayPal payment link will be added to your "
                "message: put {payment_link} where it belongs.",
                payment_link=link,
                order_id=placed.order_id,
                fallback_text=f"Order #{placed.number} ({total}): {link}",
            )

    # No online payment for this order: the merchant shares payment details.
    async with session_scope() as session:
        await escalations.open_escalation(
            session,
            merchant_id=context.merchant_id,
            conversation_id=context.conversation_id,
            question=f"Order #{placed.number} ({total}) is confirmed. Online payment isn't "
            "available for it: please share payment details with the customer.",
            trigger_message_id=context.trigger_message_id,
        )
    return ActionOutcome(
        note=f"Order #{placed.number} is placed, total {total}. Online payment isn't available "
        "for this order: tell the customer the shop will share payment details shortly.",
        order_id=placed.order_id,
        fallback_text=f"Order #{placed.number} ({total}) is confirmed. "
        "We'll share payment details shortly.",
    )


async def _placeable(
    session: AsyncSession, conversation: Conversation, quote_code: str
) -> tuple[str | None, StoredQuote | None]:
    """The current quote, if the customer may now have it placed; otherwise why not."""
    if conversation.order_stage == "payment_pending" and conversation.current_order_id:
        state = await orders.order_state(session, conversation.current_order_id)
        number = f" #{state.number}" if state else ""
        return f"Order{number} is already placed for this quote: don't place it again.", None
    saved = (
        await orders.get_quote(session, conversation.current_quote_id)
        if conversation.order_stage == "awaiting_confirmation" and conversation.current_quote_id
        else None
    )
    if saved is None:
        return (
            "There's no quote waiting for the customer's confirmation, so nothing was placed. "
            "Request quote_order first and show the customer the total."
        ), None
    if quote_code != saved.code:
        return (
            f'Quote "{quote_code}" isn\'t the current quote, so nothing was placed. The current '
            f"quote is {saved.code}: {_quote_lines(saved.lines)}, total "
            f"{format_money(saved.total_minor, saved.currency)}. Place it only if that's what "
            "the customer agreed to."
        ), None
    if not await _customer_answered(session, conversation.id, saved.created_at):
        return (
            f"The customer hasn't seen and answered quote {saved.code} yet, so nothing was "
            "placed. Show it with the total and ask them to confirm; place it only after they "
            "agree."
        ), None
    return None, saved


async def _customer_answered(
    session: AsyncSession, conversation_id: uuid.UUID, quoted_at: datetime
) -> bool:
    """Whether a reply was sent after the quote and the customer has written since."""
    shown_at = await session.scalar(
        select(Message.created_at)
        .where(
            Message.conversation_id == conversation_id,
            Message.sender == "agent",
            Message.status == "sent",
            Message.created_at > quoted_at,
        )
        .order_by(Message.created_at)
        .limit(1)
    )
    if shown_at is None:
        return False
    answer = await session.scalar(
        select(Message.id)
        .where(
            Message.conversation_id == conversation_id,
            Message.sender == "customer",
            Message.created_at > shown_at,
        )
        .limit(1)
    )
    return answer is not None


async def _settle(session: AsyncSession, conversation: Conversation) -> None:
    """Once the chat's order is no longer waiting for payment (paid, expired, cancelled),
    the chat starts afresh."""
    if conversation.order_stage != "payment_pending":
        return
    state = (
        await orders.order_state(session, conversation.current_order_id)
        if conversation.current_order_id
        else None
    )
    if state is None or state.status != "awaiting_payment":
        conversation.order_stage = "browsing"
        conversation.order_draft = None
        conversation.current_quote_id = None
        conversation.current_order_id = None


async def _locked(session: AsyncSession, conversation_id: uuid.UUID) -> Conversation:
    conversation = await session.scalar(
        select(Conversation).where(Conversation.id == conversation_id).with_for_update()
    )
    if conversation is None:
        raise LookupError(f"No conversation {conversation_id}")
    return conversation


def _quote_note(saved: StoredQuote) -> str:
    return (
        f"Quote {saved.code}: {_quote_lines(saved.lines)}. Total "
        f"{format_money(saved.total_minor, saved.currency)}. Everything is available. Summarise "
        "this for the customer, with the total, and ask them to confirm. Once they agree, in a "
        f'later message, request place_order with quote_id "{saved.code}".'
    )


def _no_quote_note(offer: Quote) -> str:
    problems = "; ".join(offer.problems) or "no items were given"
    return f"No quote: {problems}. Tell the customer and suggest alternatives from today's stock."


def _quote_lines(lines: tuple[QuoteLine, ...]) -> str:
    return ", ".join(
        f"{line.quantity} x {line.label} at {format_money(line.unit_price_minor, line.currency)}"
        f" = {format_money(line.subtotal_minor, line.currency)}"
        for line in lines
    )


def _details(saved: StoredQuote) -> str:
    parts = []
    if saved.fulfilment == "delivery":
        parts.append(f"Delivery to {saved.delivery_address or '(address missing)'}")
    elif saved.fulfilment == "pickup":
        parts.append("Pickup")
    if saved.needed_by:
        parts.append(f"needed {saved.needed_by}")
    return f" {', '.join(parts)}." if parts else ""


def _draft_summary(draft: dict[str, Any]) -> str:
    items = ", ".join(
        f"{item.get('quantity', 1)} x "
        + (
            " ".join(p for p in (item.get("product"), item.get("variant")) if p)
            or f"item {item.get('id')}"
        )
        for item in draft.get("items", [])
    )
    missing = []
    if not draft.get("fulfilment"):
        missing.append("pickup or delivery")
    elif draft["fulfilment"] == "delivery" and not draft.get("delivery_address"):
        missing.append("the delivery address")
    if not draft.get("needed_by"):
        missing.append("when they need it")
    return (
        f"Order being collected (no valid quote yet): {items or 'no items yet'}. "
        + (f"Still to ask: {', '.join(missing)}." if missing else "")
    ).strip()


def _order_request(draft: OrderDraft) -> OrderRequest:
    return OrderRequest(
        lines=tuple(
            OrderLineRequest(
                product=item.product or "",
                variant=item.variant,
                quantity=item.quantity,
                ref=item.id,
            )
            for item in draft.items
        ),
        fulfilment=draft.fulfilment,
        delivery_address=draft.delivery_address,
        needed_by=draft.needed_by,
        notes=draft.notes,
    )
