"""Job entry points for the payments module."""

import structlog

from app.core.jobs import jobs
from app.modules.payments import service

log = structlog.get_logger()


@jobs.periodic(cron="*/5 * * * *")
@jobs.task(name="reconcile_refunds", queue="payments")
async def reconcile_refunds(timestamp: int) -> None:
    """Every 5 minutes: settle refunds whose PayPal answer never arrived."""
    completed = await service.reconcile_refunds()
    if completed:
        log.info("payments.refunds_reconciled", count=completed)
