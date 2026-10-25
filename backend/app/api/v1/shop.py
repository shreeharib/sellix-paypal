"""The signed-in merchant, their shop settings and shop profile."""

from fastapi import APIRouter, HTTPException

from app.api.v1 import schemas
from app.api.v1.deps import Shop
from app.core.db import session_scope
from app.modules.channels import service as channels
from app.modules.channels.models import ChannelConnection
from app.modules.merchants import service as merchants
from app.modules.merchants.models import Merchant
from app.modules.shop_profile import service as shop_profile

router = APIRouter(tags=["shop"])


@router.get("/me")
async def me(shop: Shop) -> schemas.Me:
    async with session_scope() as session:
        merchant = await merchants.get_merchant(session, shop.merchant_id)
        connections = await channels.list_connections(session, shop.merchant_id)
        onboarding = await shop_profile.get_onboarding(session, shop.merchant_id)
    return schemas.Me(
        user_id=shop.user_id,
        role=shop.role,
        merchant=_merchant(merchant),
        channels=channel_list(connections),
        onboarding_completed=onboarding is not None and onboarding.completed_at is not None,
    )


@router.patch("/merchant")
async def update_merchant(shop: Shop, body: schemas.MerchantUpdate) -> schemas.Merchant:
    try:
        async with session_scope() as session:
            merchant = await merchants.update_settings(
                session,
                shop.merchant_id,
                name=body.name,
                timezone=body.timezone,
                agent_enabled=body.agent_enabled,
            )
            return _merchant(merchant)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc


@router.get("/shop-profile")
async def get_shop_profile(shop: Shop) -> schemas.ShopProfile | None:
    async with session_scope() as session:
        profile = await shop_profile.latest_version(session, shop.merchant_id)
    if profile is None:
        return None
    return schemas.ShopProfile(
        version=profile.version, content_md=profile.content_md, created_at=profile.created_at
    )


@router.put("/shop-profile")
async def save_shop_profile(shop: Shop, body: schemas.ShopProfileUpdate) -> schemas.ShopProfile:
    try:
        async with session_scope() as session:
            await shop_profile.save_profile(session, shop.merchant_id, body.content_md)
            profile = await shop_profile.latest_version(session, shop.merchant_id)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    if profile is None:
        raise HTTPException(status_code=500, detail="The shop profile wasn't saved")
    return schemas.ShopProfile(
        version=profile.version, content_md=profile.content_md, created_at=profile.created_at
    )


def channel_list(connections: list[ChannelConnection]) -> list[schemas.Channel]:
    return [
        schemas.Channel(
            channel=connection.channel,
            username=connection.username,
            status=connection.status,
            token_expires_at=connection.token_expires_at,
        )
        for connection in connections
    ]


def _merchant(merchant: Merchant) -> schemas.Merchant:
    return schemas.Merchant(
        id=merchant.id,
        name=merchant.name,
        timezone=merchant.timezone,
        agent_enabled=merchant.agent_enabled,
    )
