"""PayPal webhooks: verified with PayPal, stored in the inbox, processed by a job.

If verification, storing or queueing fails we return an error, so PayPal delivers again.
"""

import json
from typing import Any

import structlog
from fastapi import APIRouter, HTTPException, Request

from app.core.config import get_settings
from app.core.db import session_scope
from app.modules.payments import service as payments
from app.webhooks import service
from app.webhooks.tasks import enqueue_paypal_event

router = APIRouter(prefix="/webhooks/paypal", tags=["webhooks"])
log = structlog.get_logger()


@router.post("")
async def receive_event(request: Request) -> dict[str, str]:
    body = await request.body()
    try:
        event: dict[str, Any] = json.loads(body)
    except json.JSONDecodeError as exc:
        raise HTTPException(status_code=400, detail="Body is not JSON") from exc

    try:
        genuine = await payments.verify_webhook(dict(request.headers), event)
    except payments.PayPalError as exc:
        raise HTTPException(status_code=503, detail="Couldn't verify with PayPal") from exc
    if not genuine:
        log.warning("paypal.webhook_unverified", event_type=event.get("event_type"))
        raise HTTPException(status_code=401, detail="Invalid signature")
    if get_settings().log_webhook_payloads:
        log.info("paypal.webhook_payload", payload=event)

    async with session_scope() as session:
        event_id = await service.record_event(session, source="paypal", body=body, payload=event)
    # Committed above: the job runs on its own connection and must see the event.
    if event_id is not None:
        await enqueue_paypal_event(event_id)
    return {"status": "received"}
