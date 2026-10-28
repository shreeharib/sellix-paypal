import uuid
from dataclasses import dataclass
from datetime import datetime


@dataclass(frozen=True)
class EscalationItem:
    id: uuid.UUID
    merchant_id: uuid.UUID
    conversation_id: uuid.UUID
    trigger_message_id: uuid.UUID | None
    question: str
    status: str
    answer: str | None
    created_at: datetime
    answered_at: datetime | None
