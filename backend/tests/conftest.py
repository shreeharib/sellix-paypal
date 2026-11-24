"""Test settings: fixed values, so tests never use a developer's .env secrets or services."""

import asyncio
import os
import sys
from collections.abc import Iterator
from typing import TYPE_CHECKING, Any

import pytest
from cryptography.fernet import Fernet

from app.core.runtime import new_event_loop

if TYPE_CHECKING:
    from tests.integration.fake_razorpay import FakeRazorpay

TEST_ENV = {
    "APP_ENV": "test",
    "PUBLIC_BASE_URL": "https://sellix.test",
    "DATABASE_URL": os.environ.get(
        "TEST_DATABASE_URL", "postgresql://postgres:postgres@localhost:54322/sellix_test"
    ),
    "RUN_WORKER_IN_PROCESS": "false",
    "TOKEN_ENCRYPTION_KEYS": Fernet.generate_key().decode(),
    "OAUTH_STATE_SECRET": "test-oauth-state-secret",
    "SESSION_SIGNING_KEY": "test-session-signing-key-with-32-plus-characters",
    "APP_REDIRECT_URIS": "sellix://auth/callback,https://app.sellix.test/auth/callback",
    "META_APP_SECRET": "test-meta-app-secret",
    "INSTAGRAM_APP_ID": "test-instagram-app-id",
    "INSTAGRAM_APP_SECRET": "test-instagram-app-secret",
    "META_VERIFY_TOKEN": "test-verify-token",
    "LOG_WEBHOOK_PAYLOADS": "false",
    "LLM_BASE_URL": "https://llm.test/v1",
    "LLM_API_KEY": "test-llm-key",
    "LLM_MODEL": "test-model",
    "LLM_REASONING_EFFORT": "",
    "TURN_BATCH_SECONDS": "3",
    # Turns route by the rules, so scripted conversations never make a real router call; the
    # router's own tests switch it to "model" with a fake model.
    "AGENT_PLAYBOOK_ROUTER": "rules",
    # Razorpay: tests use a fake Razorpay (tests/support/fake_razorpay.py); no shared keys, so a
    # shop pays only through the account it connects. The simulator stays off.
    "PAYMENT_PROVIDER": "razorpay",
    "RAZORPAY_KEY_ID": "",
    "RAZORPAY_KEY_SECRET": "",
    "RAZORPAY_WEBHOOK_SECRET": "",
    "RAZORPAY_API_BASE": "https://api.razorpay.test",
}
os.environ.update(TEST_ENV)


@pytest.fixture
def anyio_backend() -> tuple[str, dict[str, Any]]:
    # psycopg's async mode needs a selector event loop on Windows.
    options: dict[str, Any] = {"loop_factory": new_event_loop} if sys.platform == "win32" else {}
    return ("asyncio", options)


@pytest.fixture(scope="session", autouse=True)
def _event_loop_for_sync_clients() -> None:
    if sys.platform == "win32":
        asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())


# Razorpay: every test that pays goes through the fake (tests/integration/fake_razorpay.py).
RAZORPAY_KEY_ID = "rzp_test_SellixShop0001"
RAZORPAY_KEY_SECRET = "TestSecretAbc123XYZ"


@pytest.fixture
def fake_razorpay(monkeypatch: pytest.MonkeyPatch) -> Iterator["FakeRazorpay"]:
    """Razorpay's API, faked; it knows the test shop's keys. No waits between retries."""
    from app.modules.payments import razorpay
    from tests.integration.fake_razorpay import FakeRazorpay

    fake = FakeRazorpay()
    fake.add_account(RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET)
    monkeypatch.setattr(razorpay, "_RETRY_DELAYS", (0.0, 0.0))
    razorpay.use_transport(fake.transport())
    yield fake
    razorpay.use_transport(None)
