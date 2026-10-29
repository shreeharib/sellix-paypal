"""Background jobs, stored in Postgres (procrastinate).

Tasks live in each module's tasks.py. Defer a job only after the transaction that created its
data has committed: the queue uses its own database connections.
"""

import procrastinate

from app.core.config import get_settings
from app.core.db import libpq_url

SHUTDOWN_GRACE_SECONDS = 20

TASK_MODULES = [
    "app.webhooks.tasks",
    "app.modules.conversations.tasks",
    "app.modules.channels.tasks",
    "app.modules.orders.tasks",
    "app.modules.payments.tasks",
]

jobs = procrastinate.App(
    connector=procrastinate.PsycopgConnector(
        conninfo=libpq_url(get_settings().database_url),
        kwargs={"prepare_threshold": None},
    ),
    import_paths=TASK_MODULES,
)


async def run_worker(*, install_signal_handlers: bool) -> None:
    """Process jobs until cancelled. The app must already be open."""
    await jobs.run_worker_async(
        concurrency=4,
        delete_jobs="successful",
        install_signal_handlers=install_signal_handlers,
        # On shutdown, give running jobs this long to finish, so deploys never hang.
        shutdown_graceful_timeout=SHUTDOWN_GRACE_SECONDS,
    )
