"""Job entry points for the conversations module, and telling customers about order events."""

import uuid
from contextlib import suppress
from datetime import UTC, datetime, timedelta
from typing import Any

import procrastinate
import structlog
from procrastinate.exceptions import AlreadyEnqueued

from app.core.config import get_settings
from app.core.db import session_scope
from app.core.jobs import jobs
from app.core.money import format_money
from app.modules.agent import service as agent
from app.modules.conversations import outbox, service
from app.modules.conversations.service import TurnRequest
from app.modules.escalations import service as escalations
from app.modules.orders import service as orders
from app.modules.orders.schemas import ExpiredOrder, PaymentResult
from app.modules.payments import service as payments
from app.modules.payments.service import PaymentFailed

log = structlog.get_logger()


@jobs.task(name="run_agent_turn", queue="agent")
async def run_agent_turn(conversation_id: str) -> None:
    await service.run_turn(uuid.UUID(conversation_id))


# A v2 turn is safe to retry: it resumes from its stored steps (agent-phase-2.md 13.3).
@jobs.task(
    name="run_agent_turn_v2",
    queue="agent",
    retry=procrastinate.RetryStrategy(max_attempts=3, wait=5),
)
async def run_agent_turn_v2(conversation_id: str, shadow: bool = False) -> None:
    from app.modules.agent import service as agent

    await agent.run_turn(uuid.UUID(conversation_id), shadow=shadow)


async def request_turn(turn: TurnRequest) -> None:
    """Queue a reply. One queued turn per chat, run one at a time, after a short wait so a
    burst of messages gets a single reply."""
    conversation_id = str(turn.conversation_id)
    async with session_scope() as session:
        engine = await service.engine_for(session, turn.conversation_id)
    task = run_agent_turn_v2 if engine in ("v2", "draft") else run_agent_turn
    # If a turn is already queued, it will see this message too: nothing more to do.
    with suppress(AlreadyEnqueued):
        await task.configure(
            lock=f"conversation:{conversation_id}",
            queueing_lock=f"turn:{conversation_id}",
            schedule_in={"seconds": get_settings().turn_batch_seconds},
        ).defer_async(conversation_id=conversation_id)
    if engine == "shadow":  # v1 answers; v2 runs on the same messages, writing nothing
        with suppress(AlreadyEnqueued):
            await run_agent_turn_v2.configure(
                lock=f"shadow:{conversation_id}",
                queueing_lock=f"shadow-turn:{conversation_id}",
                schedule_in={"seconds": get_settings().turn_batch_seconds + 5},
            ).defer_async(conversation_id=conversation_id, shadow=True)


@jobs.task(name="send_outbound", queue="outbox")
async def send_outbound(conversation_id: str) -> None:
    await service.deliver_outbox(uuid.UUID(conversation_id))


async def schedule_delivery(conversation_id: uuid.UUID, at: datetime) -> None:
    """Deliver this chat's outbox at `at` (one waiting job per chat; sends never overlap)."""
    key = str(conversation_id)
    # A job already waiting for this chat will send everything due when it runs.
    with suppress(AlreadyEnqueued):
        await send_outbound.configure(
            lock=f"outbox:{key}", queueing_lock=f"outbox:{key}", schedule_at=at
        ).defer_async(conversation_id=key)


@jobs.periodic(cron="* * * * *")
@jobs.task(name="sweep_outbox", queue="outbox")
async def sweep_outbox(timestamp: int) -> None:
    """Every minute: deliver what's due (retries, missed jobs) and recover stuck sends."""
    now = datetime.now(UTC)
    for conversation_id in await outbox.sweep():
        await schedule_delivery(conversation_id, now)


@jobs.periodic(cron="*/5 * * * *")
@jobs.task(name="warn_closing_windows", queue="agent")
async def warn_closing_windows(timestamp: int) -> None:
    """Every 5 minutes: warn merchants whose unanswered customers' windows close soon."""
    warned = await service.warn_closing_windows()
    if warned:
        log.info("conversations.window_warnings", count=warned)


@jobs.periodic(cron="* * * * *")
@jobs.task(name="reconcile_unanswered", queue="agent")
async def reconcile_unanswered(timestamp: int) -> None:
    """Every minute: queue turns for chats left unanswered (e.g. a failed enqueue)."""
    async with session_scope() as session:
        conversation_ids = await service.unanswered_conversations(
            session, waiting_longer_than=timedelta(seconds=30), max_age=timedelta(hours=24)
        )
    stalled = await agent.stalled_turn_conversations(timedelta(minutes=2))
    for conversation_id in {*conversation_ids, *stalled}:
        await request_turn(TurnRequest(conversation_id))
    if conversation_ids or stalled:
        log.info("conversations.reconciled", count=len(conversation_ids), stalled=len(stalled))


async def inform_customer(
    conversation_id: uuid.UUID | None, note: str, *, event: dict[str, Any] | None = None
) -> None:
    """Have the agent tell the customer something, in their language, in their chat."""
    if conversation_id is None:
        return
    async with session_scope() as session:
        turn = await service.add_system_note(session, conversation_id, note, event=event)
    if turn is not None:
        await request_turn(turn)


