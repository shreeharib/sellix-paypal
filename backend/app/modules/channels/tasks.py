"""Job entry points for the channels module."""

from datetime import timedelta

import structlog

from app.core.db import session_scope
from app.core.jobs import jobs
from app.modules.channels import service

log = structlog.get_logger()


@jobs.periodic(cron="0 3 * * *")
@jobs.task(name="refresh_channel_tokens", queue="maintenance")
async def refresh_channel_tokens(timestamp: int) -> None:
    """Daily: extend Instagram tokens that expire within 15 days (they last about 60)."""
    async with session_scope() as session:
        refreshed = await service.refresh_expiring_tokens(session, within=timedelta(days=15))
    log.info("channels.tokens_refreshed", count=refreshed)
