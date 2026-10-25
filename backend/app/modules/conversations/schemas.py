import uuid
from dataclasses import dataclass
from datetime import datetime


@dataclass(frozen=True)
class ConversationSummary:
    """A chat as the merchant's Chats list shows it."""

    id: uuid.UUID
    channel: str
    customer_id: uuid.UUID
    customer_handle: str  # the customer's name if known, otherwise their channel ID
    agent_active: bool
    agent_paused_reason: str | None
    last_message_sender: str | None
    last_message_body: str | None
    last_message_at: datetime | None


@dataclass(frozen=True)
class MessageView:
    id: uuid.UUID
    direction: str
    sender: str
    body: str
    status: str
    created_at: datetime
