"""Job entry points for the payments module."""

import structlog

from app.core.jobs import jobs
from app.modules.conversations import service as conversations
from app.modules.payments import service

log = structlog.get_logger()


@jobs.periodic(cron="* * * * *")
@jobs.task(name="settle_open_payments", queue="payments")
async def settle_open_payments(timestamp: int) -> None:
    """Every minute: capture payments the buyer approved when no return page or webhook told us.

    The customer gets their confirmation in chat from here, whatever device the buyer paid on.
    """
    for result in await service.settle_open_payments():
        await conversations.after_payment(result)
        log.info("payments.settled_by_poll", order_id=str(result.order_id))


@jobs.periodic(cron="*/5 * * * *")
@jobs.task(name="reconcile_refunds", queue="payments")
async def reconcile_refunds(timestamp: int) -> None:
    """Every 5 minutes: settle refunds whose PayPal answer never arrived."""
    completed = await service.reconcile_refunds()
    if completed:
        log.info("payments.refunds_reconciled", count=completed)
