"""Guided onboarding after the first "Continue with Instagram": the shop, what it sells,
the agent's persona and policies. Every step can be skipped and finished later."""

from fastapi import APIRouter, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1 import schemas
from app.api.v1.deps import Shop, ShopContext
from app.api.v1.shop import channel_list
from app.core.db import session_scope
from app.modules.channels import service as channels
from app.modules.merchants import service as merchants
from app.modules.payments import service as payments
from app.modules.shop_profile import service as shop_profile
from app.modules.shop_profile.schemas import OnboardingAnswers

router = APIRouter(prefix="/onboarding", tags=["onboarding"])


@router.get("")
async def get_onboarding(shop: Shop) -> schemas.Onboarding:
    async with session_scope() as session:
        return await _onboarding(session, shop)


@router.put("")
async def save_onboarding(shop: Shop, body: schemas.OnboardingUpdate) -> schemas.Onboarding:
    """Saves the answers (also after each step) and regenerates the shop profile."""
    try:
        async with session_scope() as session:
            merchant = await merchants.update_settings(
                session, shop.merchant_id, name=body.shop_name
            )
            await shop_profile.save_onboarding(
                session,
                shop.merchant_id,
                shop_name=merchant.name,
                answers=body.answers,
                complete=body.complete,
            )
            return await _onboarding(session, shop)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc


async def _onboarding(session: AsyncSession, shop: ShopContext) -> schemas.Onboarding:
    merchant = await merchants.get_merchant(session, shop.merchant_id)
    onboarding = await shop_profile.get_onboarding(session, shop.merchant_id)
    connections = await channels.list_connections(session, shop.merchant_id)
    return schemas.Onboarding(
        shop_name=merchant.name,
        answers=OnboardingAnswers.model_validate(onboarding.answers if onboarding else {}),
        completed=onboarding is not None and onboarding.completed_at is not None,
        channels=channel_list(connections),
        payments_ready=payments.configured(),
    )
