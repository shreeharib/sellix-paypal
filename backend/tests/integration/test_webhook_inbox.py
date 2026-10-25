import hashlib
import hmac
import json

import httpx2
import pytest
from procrastinate.testing import InMemoryConnector
from sqlalchemy import func, select

from app.core.db import session_scope
from app.main import create_app
from app.webhooks.models import WebhookEvent

pytestmark = pytest.mark.anyio

BODY = json.dumps(
    {
        "object": "instagram",
        "entry": [
            {
                "id": "17841400000000001",
                "time": 1,
                "messaging": [
                    {
                        "sender": {"id": "7000000000000002"},
                        "recipient": {"id": "17841400000000001"},
                        "message": {"mid": "m-1", "text": "hi"},
                    }
                ],
            }
        ],
    }
).encode()


def signature(body: bytes) -> str:
    return "sha256=" + hmac.new(b"test-meta-app-secret", body, hashlib.sha256).hexdigest()


async def post_event(body: bytes) -> httpx2.Response:
    transport = httpx2.ASGITransport(app=create_app())
    async with httpx2.AsyncClient(transport=transport, base_url="http://test") as client:
        return await client.post(
            "/webhooks/meta", content=body, headers={"X-Hub-Signature-256": signature(body)}
        )


async def test_event_is_stored_once_and_queued(db: None, deferred_jobs: InMemoryConnector) -> None:
    first = await post_event(BODY)
    retry = await post_event(BODY)  # Meta retries identical payloads

    assert first.status_code == 200
    assert retry.status_code == 200
    async with session_scope() as session:
        assert await session.scalar(select(func.count()).select_from(WebhookEvent)) == 1
    [job] = deferred_jobs.jobs.values()
    assert job["task_name"] == "process_meta_event"


async def test_processed_event_is_not_queued_again(
    db: None, deferred_jobs: InMemoryConnector
) -> None:
    await post_event(BODY)
    async with session_scope() as session:
        event = await session.scalar(select(WebhookEvent))
        assert event is not None
        event.status = "processed"
    deferred_jobs.reset()

    await post_event(BODY)

    assert deferred_jobs.jobs == {}
