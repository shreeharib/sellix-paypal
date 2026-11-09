"""Webhooks from the payment simulator (payments/simulator.py): signed, stored, applied by a job.

Same road as PayPal's: the delivery goes into the inbox first and a job applies it, so a crash
between the two loses nothing and a repeated delivery is harmless.
"""

import json
from typing import Any

from fastapi import APIRouter, HTTPException, Request

from app.core.db import session_scope
from app.modules.payments import service as payments
from app.webhooks import service
from app.webhooks.tasks import enqueue_simulator_event

router = APIRouter(prefix="/webhooks/simulator", tags=["webhooks"])


async def deliver(body: bytes, signature: str) -> None:
    """Accept one delivery: check the signature, store it, queue the job that applies it."""
    if not payments.simulator_enabled():
        raise HTTPException(status_code=404, detail="Not found")
    if not payments.verify_simulator_webhook(body, signature):
        raise HTTPException(status_code=401, detail="Invalid signature")
    try:
        event: dict[str, Any] = json.loads(body)
    except json.JSONDecodeError as exc:
        raise HTTPException(status_code=400, detail="Body is not JSON") from exc
    async with session_scope() as session:
        event_id = await service.record_event(
            session, source=payments.SIMULATOR_SOURCE, body=body, payload=event
        )
    # Committed above: the job runs on its own connection and must see the event.
    if event_id is not None:
        await enqueue_simulator_event(event_id)


@router.post("")
async def receive_event(request: Request) -> dict[str, str]:
    await deliver(
        await request.body(), request.headers.get(payments.SIMULATOR_SIGNATURE_HEADER, "")
    )
    return {"status": "received"}
