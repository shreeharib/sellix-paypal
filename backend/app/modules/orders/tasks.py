"""Job entry points for the orders module."""

import structlog

from app.core.db import session_scope
from app.core.jobs import jobs
from app.modules.conversations.tasks import after_expiry
from app.modules.orders import service

log = structlog.get_logger()


@jobs.periodic(cron="* * * * *")
@jobs.task(name="expire_unpaid_orders", queue="orders")
async def expire_unpaid_orders(timestamp: int) -> None:
    """Every minute: give back the stock of orders that weren't paid in time."""
    async with session_scope() as session:
        expired = await service.expire_due(session)
    for order in expired:
        await after_expiry(order)
    if expired:
        log.info("orders.expired", count=len(expired))
