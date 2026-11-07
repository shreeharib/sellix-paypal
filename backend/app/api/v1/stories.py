"""Stories and media for the merchant app: confirm what a story shows, link posts, menu photo."""

import uuid
from datetime import datetime

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from app.api.v1.deps import Shop
from app.core.db import session_scope
from app.modules.agent import service as agent
from app.modules.merchants import service as merchants
from app.modules.stories import service as stories

router = APIRouter(prefix="/stories", tags=["stories"])


class Story(BaseModel):
    story_id: str
    item_ids: list[str]
    caption: str | None
    expires_at: datetime


class StoryConfirmation(BaseModel):
    item_ids: list[str] = Field(max_length=20)


class PostLink(BaseModel):
    ig_media_id: str = Field(min_length=1, max_length=100)


class MenuImage(BaseModel):
    url: str | None = Field(default=None, max_length=2000)


@router.get("/unconfirmed")
async def unconfirmed_stories(shop: Shop) -> list[Story]:
    """Stories the assistant identified by itself: the merchant confirms them on Today."""
    async with session_scope() as session:
        found = await stories.unconfirmed(session, shop.merchant_id)
    return [
        Story(
            story_id=s.story_id,
            item_ids=[agent.item_ref(v) for v in s.variant_ids],
            caption=s.caption,
            expires_at=s.expires_at,
        )
        for s in found
    ]


@router.post("/{story_id}/confirm")
async def confirm_story(shop: Shop, story_id: str, body: StoryConfirmation) -> dict[str, bool]:
    variant_ids = await agent.variants_for_refs(shop.merchant_id, body.item_ids)
    if variant_ids is None:
        raise HTTPException(status_code=400, detail="Unknown item ids")
    async with session_scope() as session:
        if not await stories.confirm(session, shop.merchant_id, story_id, variant_ids):
            raise HTTPException(status_code=404, detail="Story not found")
    return {"confirmed": True}


@router.put("/posts/{product_id}")
async def link_post(shop: Shop, product_id: uuid.UUID, body: PostLink) -> dict[str, bool]:
    """Link the shop's own Instagram post to a product, so the assistant can share it."""
    async with session_scope() as session:
        await stories.link_post(session, shop.merchant_id, product_id, body.ig_media_id)
    return {"linked": True}


@router.put("/menu-image")
async def set_menu_image(shop: Shop, body: MenuImage) -> dict[str, bool]:
    async with session_scope() as session:
        await merchants.set_menu_image(session, shop.merchant_id, body.url)
    return {"saved": True}
