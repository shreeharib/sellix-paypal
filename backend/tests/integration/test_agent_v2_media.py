"""Stories, photos and posts on the v2 engine (agent-phase-2.md section 11)."""

import json
from typing import Any

import httpx2
import pytest
from sqlalchemy import select

from app.core.db import session_scope
from app.main import create_app
from app.modules.agent import items, llm
from app.modules.agent import service as agent
from app.modules.catalog import service as catalog
from app.modules.channels.models import ChannelConnection
from app.modules.channels.schemas import IncomingMessage
from app.modules.conversations import service as conversations
from app.modules.inventory import service as inventory
from app.modules.merchants import service as merchants
from app.modules.stories import service as stories
from app.modules.stories.models import StoryRegistry
from tests.integration.factories import CUSTOMER_ID, SHOP_ACCOUNT_ID, Instagram, ScriptedModel
from tests.integration.test_api import bearer, sign_in_as

pytestmark = pytest.mark.anyio

STORY_URL = "https://lookaside.fbsbx.com/story/abc"


class Vision:
    """The vision model: what it 'sees' in each image, and how often it was asked."""

    def __init__(self, seen: dict[str, Any]) -> None:
        self.seen = seen
        self.calls: list[str] = []

    async def __call__(self, image_url: str, *, catalog_names: list[str]) -> dict[str, Any]:
        self.calls.append(image_url)
        return self.seen


@pytest.fixture
def vision(monkeypatch: pytest.MonkeyPatch) -> Vision:
    fake = Vision({"products": ["Scoop cookie (Chocolate)"], "caption": "Fresh cookies!"})
    monkeypatch.setattr(llm, "describe_image", fake)
    return fake


async def customer_sends(
    mid: str,
    text: str = "",
    story: tuple[str, str] | None = None,
    attachments: tuple[tuple[str, str], ...] = (),
) -> None:
    async with session_scope() as session:
        turn = await conversations.handle_incoming(
            session,
            IncomingMessage(
                channel="instagram",
                shop_account_id=SHOP_ACCOUNT_ID,
                customer_id=CUSTOMER_ID,
                message_id=mid,
                text=text,
                story_reply_id=story[0] if story else None,
                story_reply_url=story[1] if story else None,
                attachment_types=tuple(kind for kind, _ in attachments),
                attachment_urls=tuple(url for _, url in attachments),
            ),
        )
    assert turn is not None
    await agent.run_turn(turn.conversation_id)


async def cookie(shop: ChannelConnection) -> str:
    async with session_scope() as session:
        merchant = await merchants.get_merchant(session, shop.merchant_id)
        [item] = await inventory.today_stock(
            session, shop.merchant_id, merchants.business_date(merchant)
        )
    assert item.variant_id is not None
    return items.ref(item.variant_id)


def last_tool_result(model: ScriptedModel) -> str:
    return [m.content for m in model.calls[-1][0] if m.role == "tool"][-1]


async def test_a_story_is_identified_once_and_later_replies_cost_no_image_call(
    v2_shop: ChannelConnection, model: ScriptedModel, instagram: Instagram, vision: Vision
) -> None:
    item = await cookie(v2_shop)
    model.then(
        [("lookup_story", {})],
        [("send_reply", {"text": "Chocolate cookie [[price:" + item + "]]!", "language": "ta-en"})],
    )
    await customer_sends("m-1", "idhu venum", story=("story-1", STORY_URL))

    assert item in last_tool_result(model)
    assert vision.calls == [STORY_URL]
    async with session_scope() as session:
        registered = await session.scalar(select(StoryRegistry))
    assert registered is not None and not registered.confirmed_by_merchant
    assert registered.cdn_url == STORY_URL  # the link only, never the media

    model.then(
        [("lookup_story", {})],
        [("send_reply", {"text": "Same cookie!", "language": "ta-en"})],
    )
    await customer_sends("m-2", "M size irukka?", story=("story-1", STORY_URL))

    assert item in last_tool_result(model)
    assert len(vision.calls) == 1


