from typing import Any
from urllib.parse import parse_qs, urlparse

from app.modules.channels import instagram

SHOP = "17841400000000001"
CUSTOMER = "7000000000000002"


def payload(*events: dict[str, Any], object_type: str = "instagram") -> dict[str, Any]:
    return {"object": object_type, "entry": [{"id": SHOP, "time": 0, "messaging": list(events)}]}


def customer_event(message: dict[str, Any]) -> dict[str, Any]:
    return {"sender": {"id": CUSTOMER}, "recipient": {"id": SHOP}, "message": message}


def test_text_message_from_a_customer() -> None:
    [message] = instagram.parse_messages(
        payload(customer_event({"mid": "m1", "text": "rendu cookie venum"}))
    )

    assert message.channel == "instagram"
    assert message.shop_account_id == SHOP
    assert message.customer_id == CUSTOMER
    assert message.message_id == "m1"
    assert message.text == "rendu cookie venum"
    assert not message.is_echo


def test_echo_swaps_sender_and_recipient() -> None:
    echo = {
        "sender": {"id": SHOP},
        "recipient": {"id": CUSTOMER},
        "message": {"mid": "m2", "text": "Sure!", "is_echo": True},
    }

    [message] = instagram.parse_messages(payload(echo))

    assert message.is_echo
    assert message.shop_account_id == SHOP
    assert message.customer_id == CUSTOMER


def test_story_reply_and_attachments() -> None:
    [message] = instagram.parse_messages(
        payload(
            customer_event(
                {
                    "mid": "m3",
                    "text": "idhu venum",
                    "reply_to": {"story": {"id": "s1", "url": "https://cdn.test/story.jpg"}},
                    "attachments": [{"type": "image", "payload": {"url": "https://cdn.test/a"}}],
                }
            )
        )
    )

    assert message.story_reply_url == "https://cdn.test/story.jpg"
    assert message.attachment_types == ("image",)


def test_deleted_messages_and_other_objects_are_ignored() -> None:
    deleted = customer_event({"mid": "m4", "is_deleted": True})
    read_receipt = {"sender": {"id": CUSTOMER}, "recipient": {"id": SHOP}, "read": {"mid": "m1"}}

    assert instagram.parse_messages(payload(deleted, read_receipt)) == []
    assert (
        instagram.parse_messages(payload(customer_event({"mid": "m5"}), object_type="page")) == []
    )


def test_authorize_url_asks_for_messaging_permissions() -> None:
    url = instagram.authorize_url(
        app_id="123", redirect_uri="https://sellix.test/oauth/instagram/callback", state="abc"
    )

    query = parse_qs(urlparse(url).query)
    assert url.startswith(instagram.AUTHORIZE_URL)
    assert query["client_id"] == ["123"]
    assert query["response_type"] == ["code"]
    assert query["state"] == ["abc"]
    assert set(query["scope"][0].split(",")) == set(instagram.SCOPES)


def test_story_replies_keep_the_story_id_and_attachments_their_urls() -> None:
    [message] = instagram.parse_messages(
        payload(
            customer_event(
                {
                    "mid": "m1",
                    "text": "idhu venum",
                    "reply_to": {"story": {"id": "story-9", "url": "https://cdn/story-9"}},
                    "attachments": [{"type": "image", "payload": {"url": "https://cdn/p.jpg"}}],
                }
            )
        )
    )

    assert (message.story_reply_id, message.story_reply_url) == ("story-9", "https://cdn/story-9")
    assert message.attachment_types == ("image",)
    assert message.attachment_urls == ("https://cdn/p.jpg",)
