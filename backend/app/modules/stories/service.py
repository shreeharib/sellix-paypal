"""Public interface of the stories module: what the shop's stories show, photo results, posts.

Story media is never stored (Meta's rule): only the CDN link and what code derived from it.
"""

import hashlib
import uuid
from datetime import UTC, datetime, timedelta
from typing import Any

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.stories.models import MediaResult, ProductPost, StoryRegistry
from app.modules.stories.schemas import StoryInfo

STORY_LIFETIME = timedelta(hours=24)


async def lookup(session: AsyncSession, merchant_id: uuid.UUID, story_id: str) -> StoryInfo | None:
    row = await session.scalar(
        select(StoryRegistry).where(
            StoryRegistry.merchant_id == merchant_id, StoryRegistry.ig_story_id == story_id
        )
    )
    return _info(row) if row else None


async def save_detected(
    session: AsyncSession,
    *,
    merchant_id: uuid.UUID,
    story_id: str,
    cdn_url: str | None,
    variant_ids: list[uuid.UUID],
    caption: str | None,
) -> None:
    """What the vision model saw on a first reply; the merchant confirms it on Today."""
    await session.execute(
        pg_insert(StoryRegistry)
        .values(
            merchant_id=merchant_id,
            ig_story_id=story_id,
            cdn_url=cdn_url,
            products=[str(v) for v in variant_ids],
            caption=caption,
            expires_at=datetime.now(UTC) + STORY_LIFETIME,
        )
        .on_conflict_do_nothing(index_elements=["merchant_id", "ig_story_id"])
    )


async def confirm(
    session: AsyncSession, merchant_id: uuid.UUID, story_id: str, variant_ids: list[uuid.UUID]
) -> bool:
    row = await session.scalar(
        select(StoryRegistry)
        .where(StoryRegistry.merchant_id == merchant_id, StoryRegistry.ig_story_id == story_id)
        .with_for_update()
    )
    if row is None:
        return False
    row.products = [str(v) for v in variant_ids]
    row.confirmed_by_merchant = True
    return True


async def unconfirmed(session: AsyncSession, merchant_id: uuid.UUID) -> list[StoryInfo]:
    rows = await session.scalars(
        select(StoryRegistry)
        .where(
            StoryRegistry.merchant_id == merchant_id,
            StoryRegistry.confirmed_by_merchant.is_(False),
        )
        .order_by(StoryRegistry.created_at.desc())
    )
    return [_info(row) for row in rows]


def media_key(url: str) -> str:
    return hashlib.sha256(url.encode()).hexdigest()


async def cached_result(
    session: AsyncSession, merchant_id: uuid.UUID, key: str
) -> dict[str, Any] | None:
    return await session.scalar(
        select(MediaResult.result).where(
            MediaResult.merchant_id == merchant_id, MediaResult.media_key == key
        )
    )


async def save_result(
    session: AsyncSession, merchant_id: uuid.UUID, key: str, result: dict[str, Any]
) -> None:
    await session.execute(
        pg_insert(MediaResult)
        .values(merchant_id=merchant_id, media_key=key, result=result)
        .on_conflict_do_nothing(index_elements=["merchant_id", "media_key"])
    )


async def link_post(
    session: AsyncSession, merchant_id: uuid.UUID, product_id: uuid.UUID, ig_media_id: str
) -> None:
    """The shop's own Instagram post for this product (Catalog), for share_post."""
    await session.execute(
        pg_insert(ProductPost)
        .values(merchant_id=merchant_id, product_id=product_id, ig_media_id=ig_media_id)
        .on_conflict_do_update(
            index_elements=["merchant_id", "product_id"], set_={"ig_media_id": ig_media_id}
        )
    )


async def post_for(
    session: AsyncSession, merchant_id: uuid.UUID, product_id: uuid.UUID
) -> str | None:
    return await session.scalar(
        select(ProductPost.ig_media_id).where(
            ProductPost.merchant_id == merchant_id, ProductPost.product_id == product_id
        )
    )


def _info(row: StoryRegistry) -> StoryInfo:
    ids = [uuid.UUID(v) for v in row.products or []]
    if not ids and row.mapped_variant_id:
        ids = [row.mapped_variant_id]
    return StoryInfo(
        story_id=row.ig_story_id,
        variant_ids=tuple(ids),
        confirmed=row.confirmed_by_merchant,
        caption=row.caption,
        expires_at=row.expires_at,
    )