async def test_the_merchant_confirms_what_a_story_shows(
    v2_shop: ChannelConnection, model: ScriptedModel, instagram: Instagram, vision: Vision
) -> None:
    model.then([("lookup_story", {})], [("send_reply", {"text": "Ok!", "language": "en"})])
    await customer_sends("m-1", "this one", story=("story-1", STORY_URL))
    item = await cookie(v2_shop)
    token = await sign_in_as(v2_shop.merchant_id)
    async with httpx2.AsyncClient(
        transport=httpx2.ASGITransport(app=create_app()), base_url="http://test"
    ) as api:
        waiting = await api.get("/v1/stories/unconfirmed", headers=bearer(token))
        confirmed = await api.post(
            "/v1/stories/story-1/confirm", headers=bearer(token), json={"item_ids": [item]}
        )
        after = await api.get("/v1/stories/unconfirmed", headers=bearer(token))

    assert [s["story_id"] for s in waiting.json()] == ["story-1"]
    assert confirmed.status_code == 200
    assert after.json() == []


async def test_photos_are_described_once_and_at_most_three_per_turn(
    v2_shop: ChannelConnection, model: ScriptedModel, instagram: Instagram, vision: Vision
) -> None:
    photos = tuple(("image", f"https://cdn.example/photo-{n}.jpg") for n in range(4))
    model.then(
        [("describe_image", {"attachment_id": f"a{n}"}) for n in range(4)]
        + [("describe_image", {"attachment_id": "a0"})],
        [("send_reply", {"text": "Nice!", "language": "en"})],
    )

    await customer_sends("m-1", "which of these do you have?", attachments=photos)

    results = [m.content for m in model.calls[-1][0] if m.role == "tool"]
    assert len(vision.calls) == 3
    assert "too_many_images" in results[3]
    assert json.loads(results[4]) == json.loads(results[0])  # cached: no new call


async def test_the_shops_own_post_and_menu_image_are_sent_through_the_outbox(
    v2_shop: ChannelConnection, model: ScriptedModel, instagram: Instagram, vision: Vision
) -> None:
    item = await cookie(v2_shop)
    async with session_scope() as session:
        merchant = await merchants.get_merchant(session, v2_shop.merchant_id)
        [stock] = await inventory.today_stock(
            session, v2_shop.merchant_id, merchants.business_date(merchant)
        )
        assert stock.variant_id is not None
        [variant] = await catalog.list_variants_by_ids(
            session, v2_shop.merchant_id, [stock.variant_id]
        )
        await stories.link_post(session, v2_shop.merchant_id, variant.product_id, "IG-MEDIA-7")
        await merchants.set_menu_image(session, v2_shop.merchant_id, "https://cdn.example/menu.jpg")
    model.then(
        [("share_post", {"item_id": item}), ("send_menu_image", {})],
        [("send_reply", {"text": "Here you go!", "language": "en"})],
    )

    await customer_sends("m-1", "show me")

    post, menu, reply = instagram.sent
    assert post["attachment"] == {"type": "MEDIA_SHARE", "payload": {"id": "IG-MEDIA-7"}}
    assert menu["attachment"] == {
        "type": "image",
        "payload": {"url": "https://cdn.example/menu.jpg"},
    }
    assert reply["text"] == "Here you go!"


async def test_voice_notes_are_not_supported_yet(
    v2_shop: ChannelConnection, model: ScriptedModel, instagram: Instagram, vision: Vision
) -> None:
    model.then(
        [("transcribe_voice", {"attachment_id": "a0"})],
        [("send_reply", {"text": "Could you type it please?", "language": "en"})],
    )

    await customer_sends("m-1", attachments=(("audio", "https://cdn.example/voice.mp4"),))

    assert "not_available" in last_tool_result(model)
    assert vision.calls == []
