"""Job entry points for the conversations module, and telling customers about order events."""

import uuid
from contextlib import suppress
from datetime import timedelta

import structlog
from procrastinate.exceptions import AlreadyEnqueued

from app.core.config import get_settings
from app.core.db import session_scope
from app.core.jobs import jobs
from app.core.money import format_money
from app.modules.conversations import service
from app.modules.conversations.service import TurnRequest
from app.modules.escalations import service as escalations
from app.modules.orders.schemas import ExpiredOrder, PaymentResult
from app.modules.payments.service import PaymentFailed

log = structlog.get_logger()


@jobs.task(name="run_agent_turn", queue="agent")
async def run_agent_turn(conversation_id: str) -> None:
    await service.run_turn(uuid.UUID(conversation_id))


async def request_turn(turn: TurnRequest) -> None:
    """Queue a reply. One queued turn per chat, run one at a time, after a short wait so a
    burst of messages gets a single reply."""
    conversation_id = str(turn.conversation_id)
    # If a turn is already queued, it will see this message too: nothing more to do.
    with suppress(AlreadyEnqueued):
        await run_agent_turn.configure(
            lock=f"conversation:{conversation_id}",
            queueing_lock=f"turn:{conversation_id}",
            schedule_in={"seconds": get_settings().turn_batch_seconds},
        ).defer_async(conversation_id=conversation_id)


@jobs.periodic(cron="* * * * *")
@jobs.task(name="reconcile_unanswered", queue="agent")
async def reconcile_unanswered(timestamp: int) -> None:
    """Every minute: queue turns for chats left unanswered (e.g. a failed enqueue)."""
    async with session_scope() as session:
        conversation_ids = await service.unanswered_conversations(
            session, waiting_longer_than=timedelta(seconds=30), max_age=timedelta(hours=24)
        )
    for conversation_id in conversation_ids:
        await request_turn(TurnRequest(conversation_id))
    if conversation_ids:
        log.info("conversations.reconciled", count=len(conversation_ids))


async def inform_customer(conversation_id: uuid.UUID | None, note: str) -> None:
    """Have the agent tell the customer something, in their language, in their chat."""
    if conversation_id is None:
        return
    async with session_scope() as session:
        turn = await service.add_system_note(session, conversation_id, note)
    if turn is not None:
        await request_turn(turn)


async def after_payment(result: PaymentResult | PaymentFailed) -> None:
    """Tell the customer (and, if needed, the merchant) what a payment event means."""
    if isinstance(result, PaymentFailed):
        await inform_customer(
            result.conversation_id,
            f"The PayPal payment for order #{result.number} didn't go through. Ask the customer "
            "to try again with the same link.",
        )
        return

    total = format_money(result.total_minor, result.currency)
    if result.outcome == "paid":
        await inform_customer(
            result.conversation_id,
            f"Payment of {total} received for order #{result.number}. Thank the customer and "
            "confirm the order; the shop will be in touch about pickup or delivery.",
        )
    elif result.outcome == "paid_stock_short":
        await _ask_merchant(
            result,
            f"Order #{result.number} ({total}) was paid after its hold expired, and some items "
            "have sold out since. Please arrange a replacement or a refund.",
        )
        await inform_customer(
            result.conversation_id,
            f"Payment of {total} received for order #{result.number}, but some items sold out "
            "after the hold expired. Tell the customer the shop will contact them about a "
            "replacement or a refund.",
        )
    elif result.outcome == "amount_mismatch":
        await _ask_merchant(
            result,
            f"The PayPal payment for order #{result.number} doesn't match the order total "
            f"({total}). Please check it in PayPal.",
        )


async def after_expiry(order: ExpiredOrder) -> None:
    await inform_customer(
        order.conversation_id,
        f"Order #{order.number} wasn't paid in time, so the items were released. Ask the "
        "customer if they'd still like to order.",
    )


async def _ask_merchant(result: PaymentResult, question: str) -> None:
    if result.conversation_id is None:
        log.warning("conversations.payment_issue_without_chat", order_id=str(result.order_id))
        return
    async with session_scope() as session:
        await escalations.open_escalation(
            session,
            merchant_id=result.merchant_id,
            conversation_id=result.conversation_id,
            question=question,
        )