async def after_payment(result: PaymentResult | PaymentFailed) -> None:
    """Tell the customer (and, if needed, the merchant) what a payment event means."""
    if isinstance(result, PaymentFailed):
        await _payment_failed(result)
        return

    await _order_settled(result.conversation_id)

    total = format_money(result.total_minor, result.currency)
    if result.outcome == "paid":
        await inform_customer(
            result.conversation_id,
            agent.prompt("v1.note.payment_received", number=result.number, total=total),
            event={"event": "payment_received", "order": f"#{result.number}"},
        )
    elif result.outcome == "paid_stock_short":
        await _ask_merchant(
            result,
            f"Order #{result.number} ({total}) was paid after its hold expired, and some items "
            "have sold out since. Please arrange a replacement or a refund.",
        )
        await inform_customer(
            result.conversation_id,
            agent.prompt("v1.note.paid_stock_short", number=result.number, total=total),
            event={"event": "paid_but_items_sold_out", "order": f"#{result.number}"},
        )
    elif result.outcome == "amount_mismatch":
        await _ask_merchant(
            result,
            f"The PayPal payment for order #{result.number} doesn't match the order total "
            f"({total}). Please check it in PayPal.",
        )


async def _payment_failed(result: PaymentFailed) -> None:
    """A payment was rejected or declined. Code, not the model, answers: this is about money.

    While the order may still get a new link, the customer is told how many tries are left and
    gets a button for the new link (after the cooldown). Otherwise the order is cancelled and its
    items released.
    """
    if result.conversation_id is None:
        return
    status = await payments.retry_status(result.order_id)
    if status.reason == "not_payable":
        return  # already paid, cancelled or expired: nothing to offer
    number = f"#{result.number}"
    async with session_scope() as session:
        language = await service.customer_language(session, result.conversation_id)
        if status.can_retry:
            await service.queue_message(
                session,
                conversation_id=result.conversation_id,
                text=agent.fixed_text(
                    "payment_declined",
                    language,
                    number=number,
                    attempts_left=status.attempts_left,
                    wait=status.wait_seconds,
                ),
                key=f"order:{result.order_id}:declined:{status.attempts_left}",
                details={
                    "order_id": str(result.order_id),
                    "kind": "payment_declined",
                    "language": language,
                },
                quick_replies=(
                    (
                        agent.fixed_text("payment_retry_button", language),
                        f"RETRY:{result.order_id}",
                    ),
                ),
            )
            return
        order = await orders.get_order(session, result.order_id)
        if order is None or order.merchant_id is None:
            return
        await orders.cancel_order(
            session,
            result.order_id,
            merchant_id=order.merchant_id,
            actor="system",
            reason=f"payment failed ({status.reason})",
        )
        await service.queue_message(
            session,
            conversation_id=result.conversation_id,
            text=agent.fixed_text("payment_gave_up", language, number=number),
            key=f"order:{result.order_id}:gave_up",
            details={
                "order_id": str(result.order_id),
                "kind": "payment_gave_up",
                "language": language,
            },
        )
        state = await service.load_state(session, result.conversation_id, lock=True)
        if state is not None and state.stage == "payment_pending":
            await service.set_stage(session, result.conversation_id, "browsing")


async def after_expiry(order: ExpiredOrder) -> None:
    await _order_settled(order.conversation_id)
    await inform_customer(
        order.conversation_id,
        agent.prompt("v1.note.hold_expired", number=order.number),
        event={"event": "hold_expired", "order": f"#{order.number}"},
    )


# The merchant moved an order on (Orders screen): what the customer is told. Code, not the model:
# it is a plain fact about their order. Other statuses (accepted, picked up) send nothing.
_STATUS_TEMPLATES = {
    ("ready", "pickup"): "order_ready_pickup",
    ("ready", "delivery"): "order_packed",
    ("ready", "local_delivery"): "order_packed",
    ("ready", "courier"): "order_packed",
    ("delivered", "delivery"): "order_delivered",
    ("delivered", "local_delivery"): "order_delivered",
    ("delivered", "courier"): "order_delivered",
    ("completed", "digital"): "order_sent",
}


async def after_status_change(order_id: uuid.UUID, merchant_id: uuid.UUID) -> None:
    """Tell the customer, in their chat, that the merchant marked their order ready / delivered.

    Each status is sent at most once per order (the outbox key), so an undo and redo, or a
    retried request, doesn't message the customer twice.
    """
    async with session_scope() as session:
        order = await orders.get_order(session, order_id, merchant_id)
        if order is None or order.conversation_id is None:
            return
        template = _STATUS_TEMPLATES.get((order.status, order.fulfilment_method or "pickup"))
        if template is None:
            return
        conversation_id = order.conversation_id
        language = await service.customer_language(session, conversation_id)
        await service.queue_message(
            session,
            conversation_id=conversation_id,
            text=agent.fixed_text(template, language, number=f"#{order.number}"),
            key=f"order:{order_id}:status:{order.status}",
            details={"order_id": str(order_id), "kind": template, "language": language},
        )
    await schedule_delivery(conversation_id, datetime.now(UTC))


async def _order_settled(conversation_id: uuid.UUID | None) -> None:
    """Paid or expired: the chat is back to browsing (unless the merchant has taken over)."""
    if conversation_id is None:
        return
    async with session_scope() as session:
        state = await service.load_state(session, conversation_id, lock=True)
        if state is not None and state.stage == "payment_pending":
            await service.set_stage(session, conversation_id, "browsing")


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
