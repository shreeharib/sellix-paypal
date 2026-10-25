"""Job entry points for processing stored webhook events."""

import uuid
from contextlib import suppress

import procrastinate
import structlog
from procrastinate.exceptions import AlreadyEnqueued

from app.core.db import session_scope
from app.core.jobs import jobs
from app.modules.channels import service as channels
from app.modules.conversations import service as conversations
from app.modules.conversations.tasks import after_payment, request_turn
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
        await request_turn(turn)


@jobs.task(name="process_paypal_event", queue="webhooks", retry=_RETRY)
async def process_paypal_event(event_id: str) -> None:
    async with session_scope() as session:
        event = await service.claim_pending(session, uuid.UUID(event_id))
        payload = event.payload if event is not None else None
    if payload is None:
        return
    try:
        # Calls PayPal, so it runs outside any transaction; applying it twice is harmless.
        result = await payments.handle_webhook(payload)
    except Exception as exc:
        async with session_scope() as session:
            await service.record_failure(session, uuid.UUID(event_id), repr(exc))
        log.exception("webhooks.paypal_event_failed", event_id=event_id)
        raise
    async with session_scope() as session:
        await service.mark_processed_by_id(session, uuid.UUID(event_id))
    if result is not None:
        await after_payment(result)


async def enqueue_meta_event(event_id: uuid.UUID) -> None:
    # A retry of a delivery whose job is already waiting raises AlreadyEnqueued: nothing to do.
    with suppress(AlreadyEnqueued):
        await process_meta_event.configure(queueing_lock=f"meta_event:{event_id}").defer_async(
            event_id=str(event_id)
        )


async def enqueue_paypal_event(event_id: uuid.UUID) -> None:
    with suppress(AlreadyEnqueued):
        await process_paypal_event.configure(
            queueing_lock=f"paypal_event:{event_id}", lock=f"paypal_event:{event_id}"
        ).defer_async(event_id=str(event_id))
