"""Public interface of the merchants module."""

import uuid
from datetime import date, datetime
from typing import Literal
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.merchants.models import Merchant
from app.modules.merchants.schemas import MerchantInfo

__all__ = [
    "MerchantInfo",
    "MerchantNotFound",
    "business_date",
    "create_merchant",
    "find_merchant",
    "get_merchant",
    "list_enabled_merchant_ids",
    "set_agent_enabled",
    "update_settings",
]


class MerchantNotFound(LookupError):
    pass


async def create_merchant(
    session: AsyncSession, *, name: str, timezone: str = "Asia/Kolkata"
) -> MerchantInfo:
    try:
        ZoneInfo(timezone)
    except ZoneInfoNotFoundError as exc:
        raise ValueError(f"Unknown time zone: {timezone}") from exc
    merchant = Merchant(name=name.strip(), timezone=timezone)
    session.add(merchant)
    await session.flush()
    return _to_info(merchant)


async def find_merchant(session: AsyncSession, merchant_id: uuid.UUID) -> MerchantInfo | None:
    merchant = await session.get(Merchant, merchant_id)
    return _to_info(merchant) if merchant is not None else None


async def get_merchant(session: AsyncSession, merchant_id: uuid.UUID) -> MerchantInfo:
    merchant = await _get_model(session, merchant_id)
    return _to_info(merchant)


async def list_enabled_merchant_ids(session: AsyncSession) -> list[uuid.UUID]:
    """Return IDs of merchants whose AI agent is currently enabled."""
    return list(await session.scalars(select(Merchant.id).where(Merchant.agent_enabled)))


async def set_agent_enabled(session: AsyncSession, merchant_id: uuid.UUID, enabled: bool) -> None:
    merchant = await _get_model(session, merchant_id)
    merchant.agent_enabled = enabled


def business_date(merchant: MerchantInfo | Merchant, at: datetime | None = None) -> date:
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
) -> MerchantInfo:
    merchant = await _get_model(session, merchant_id)
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
    return _to_info(merchant)


async def set_agent_engine(
    session: AsyncSession, merchant_id: uuid.UUID, engine: Literal["v1", "v2", "shadow", "draft"]
) -> None:
    """Which agent answers this shop's customers (agent-phase-2.md section 19)."""
    merchant = await _get_model(session, merchant_id)
    merchant.agent_engine = engine


async def set_menu_image(session: AsyncSession, merchant_id: uuid.UUID, url: str | None) -> None:
    merchant = await _get_model(session, merchant_id)
    merchant.menu_image_url = url


async def _get_model(session: AsyncSession, merchant_id: uuid.UUID) -> Merchant:
    merchant = await session.get(Merchant, merchant_id)
    if merchant is None:
        raise MerchantNotFound(f"No merchant {merchant_id}")
    return merchant


def _to_info(merchant: Merchant) -> MerchantInfo:
    return MerchantInfo(
        id=merchant.id,
        name=merchant.name,
        timezone=merchant.timezone,
        agent_enabled=merchant.agent_enabled,
        agent_engine=merchant.agent_engine,
        never_promise=tuple(merchant.never_promise or ()),
        ai_daily_budget_usd=merchant.ai_daily_budget_usd,
        menu_image_url=merchant.menu_image_url,
        created_at=merchant.created_at,
        updated_at=merchant.updated_at,
    )
