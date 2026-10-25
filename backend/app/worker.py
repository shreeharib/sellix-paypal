"""Standalone job worker: `uv run python -m app.worker`.

Deployments that run the worker as its own process set RUN_WORKER_IN_PROCESS=false on the API.
"""

import asyncio
import sys

from app.core.config import get_settings
from app.core.db import dispose_engine
from app.core.jobs import jobs, run_worker
from app.core.logging import configure_logging
from app.core.runtime import new_event_loop


async def main() -> None:
    settings = get_settings()
    configure_logging(settings.log_level, json_logs=settings.app_env != "local")
    try:
        async with jobs.open_async():
            # Signal handlers need a Unix event loop.
            await run_worker(install_signal_handlers=sys.platform != "win32")
    finally:
        await dispose_engine()


if __name__ == "__main__":
    asyncio.run(main(), loop_factory=new_event_loop)
