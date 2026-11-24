"""Job entry points for the orders module."""

import structlog

from app.core import locks
from app.core.db import session_scope
from app.core.jobs import jobs
from app.modules.conversations import service as conversations
from app.modules.orders import service

log = structlog.get_logger()


@jobs.periodic(cron="* * * * *")
@jobs.task(name="expire_unpaid_orders", queue="orders")
async def expire_unpaid_orders(timestamp: int) -> None:
    """Every minute: give back the stock of orders that weren't paid in time.

    One copy at a time: after the laptop slept, every missed minute ran at once and the copies
    deadlocked on the same stock rows. A copy that finds another running skips; the next
    minute's run picks up anything left.
    """
    async with locks.advisory_lock("orders", "expire_unpaid_orders") as held:
        if not held:
            log.info("orders.expire_skipped", reason="another copy is running")
            return
        async with session_scope() as session:
            expired = await service.expire_due(session)
    for order in expired:
        await conversations.after_expiry(order)
    if expired:
        log.info("orders.expired", count=len(expired))
