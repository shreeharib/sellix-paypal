"""Public interface of the merchants module."""

import secrets
import uuid
from datetime import date, datetime
from typing import Literal
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import structlog
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.accounts import service as accounts
from app.modules.merchants.models import DataDeletionRequest, Merchant
from app.modules.merchants.schemas import DeletionRequest, MerchantInfo

__all__ = [
    "DeletionRequest",
    "MerchantInfo",
    "MerchantNotFound",
    "business_date",
    "create_merchant",
    "delete_shop",
    "deletion_request",
    "find_merchant",
    "get_merchant",
    "list_enabled_merchant_ids",
    "record_deletion",
    "set_agent_enabled",
    "update_settings",
]

log = structlog.get_logger()

AgentEngine = Literal["v1", "v2", "shadow", "draft"]
DeletionSource = Literal["app", "meta"]


class MerchantNotFound(LookupError):
    pass


async def create_merchant(
    session: AsyncSession,
    *,
    name: str,
    timezone: str = "Asia/Kolkata",
    agent_enabled: bool = False,
    agent_engine: AgentEngine = "v2",
) -> MerchantInfo:
    """A new shop. Its assistant stays off until the onboarding is finished (or switched on)."""
    try:
        ZoneInfo(timezone)
    except ZoneInfoNotFoundError as exc:
        raise ValueError(f"Unknown time zone: {timezone}") from exc
    merchant = Merchant(
        name=name.strip(),
        timezone=timezone,
        agent_enabled=agent_enabled,
        agent_engine=agent_engine,
    )
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
    session: AsyncSession, merchant_id: uuid.UUID, engine: AgentEngine
) -> None:
    """Which agent answers this shop's customers (agent-phase-2.md section 19)."""
    merchant = await _get_model(session, merchant_id)
    merchant.agent_engine = engine


async def set_menu_image(session: AsyncSession, merchant_id: uuid.UUID, url: str | None) -> None:
    merchant = await _get_model(session, merchant_id)
    merchant.menu_image_url = url


async def delete_shop(
    session: AsyncSession, merchant_id: uuid.UUID, *, source: DeletionSource
) -> str:
    """Delete the shop and everything it stores, and sign out its users. Returns the
    confirmation code. Every shop table cascades from merchants, so one delete removes its
    products, stock, customers, chats, messages, orders, payments, rules and channel tokens."""
    await _get_model(session, merchant_id)
    await accounts.remove_shop_users(session, merchant_id)
    await session.execute(delete(Merchant).where(Merchant.id == merchant_id))
    code = await record_deletion(session, source=source, status="deleted")
    log.info("merchants.shop_deleted", merchant_id=str(merchant_id), source=source, code=code)
    return code


async def record_deletion(
    session: AsyncSession, *, source: DeletionSource, status: Literal["deleted", "no_data"]
) -> str:
    """Remember a deletion request's outcome under a new confirmation code (no personal data)."""
    code = secrets.token_hex(6).upper()
    session.add(DataDeletionRequest(code=code, source=source, status=status))
    await session.flush()
    return code


async def deletion_request(session: AsyncSession, code: str) -> DeletionRequest | None:
    row = await session.get(DataDeletionRequest, code.strip().upper())
    if row is None:
        return None
    return DeletionRequest(
        code=row.code, source=row.source, status=row.status, requested_at=row.requested_at
    )


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
