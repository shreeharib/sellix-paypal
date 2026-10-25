from dataclasses import dataclass


@dataclass(frozen=True)
class IncomingMessage:
    """One message from a channel webhook, the same shape for every channel."""

    channel: str  # "instagram" | "whatsapp" | "webchat"
    shop_account_id: str  # the merchant's account on that channel
    customer_id: str  # the customer's ID on that channel (Instagram: IGSID)
    message_id: str
    text: str = ""
    attachment_types: tuple[str, ...] = ()  # e.g. ("image",)
    story_reply_url: str | None = None  # set when the customer replied to a story
    is_echo: bool = False  # sent by the shop (from the Instagram app, or by sellix itself)
