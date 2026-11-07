"""Database tests: a fresh database built from the real migrations in supabase/migrations.

Locally they're skipped when Postgres isn't running (start it with the command in
backend/README.md). CI sets REQUIRE_DB_TESTS=1, which turns the skip into a failure.
"""

import os
from collections.abc import AsyncIterator, Iterator
from pathlib import Path

import psycopg
import pytest
from procrastinate.testing import InMemoryConnector
from psycopg import sql

from app.core import crypto
from app.core.config import BACKEND_DIR, get_settings
from app.core.db import dispose_engine, libpq_url, session_scope
from app.core.jobs import jobs
from app.modules.agent import llm
from app.modules.channels import service as channels
from app.modules.channels.models import ChannelConnection
from app.modules.conversations import outbox
from app.modules.inventory import service as inventory
from app.modules.inventory.schemas import OpeningStockLine
from app.modules.merchants import service as merchants
from app.modules.merchants.models import Merchant
from app.modules.shop_profile import service as shop_profile
from app.modules.shop_profile.schemas import OnboardingAnswers
from tests.integration.factories import SHOP_ACCOUNT_ID, Instagram, ScriptedModel

MIGRATIONS_DIR = BACKEND_DIR.parent / "supabase" / "migrations"


@pytest.fixture(scope="session")
def database_url() -> str:
    url = libpq_url(get_settings().database_url)
    database_name = url.rsplit("/", 1)[-1]
    admin_url = url.rsplit("/", 1)[0] + "/postgres"
    try:
        with psycopg.connect(admin_url, autocommit=True, connect_timeout=3) as admin:
            admin.execute(
                sql.SQL("drop database if exists {} with (force)").format(
                    sql.Identifier(database_name)
                )
            )
            admin.execute(sql.SQL("create database {}").format(sql.Identifier(database_name)))
    except psycopg.OperationalError as exc:
        if os.environ.get("REQUIRE_DB_TESTS") == "1":
            raise
        pytest.skip(f"Postgres isn't reachable for database tests: {exc}")

    with psycopg.connect(url, autocommit=True) as connection:
        for migration in sorted(MIGRATIONS_DIR.glob("*.sql")):
            connection.execute(Path(migration).read_text(encoding="utf-8").encode())
    return url


@pytest.fixture
async def db(database_url: str) -> AsyncIterator[None]:
    async with await psycopg.AsyncConnection.connect(database_url, autocommit=True) as connection:
        await connection.execute("truncate merchants, webhook_events, users cascade")
    yield
    await dispose_engine()


@pytest.fixture
def deferred_jobs() -> Iterator[InMemoryConnector]:
    """Captures deferred jobs instead of writing them to the queue."""
    connector = InMemoryConnector()
    with jobs.replace_connector(connector):
        yield connector


@pytest.fixture
async def shop(db: None) -> ChannelConnection:
    """A merchant with a connected Instagram account."""
    async with session_scope() as session:
        merchant = Merchant(name="Sweet Crumbs")
        session.add(merchant)
        await session.flush()
        connection = ChannelConnection(
            merchant_id=merchant.id,
            channel="instagram",
            external_account_id=SHOP_ACCOUNT_ID,
            username="sweetcrumbs",
            access_token_encrypted=crypto.encrypt("ig-token"),
            scopes=["instagram_business_basic", "instagram_business_manage_messages"],
        )
        session.add(connection)
        await session.flush()
    return connection


@pytest.fixture
async def v2_shop(shop: ChannelConnection) -> ChannelConnection:
    """The shop on the v2 engine, with chocolate cookies (₹60, 10 left) and UPI payments."""
    async with session_scope() as session:
        merchant = await merchants.get_merchant(session, shop.merchant_id)
        await merchants.set_agent_engine(session, shop.merchant_id, "v2")
        await inventory.set_opening_stock(
            session,
            merchant_id=shop.merchant_id,
            business_date=merchants.business_date(merchant),
            lines=[OpeningStockLine("Scoop cookie", "Chocolate", 6000, 10)],
        )
        await shop_profile.save_onboarding(
            session,
            shop.merchant_id,
            shop_name=merchant.name,
            answers=OnboardingAnswers(upi_id="sweetcrumbs@okhdfcbank"),
        )
    return shop


@pytest.fixture
def instagram(monkeypatch: pytest.MonkeyPatch) -> Instagram:
    fake = Instagram()
    monkeypatch.setattr(channels, "send_text", fake)
    monkeypatch.setattr(channels, "send_attachment", fake.attachment)
    monkeypatch.setattr(outbox, "PACING_SECONDS", 0)
    return fake


@pytest.fixture
def model(monkeypatch: pytest.MonkeyPatch) -> ScriptedModel:
    scripted = ScriptedModel()
    monkeypatch.setattr(llm, "generate", scripted)
    return scripted
