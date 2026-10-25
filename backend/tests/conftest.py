"""Test settings: fixed values, so tests never use a developer's .env secrets or services."""

import asyncio
import os
import sys
from typing import Any

import pytest
from cryptography.fernet import Fernet

from app.core.runtime import new_event_loop

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
    # Only tests/sandbox talks to PayPal, with its own credentials (see that conftest).
    "PAYPAL_ENV": "sandbox",
    "PAYPAL_CLIENT_ID": "",
    "PAYPAL_CLIENT_SECRET": "",
    "PAYPAL_WEBHOOK_ID": "",
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
