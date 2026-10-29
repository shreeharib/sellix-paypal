"""Job entry points for the agent module."""

import structlog

from app.core.jobs import jobs
from app.modules.agent import service

log = structlog.get_logger()


@jobs.periodic(cron="*/15 * * * *")
@jobs.task(name="summarise_long_conversations", queue="maintenance")
async def summarise_long_conversations(timestamp: int) -> None:
    """Every 15 minutes: summarise the older part of long chats (never inside a turn)."""
    written = await service.summarise_long_conversations()
    if written:
        log.info("agent.summaries_written", count=written)
