"""The webhook inbox: store each delivery once, then process it in a job."""

import hashlib
import uuid
from datetime import UTC, datetime
from typing import Any

from sqlalchemy import select, update
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.webhooks.models import WebhookEvent


async def record_event(
    session: AsyncSession, *, source: str, body: bytes, payload: dict[str, Any]
) -> uuid.UUID | None:
    """Store a delivery. Returns its ID while it still needs processing, None once processed."""
    dedupe_key = hashlib.sha256(body).hexdigest()
    await session.execute(
        pg_insert(WebhookEvent)
        .values(source=source, dedupe_key=dedupe_key, payload=payload)
        .on_conflict_do_nothing(index_elements=[WebhookEvent.source, WebhookEvent.dedupe_key])
    )
    row = await session.execute(
        select(WebhookEvent.id, WebhookEvent.status).where(
            WebhookEvent.source == source, WebhookEvent.dedupe_key == dedupe_key
        )
    )
    event_id, status = row.one()
    return event_id if status == "pending" else None


async def claim_pending(session: AsyncSession, event_id: uuid.UUID) -> WebhookEvent | None:
    """Lock a pending event for processing; None if it's gone or already processed."""
    return await session.scalar(
        select(WebhookEvent)
        .where(WebhookEvent.id == event_id, WebhookEvent.status == "pending")
        .with_for_update(skip_locked=True)
    )


def mark_processed(event: WebhookEvent) -> None:
    event.status = "processed"
    event.processed_at = datetime.now(UTC)
    event.attempts += 1
    event.error = None


async def mark_processed_by_id(session: AsyncSession, event_id: uuid.UUID) -> None:
    await session.execute(
        update(WebhookEvent)
        .where(WebhookEvent.id == event_id)
        .values(
            status="processed",
            processed_at=datetime.now(UTC),
            attempts=WebhookEvent.attempts + 1,
            error=None,
        )
    )


async def record_failure(session: AsyncSession, event_id: uuid.UUID, error: str) -> None:
    await session.execute(
        update(WebhookEvent)
        .where(WebhookEvent.id == event_id)
        .values(attempts=WebhookEvent.attempts + 1, error=error[:1000])
    )
