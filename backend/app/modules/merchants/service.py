"""Public interface of the merchants module."""

import uuid
from datetime import date, datetime
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from sqlalchemy import Select, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.merchants.models import Merchant

__all__ = [
    "Merchant",
    "MerchantNotFound",
    "business_date",
    "create_merchant",
    "enabled_merchant_ids_select",
    "find_merchant",
    "get_merchant",
    "set_agent_enabled",
    "update_settings",
]


class MerchantNotFound(LookupError):
    pass


async def create_merchant(
    session: AsyncSession, *, name: str, timezone: str = "Asia/Kolkata"
) -> Merchant:
    try:
        ZoneInfo(timezone)
    except ZoneInfoNotFoundError as exc:
        raise ValueError(f"Unknown time zone: {timezone}") from exc
    merchant = Merchant(name=name.strip(), timezone=timezone)
    session.add(merchant)
    await session.flush()
    return merchant


async def find_merchant(session: AsyncSession, merchant_id: uuid.UUID) -> Merchant | None:
    return await session.get(Merchant, merchant_id)


async def get_merchant(session: AsyncSession, merchant_id: uuid.UUID) -> Merchant:
    merchant = await find_merchant(session, merchant_id)
    if merchant is None:
        raise MerchantNotFound(f"No merchant {merchant_id}")
    return merchant


def enabled_merchant_ids_select() -> Select[uuid.UUID]:
    """Subquery selecting IDs of merchants whose AI agent is enabled."""
    return select(Merchant.id).where(Merchant.agent_enabled)


async def set_agent_enabled(session: AsyncSession, merchant_id: uuid.UUID, enabled: bool) -> None:
    merchant = await get_merchant(session, merchant_id)
    merchant.agent_enabled = enabled


def business_date(merchant: Merchant, at: datetime | None = None) -> date:
    """The merchant's local calendar date (closing-time cut-off comes with the stock ledger)."""
    moment = at or datetime.now(tz=ZoneInfo("UTC"))
    return moment.astimezone(ZoneInfo(merchant.timezone)).date()


async def update_settings(
    session: AsyncSession,
    merchant_id: uuid.UUID,
    *,
    name: str | None = None,
    timezone: str | None = None,
    agent_enabled: bool | None = None,
) -> Merchant:
    merchant = await get_merchant(session, merchant_id)
    if name is not None:
        if not name.strip():
            raise ValueError("The shop name can't be empty")
        merchant.name = name.strip()
    if timezone is not None:
        try:
            ZoneInfo(timezone)
        except ZoneInfoNotFoundError as exc:
            raise ValueError(f"Unknown time zone: {timezone}") from exc
        merchant.timezone = timezone
    if agent_enabled is not None:
        merchant.agent_enabled = agent_enabled
    return merchant
