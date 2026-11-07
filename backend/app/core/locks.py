"""Cross-process locks, from Postgres advisory locks.

An advisory lock belongs to a database connection, so it is released by `unlock`, or by Postgres
itself if the process dies. That is why this needs a direct or session-pooler connection, the
same requirement as the job queue (see db.py).
"""

import asyncio
import time
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from sqlalchemy import text

from app.core.db import get_engine

POLL_SECONDS = 0.5


@asynccontextmanager
async def advisory_lock(scope: str, key: str, *, wait_seconds: float = 0.0) -> AsyncIterator[bool]:
    """Hold the lock (`scope`, `key`) while the block runs. Yields False if it wasn't free in time.

    Waits up to `wait_seconds` for the holder to finish, polling. The lock lives on its own
    connection for the whole block, so the block's own database sessions are unaffected.
    """
    params = {"scope": scope, "key": key}
    async with get_engine().connect() as connection:
        connection = await connection.execution_options(isolation_level="AUTOCOMMIT")
        deadline = time.monotonic() + wait_seconds
        held = False
        while True:
            held = bool(
                await connection.scalar(
                    text("select pg_try_advisory_lock(hashtext(:scope), hashtext(:key))"), params
                )
            )
            if held or time.monotonic() >= deadline:
                break
            await asyncio.sleep(POLL_SECONDS)
        try:
            yield held
        finally:
            if held:
                await connection.execute(
                    text("select pg_advisory_unlock(hashtext(:scope), hashtext(:key))"), params
                )
