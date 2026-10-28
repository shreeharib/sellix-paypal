import uuid
from dataclasses import dataclass
from datetime import datetime


@dataclass(frozen=True)
class ChannelConnectionInfo:
    id: uuid.UUID
    merchant_id: uuid.UUID
    channel: str
    external_account_id: str
    username: str | None
    status: str
    token_expires_at: datetime | None
    token_refreshed_at: datetime | None
    scopes: tuple[str, ...]
    created_at: datetime
    updated_at: datetime


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
