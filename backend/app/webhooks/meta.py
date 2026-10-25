"""Meta webhooks (Instagram and WhatsApp).

GET is the one-time handshake when the webhook URL is registered in the Meta app dashboard.
POST delivers messages, story replies, echoes and so on: we verify the signature, store the
raw event, queue a job to process it, and answer at once. If storing or queueing fails we
return an error, so Meta delivers the event again.
"""

import hashlib
import hmac
import json
from typing import Annotated, Any

import structlog
from fastapi import APIRouter, Header, HTTPException, Query, Request
from fastapi.responses import PlainTextResponse

from app.core.config import get_settings
from app.core.db import session_scope
from app.webhooks import service
from app.webhooks.tasks import enqueue_meta_event

router = APIRouter(prefix="/webhooks/meta", tags=["webhooks"])
log = structlog.get_logger()


@router.get("", response_class=PlainTextResponse)
async def verify_subscription(
    mode: Annotated[str, Query(alias="hub.mode")] = "",
    verify_token: Annotated[str, Query(alias="hub.verify_token")] = "",
    challenge: Annotated[str, Query(alias="hub.challenge")] = "",
) -> str:
    expected = get_settings().meta_verify_token
    if mode == "subscribe" and expected and hmac.compare_digest(verify_token, expected):
        log.info("meta.webhook_verified")
        return challenge
    raise HTTPException(status_code=403, detail="Verification failed")


@router.post("")
async def receive_event(
    request: Request,
    signature: Annotated[str | None, Header(alias="X-Hub-Signature-256")] = None,
) -> dict[str, str]:
    settings = get_settings()
    body = await request.body()
    if not is_valid_signature(
        body, signature, settings.meta_app_secret, settings.instagram_app_secret
    ):
        log.warning("meta.webhook_bad_signature", has_signature=signature is not None)
        raise HTTPException(status_code=401, detail="Invalid signature")

    try:
        payload: dict[str, Any] = json.loads(body)
    except json.JSONDecodeError as exc:
        raise HTTPException(status_code=400, detail="Body is not JSON") from exc
    if settings.log_webhook_payloads:
        log.info("meta.webhook_payload", payload=payload)

    async with session_scope() as session:
        event_id = await service.record_event(session, source="meta", body=body, payload=payload)
    # Committed above: the job runs on its own connection and must see the event.
    if event_id is not None:
        await enqueue_meta_event(event_id)
    return {"status": "received"}


def is_valid_signature(body: bytes, signature: str | None, *secrets: str) -> bool:
    """Meta sends `sha256=<hex HMAC-SHA256 of the raw body>`, keyed with an app secret."""
    if not signature or not signature.startswith("sha256="):
        return False
    received = signature.removeprefix("sha256=")
    return any(
        hmac.compare_digest(received, hmac.new(secret.encode(), body, hashlib.sha256).hexdigest())
        for secret in secrets
        if secret
    )
