"""Public interface of the shop_profile module: the versioned Markdown profile the agent reads."""

import re
import uuid
from datetime import UTC, datetime

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.shop_profile.models import ShopOnboarding, ShopProfile
from app.modules.shop_profile.schemas import OnboardingAnswers

MAX_PROFILE_CHARS = 8000  # keeps the agent's cached instructions small and cheap
SAVED_ANSWERS_HEADING = "## Saved answers"
_SAVED_ANSWERS = re.compile(rf"^{SAVED_ANSWERS_HEADING}\n.*?(?=^## |\Z)", re.M | re.S)


async def latest_profile(session: AsyncSession, merchant_id: uuid.UUID) -> str | None:
    return await session.scalar(
        select(ShopProfile.content_md)
        .where(ShopProfile.merchant_id == merchant_id)
        .order_by(ShopProfile.version.desc())
        .limit(1)
    )


async def save_profile(session: AsyncSession, merchant_id: uuid.UUID, content_md: str) -> int:
    """Store a new version and return its number. Older versions are kept."""
    content_md = content_md.strip()
    if not content_md:
        raise ValueError("The shop profile is empty")
    if len(content_md) > MAX_PROFILE_CHARS:
        raise ValueError(f"The shop profile is longer than {MAX_PROFILE_CHARS} characters")
    current = await session.scalar(
        select(func.coalesce(func.max(ShopProfile.version), 0)).where(
            ShopProfile.merchant_id == merchant_id
        )
    )
    version = (current or 0) + 1
    session.add(ShopProfile(merchant_id=merchant_id, version=version, content_md=content_md))
    await session.flush()
    return version


async def latest_version(session: AsyncSession, merchant_id: uuid.UUID) -> ShopProfile | None:
    return await session.scalar(
        select(ShopProfile)
        .where(ShopProfile.merchant_id == merchant_id)
        .order_by(ShopProfile.version.desc())
        .limit(1)
    )


async def get_onboarding(session: AsyncSession, merchant_id: uuid.UUID) -> ShopOnboarding | None:
    return await session.get(ShopOnboarding, merchant_id)


async def save_onboarding(
    session: AsyncSession,
    merchant_id: uuid.UUID,
    *,
    shop_name: str,
    answers: OnboardingAnswers,
    complete: bool = False,
) -> ShopOnboarding:
    """Store the answers and regenerate the shop profile from them. Saved answers already in
    the profile (approved escalation answers) are kept. `complete` finishes the setup."""
    now = datetime.now(UTC)
    onboarding = await session.get(ShopOnboarding, merchant_id) or ShopOnboarding(
        merchant_id=merchant_id
    )
    onboarding.answers = answers.model_dump(exclude_none=True)
    onboarding.updated_at = now
    if complete and onboarding.completed_at is None:
        onboarding.completed_at = now
    session.add(onboarding)

    current = await latest_profile(session, merchant_id)
    saved = _SAVED_ANSWERS.search(current or "")
    content = render_profile(shop_name, answers, saved_answers=saved.group(0) if saved else None)
    if content != (current or "").strip():
        await save_profile(session, merchant_id, content)
    await session.flush()
    return onboarding


def render_profile(
    shop_name: str, answers: OnboardingAnswers, *, saved_answers: str | None = None
) -> str:
    """Onboarding answers -> the Markdown brief the agent reads. Skipped answers are left out."""
    place = ", ".join(part for part in (answers.category, answers.area, answers.city) if part)
    lines = [f"# {shop_name}" + (f" ({place})" if place else "")]

    persona = []
    if answers.intro:
        persona.append(f'Introduce yourself as: "{answers.intro}".')
    if answers.tone:
        persona.append(f"{answers.tone.capitalize()} tone.")
    if answers.emoji is not None:
        persona.append("Light emoji." if answers.emoji else "No emoji.")
    if answers.address_customers:
        persona.append(f"Address customers as: {answers.address_customers}.")
    if persona:
        lines.append("- " + " ".join(persona))
    if answers.hours:
        lines.append(f"- Open {answers.hours}.")
    if answers.weekly_off:
        lines.append(f"- Closed {answers.weekly_off}.")
    if answers.address:
        lines.append(f"- Address: {answers.address}")
    if answers.products:
        lines.append(f"- We sell: {answers.products}")
    if answers.fulfilment:
        lines.append(f"- Pickup and delivery: {answers.fulfilment}")

    policies = [
        (label, value)
        for label, value in (
            ("Custom orders", answers.custom_orders),
            ("Cancellations and refunds", answers.cancellations),
            ("Never promise", answers.never_promise),
        )
        if value
    ]
    if policies:
        lines += ["## Policies", *(f"- {label}: {value}" for label, value in policies)]
    if answers.faqs:
        lines += ["## Common questions", answers.faqs.strip()]
    if saved_answers:
        lines.append(saved_answers.strip())
    return "\n".join(lines)
