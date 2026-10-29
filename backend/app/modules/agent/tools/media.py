"""Stories, photos and posts: lookup_story, describe_image, transcribe_voice, send_menu_image,
share_post (agent-phase-2.md section 11).

Story and photo media is never stored: the vision model gets the link, and only what it found
(product ids, a caption) is kept. A story is looked at once; later replies use the registry.
"""

import uuid
from typing import Any

from pydantic import BaseModel, Field

from app.core.config import get_settings
from app.core.db import session_scope
from app.modules.agent import items, llm
from app.modules.agent.tools.registry import Tool, ToolResult, TurnContext, register
from app.modules.catalog import service as catalog
from app.modules.conversations import service as conversations
from app.modules.stories import service as stories

SELLING = frozenset({"browsing", "collecting_details"})


class LookupStoryArgs(BaseModel):
    story_id: str | None = Field(default=None, max_length=150)


class LookupStory(Tool):
    name = "lookup_story"
    Args = LookupStoryArgs

    async def run(self, ctx: TurnContext, args: LookupStoryArgs) -> ToolResult:
        story = ctx.trigger_details.get("story") or {}
        story_id = args.story_id or story.get("id")
        if not story_id:
            return ToolResult.fail("no_story", "This message isn't a reply to a story")
        async with session_scope() as session:
            known = await stories.lookup(session, ctx.merchant.id, story_id)
        if known is not None:
            return ToolResult(True, _products(ctx, known.variant_ids, known.confirmed))
        url = story.get("url") if story.get("id") == story_id else None
        if not url:
            return ToolResult(
                True,
                {"products": [], "status": "unknown"},
                hint="Ask which item they mean, or send_menu_image",
            )
        seen = await _look(ctx, url)
        variant_ids = _match(ctx, seen.get("products") or [])
        async with session_scope() as session:
            await stories.save_detected(
                session,
                merchant_id=ctx.merchant.id,
                story_id=story_id,
                cdn_url=url,
                variant_ids=variant_ids,
                caption=seen.get("caption"),
            )
        return ToolResult(True, _products(ctx, tuple(variant_ids), confirmed=False))


class AttachmentArgs(BaseModel):
    attachment_id: str = Field(min_length=2, max_length=10)


class DescribeImage(Tool):
    name = "describe_image"
    Args = AttachmentArgs

    async def run(self, ctx: TurnContext, args: AttachmentArgs) -> ToolResult:
        url = _attachment(ctx, args.attachment_id, "image")
        if url is None:
            return ToolResult.fail("unknown_attachment", f"No image {args.attachment_id}")
        key = stories.media_key(url)
        async with session_scope() as session:
            cached = await stories.cached_result(session, ctx.merchant.id, key)
        if cached is not None:
            return ToolResult(True, cached)
        if ctx.vision_calls >= get_settings().agent_max_images_per_turn:
            return ToolResult.fail(
                "too_many_images",
                "Only a few photos can be looked at per message",
                "Ask the customer which photo they mean",
            )
        seen = await _look(ctx, url)
        data = {
            **_products(ctx, tuple(_match(ctx, seen.get("products") or [])), confirmed=False),
            "caption": seen.get("caption"),
        }
        async with session_scope() as session:
            await stories.save_result(session, ctx.merchant.id, key, data)
        return ToolResult(True, data)


class TranscribeVoice(Tool):
    name = "transcribe_voice"
    Args = AttachmentArgs

    async def run(self, ctx: TurnContext, args: AttachmentArgs) -> ToolResult:
        return ToolResult.fail(
            "not_available",
            "Voice notes can't be understood yet",
            "Ask the customer to type their message",
        )


class SendMenuImageArgs(BaseModel):
    pass


class SendMenuImage(Tool):
    name = "send_menu_image"
    Args = SendMenuImageArgs
    stages = SELLING
    writes = True

    async def run(self, ctx: TurnContext, args: SendMenuImageArgs) -> ToolResult:
        if not ctx.merchant.menu_image_url:
            return ToolResult.fail("not_available", "The shop hasn't uploaded a menu photo")
        async with session_scope() as session:
            await conversations.queue_attachment(
                session,
                conversation_id=ctx.conversation_id,
                attachment={"type": "image", "payload": {"url": ctx.merchant.menu_image_url}},
                label="[Menu photo]",
                key=f"turn:{ctx.turn_id}:menu",
            )
        return ToolResult(True, {"sent": "menu photo"})


class SharePostArgs(BaseModel):
    item_id: str = Field(min_length=2, max_length=20)


class SharePost(Tool):
    name = "share_post"
    Args = SharePostArgs
    stages = SELLING
    writes = True

    async def run(self, ctx: TurnContext, args: SharePostArgs) -> ToolResult:
        item = items.resolve(args.item_id, ctx.stock)
        if item is None or item.variant_id is None:
            return ToolResult.fail("unknown_item", f"No item {args.item_id} in today's menu")
        async with session_scope() as session:
            [variant] = await catalog.list_variants_by_ids(
                session, ctx.merchant.id, [item.variant_id]
            )
            media_id = await stories.post_for(session, ctx.merchant.id, variant.product_id)
            if media_id is None:
                return ToolResult.fail("no_post", "The shop hasn't linked a post to this item")
            await conversations.queue_attachment(
                session,
                conversation_id=ctx.conversation_id,
                attachment={"type": "MEDIA_SHARE", "payload": {"id": media_id}},
                label=f"[Post: {item.label}]",
                key=f"turn:{ctx.turn_id}:post:{args.item_id}",
            )
        return ToolResult(True, {"sent": "post", "item": args.item_id})


async def _look(ctx: TurnContext, url: str) -> dict[str, Any]:
    ctx.vision_calls += 1
    return await llm.describe_image(url, catalog_names=[item.label for item in ctx.stock])


def _match(ctx: TurnContext, names: list[Any]) -> list[uuid.UUID]:
    """Map what the vision model named onto today's items (exact label, then product name)."""
    found: list[uuid.UUID] = []
    for name in (str(n).strip().lower() for n in names):
        for item in ctx.stock:
            if (
                item.variant_id
                and item.variant_id not in found
                and (item.label.lower() == name or item.product.lower() == name)
            ):
                found.append(item.variant_id)
    return found


def _products(
    ctx: TurnContext, variant_ids: tuple[uuid.UUID, ...], confirmed: bool
) -> dict[str, Any]:
    in_stock = {item.variant_id: item for item in ctx.stock}
    return {
        "products": [
            {
                "id": items.ref(variant_id),
                "name": in_stock[variant_id].label if variant_id in in_stock else None,
                "available_today": in_stock[variant_id].available if variant_id in in_stock else 0,
                "price": f"[[price:{items.ref(variant_id)}]]" if variant_id in in_stock else None,
            }
            for variant_id in variant_ids
        ],
        "confirmed_by_shop": confirmed,
    }


def _attachment(ctx: TurnContext, attachment_id: str, kind: str) -> str | None:
    kinds = ctx.trigger_details.get("attachments") or []
    urls = ctx.trigger_details.get("attachment_urls") or []
    try:
        index = int(attachment_id.removeprefix("a"))
    except ValueError:
        return None
    if index < 0 or index >= len(urls) or index >= len(kinds) or kinds[index] != kind:
        return None
    return str(urls[index]) or None


register(LookupStory())
register(DescribeImage())
register(TranscribeVoice())
register(SendMenuImage())
register(SharePost())
