"""Carrying out the agent's actions inside a customer turn: quotes and placing orders.

Each action returns a note for the agent (prices, totals and order numbers come from here,
never from the model) and, for a placed order, the payment link to put in the reply.
"""

import uuid
from dataclasses import dataclass
from datetime import date

import structlog

from app.core.config import get_settings
from app.core.db import session_scope
from app.core.money import format_money
from app.modules.agent import service as agent
from app.modules.agent.schemas import AgentAction, OrderDraft
from app.modules.escalations import service as escalations
from app.modules.orders import service as orders
from app.modules.orders.schemas import OrderLineRequest, OrderRequest, PlacedOrder, Quote
from app.modules.payments import service as payments
from app.modules.shop_profile import service as shop_profile

log = structlog.get_logger()

# v1 fallbacks go out in English: the turn failed before we learned the customer's language.
FALLBACK_LANGUAGE = "en"


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
    note: str  # for the agent, as a [Shop system] note
    payment_link: str | None = None
    order_id: uuid.UUID | None = None
    # Sent instead of the agent's message if the agent fails after the order was placed.
    fallback_text: str | None = None


async def perform(context: TurnContext, action: AgentAction) -> ActionOutcome:
    request = _order_request(action.order)
    if action.type == "quote_order":
        async with session_scope() as session:
            offer = await orders.quote(
                session,
                merchant_id=context.merchant_id,
                business_date=context.business_date,
                request=request,
            )
        return ActionOutcome(note=_quote_note(offer))
    return await _place(context, request)


async def _place(context: TurnContext, request: OrderRequest) -> ActionOutcome:
    try:
        async with session_scope() as session:
            placed = await orders.place_order(
                session,
                merchant_id=context.merchant_id,
                customer_id=context.customer_id,
                conversation_id=context.conversation_id,
                business_date=context.business_date,
                request=request,
                hold_minutes=get_settings().payment_hold_minutes,
            )
    except orders.OrderProblem as problem:
        return ActionOutcome(
            note=agent.prompt("v1.note.order_failed", problems=list(problem.problems))
        )

    total = format_money(placed.total_minor, placed.currency)
    if placed.currency == "INR":
        async with session_scope() as session:
            onboarding = await shop_profile.get_onboarding(session, context.merchant_id)
            vpa = onboarding.answers.get("upi_id") if onboarding and onboarding.answers else None
        if vpa:
            upi_link = payments.create_upi_checkout(placed, vpa=vpa, shop_name=context.shop_name)
            return ActionOutcome(
                note=_placed_note(placed, total, "upi"),
                payment_link=upi_link,
                order_id=placed.order_id,
                fallback_text=_fallback(placed, total, upi_link),
            )

    if payments.accepts(placed.currency):
        try:
            link = await payments.create_checkout(placed, shop_name=context.shop_name)
        except payments.PaymentUnavailable as exc:
            log.error(
                "conversations.checkout_failed", order_id=str(placed.order_id), error=str(exc)
            )
        else:
            return ActionOutcome(
                note=_placed_note(placed, total, "paypal"),
                payment_link=link,
                order_id=placed.order_id,
                fallback_text=_fallback(placed, total, link),
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
        note=agent.prompt("v1.note.order_placed_offline", number=placed.number, total=total),
        order_id=placed.order_id,
        fallback_text=agent.fixed_text(
            "v1.order_fallback_offline", FALLBACK_LANGUAGE, number=placed.number, total=total
        ),
    )


def _placed_note(placed: PlacedOrder, total: str, method: str) -> str:
    return agent.prompt(
        "v1.note.order_placed",
        number=placed.number,
        total=total,
        hold_minutes=placed.hold_minutes,
        method=method,
    )


def _fallback(placed: PlacedOrder, total: str, link: str) -> str:
    return agent.fixed_text(
        "v1.order_fallback", FALLBACK_LANGUAGE, number=placed.number, total=total, link=link
    )


def _quote_note(offer: Quote) -> str:
    if not offer.ok or offer.currency is None:
        return agent.prompt("v1.note.no_quote", problems=list(offer.problems))
    lines = [
        {
            "quantity": line.quantity,
            "label": line.label,
            "unit_price": format_money(line.unit_price_minor, line.currency),
            "subtotal": format_money(line.subtotal_minor, line.currency),
        }
        for line in offer.lines
    ]
    return agent.prompt(
        "v1.note.quote", lines=lines, total=format_money(offer.total_minor, offer.currency)
    )


def _order_request(draft: OrderDraft) -> OrderRequest:
    return OrderRequest(
        lines=tuple(
            OrderLineRequest(product=item.product, variant=item.variant, quantity=item.quantity)
            for item in draft.items
        ),
        fulfilment=draft.fulfilment,
        delivery_address=draft.delivery_address,
        needed_by=draft.needed_by,
        notes=draft.notes,
    )
