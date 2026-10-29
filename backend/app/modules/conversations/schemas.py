import uuid
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any, Literal

# Code owns the stage; the model can't set it (agent-phase-2.md section 7).
OrderStage = Literal[
    "browsing", "collecting_details", "awaiting_confirmation", "payment_pending", "handed_off"
]


@dataclass(frozen=True)
class ConversationState:
    """A chat as the v2 agent sees it at the start of a turn."""

    id: uuid.UUID
    merchant_id: uuid.UUID
    customer_id: uuid.UUID
    customer_external_id: str
    channel_connection_id: uuid.UUID
    stage: str
    draft: dict[str, Any]
    last_customer_message_at: datetime | None
    agent_active: bool
    customer_handle: str = "the customer"  # their name, or their channel id


@dataclass(frozen=True)
class ChatLine:
    """One stored message, for building the model's context."""

    id: uuid.UUID
    sender: str  # customer | agent | merchant | system
    body: str
    created_at: datetime
    details: dict[str, Any] = field(default_factory=dict)


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
