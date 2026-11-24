"""Razorpay webhooks: signature checked, stored in the inbox, processed by a job.

Each shop's webhook goes to /webhooks/razorpay/<its token>, so the delivery says whose secret
checks it; /webhooks/razorpay is the shared account's. Razorpay wants a 2xx within 5 seconds and
retries for 24 hours otherwise, so this only checks, stores and queues. If storing or queueing
fails we return an error, so Razorpay delivers again.
"""

import json
from typing import Any

import structlog
from fastapi import APIRouter, HTTPException, Request

from app.core.config import get_settings
from app.core.db import session_scope
from app.modules.payments import service as payments
from app.webhooks import service
from app.webhooks.tasks import enqueue_razorpay_event

router = APIRouter(prefix="/webhooks/razorpay", tags=["webhooks"])
log = structlog.get_logger()

SOURCE = "razorpay"


@router.post("")
async def receive_shared(request: Request) -> dict[str, str]:
    return await _receive(request, None)


@router.post("/{token}")
async def receive_for_shop(token: str, request: Request) -> dict[str, str]:
    return await _receive(request, token)


async def _receive(request: Request, token: str | None) -> dict[str, str]:
    body = await request.body()
    signature = request.headers.get(payments.RAZORPAY_SIGNATURE_HEADER, "")
    sender = await payments.verify_razorpay_webhook(token, body, signature)
    if sender is None:
        log.warning("razorpay.webhook_unverified", shop_address=token is not None)
        raise HTTPException(status_code=401, detail="Invalid signature")
    try:
        event: Any = json.loads(body)
    except json.JSONDecodeError as exc:
        raise HTTPException(status_code=400, detail="Body is not JSON") from exc
    if not isinstance(event, dict):
        raise HTTPException(status_code=400, detail="Body is not a JSON object")
    if get_settings().log_webhook_payloads:
        log.info("razorpay.webhook_payload", payload=event)

    # Razorpay names each event; a redelivery carries the same id (the body may differ).
    event_header = request.headers.get(payments.RAZORPAY_EVENT_ID_HEADER, "").strip()
    async with session_scope() as session:
        event_id = await service.record_event(
            session,
            source=SOURCE,
            body=body,
            payload=payments.stored_event(event, sender),
            # Per sending account, so one shop's event ids can't shadow another's.
            dedupe_key=f"event:{sender.tag}:{event_header}" if event_header else None,
        )
    # Committed above: the job runs on its own connection and must see the event.
    if event_id is not None:
        await enqueue_razorpay_event(event_id)
    return {"status": "received"}
