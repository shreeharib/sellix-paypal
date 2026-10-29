"""Public interface of the insights module: what customers wanted and couldn't get."""

import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.insights.models import MissedDemand


async def log_missed_demand(
    session: AsyncSession,
    *,
    merchant_id: uuid.UUID,
    conversation_id: uuid.UUID | None,
    wanted: str,
    reason: str,
    quantity: int = 1,
) -> None:
    session.add(
        MissedDemand(
            merchant_id=merchant_id,
            conversation_id=conversation_id,
            requested_item_name=wanted.strip()[:150],
            quantity_requested=quantity,
            reason=reason,
        )
    )
