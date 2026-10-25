"""Database engine and sessions: SQLAlchemy 2 (async) on psycopg 3.

The schema is defined by the SQL migrations in supabase/migrations; models only map it.
Use a direct or session-pooler connection string: the job queue relies on LISTEN/NOTIFY,
which transaction-mode poolers don't support.
"""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase

from app.core.config import get_settings

_POSTGRES_SCHEMES = ("postgres", "postgresql", "postgresql+psycopg")


class Base(DeclarativeBase):
    pass


_engine: AsyncEngine | None = None
_sessions: async_sessionmaker[AsyncSession] | None = None


def libpq_url(database_url: str) -> str:
    """The plain `postgresql://` form that psycopg and the job queue expect."""
    scheme, separator, rest = database_url.partition("://")
    if separator and scheme in _POSTGRES_SCHEMES:
        return f"postgresql://{rest}"
    return database_url


def get_engine() -> AsyncEngine:
    global _engine
    if _engine is None:
        url = libpq_url(get_settings().database_url)
        _engine = create_async_engine(
            url.replace("postgresql://", "postgresql+psycopg://", 1),
            pool_pre_ping=True,
            # No server-side prepared statements, so a pooler in front of Postgres is safe.
            connect_args={"prepare_threshold": None},
        )
    return _engine


def _session_factory() -> async_sessionmaker[AsyncSession]:
    global _sessions
    if _sessions is None:
        _sessions = async_sessionmaker(get_engine(), expire_on_commit=False)
    return _sessions


@asynccontextmanager
async def session_scope() -> AsyncIterator[AsyncSession]:
    """One transaction: commits on success, rolls back on error."""
    async with _session_factory()() as session, session.begin():
        yield session


async def get_session() -> AsyncIterator[AsyncSession]:
    """FastAPI dependency: one transaction per request."""
    async with session_scope() as session:
        yield session


async def dispose_engine() -> None:
    global _engine, _sessions
    if _engine is not None:
        await _engine.dispose()
    _engine = None
    _sessions = None
