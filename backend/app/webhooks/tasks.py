"""Job entry points for processing stored webhook events."""

import uuid
from collections.abc import Awaitable, Callable, Mapping
from contextlib import suppress
from typing import Any

import procrastinate
import structlog
from procrastinate.exceptions import AlreadyEnqueued

from app.core.db import session_scope
from app.core.jobs import jobs
from app.modules.channels import service as channels
from app.modules.conversations import service as conversations
from app.modules.orders.schemas import PaymentResult
from app.modules.payments import service as payments
from app.webhooks import service

log = structlog.get_logger()
_RETRY = procrastinate.RetryStrategy(max_attempts=5, exponential_wait=2)


@jobs.task(name="process_meta_event", queue="webhooks", retry=_RETRY)
async def process_meta_event(event_id: str) -> None:
    turns: list[conversations.TurnRequest] = []
    try:
        async with session_scope() as session:
            event = await service.claim_pending(session, uuid.UUID(event_id))
            if event is None:
                return
            for message in channels.parse_webhook(event.payload):
                turn = await conversations.handle_incoming(session, message)
                if turn is not None:
                    turns.append(turn)
            service.mark_processed(event)
    except Exception as exc:
        async with session_scope() as session:
            await service.record_failure(session, uuid.UUID(event_id), repr(exc))
        log.exception("webhooks.meta_event_failed", event_id=event_id)
        raise

    # Only after the messages are committed, so the turn can see them.
    for turn in turns:
        await conversations.request_turn(turn)


type PaymentEventHandler = Callable[
    [Mapping[str, Any]], Awaitable[PaymentResult | payments.PaymentFailed | None]
]


async def _apply_payment_event(event_id: str, handle: PaymentEventHandler, source: str) -> None:
    async with session_scope() as session:
        event = await service.claim_pending(session, uuid.UUID(event_id))
        payload = event.payload if event is not None else None
    if payload is None:
        return
    try:
        # May call PayPal, so it runs outside any transaction; applying it twice is harmless.
        result = await handle(payload)
    except Exception as exc:
        async with session_scope() as session:
            await service.record_failure(session, uuid.UUID(event_id), repr(exc))
        log.exception("webhooks.payment_event_failed", source=source, event_id=event_id)
        raise
    async with session_scope() as session:
        await service.mark_processed_by_id(session, uuid.UUID(event_id))
    if result is not None:
        await conversations.after_payment(result)


@jobs.task(name="process_paypal_event", queue="webhooks", retry=_RETRY)
async def process_paypal_event(event_id: str) -> None:
    await _apply_payment_event(event_id, payments.handle_webhook, "paypal")


@jobs.task(name="process_simulator_event", queue="webhooks", retry=_RETRY)
async def process_simulator_event(event_id: str) -> None:
    await _apply_payment_event(event_id, payments.handle_simulator_event, "simulator")


async def enqueue_meta_event(event_id: uuid.UUID) -> None:
    # A retry of a delivery whose job is already waiting raises AlreadyEnqueued: nothing to do.
    with suppress(AlreadyEnqueued):
        await process_meta_event.configure(queueing_lock=f"meta_event:{event_id}").defer_async(
            event_id=str(event_id)
        )


async def enqueue_simulator_event(event_id: uuid.UUID) -> None:
    with suppress(AlreadyEnqueued):
        await process_simulator_event.configure(
            queueing_lock=f"simulator_event:{event_id}", lock=f"simulator_event:{event_id}"
        ).defer_async(event_id=str(event_id))


async def enqueue_paypal_event(event_id: uuid.UUID) -> None:
    with suppress(AlreadyEnqueued):
        await process_paypal_event.configure(
            queueing_lock=f"paypal_event:{event_id}", lock=f"paypal_event:{event_id}"
        ).defer_async(event_id=str(event_id))
