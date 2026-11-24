"""Job entry points for the accounts module."""

import structlog

from app.core.db import session_scope
from app.core.jobs import jobs
from app.modules.accounts import service

log = structlog.get_logger()


@jobs.periodic(cron="*/10 * * * *")
@jobs.task(name="forget_rotated_refresh_tokens", queue="maintenance")
async def forget_rotated_refresh_tokens(timestamp: int) -> None:
    """Every 10 minutes: forget refresh-token copies whose 2-minute reuse grace has passed."""
    async with session_scope() as session:
        dropped = await service.forget_rotated_refresh_tokens(session)
    if dropped:
        log.info("accounts.refresh_copies_forgotten", count=dropped)
