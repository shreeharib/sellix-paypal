import uuid
from dataclasses import dataclass
from datetime import datetime
from typing import Protocol


class HasTimezone(Protocol):
    @property
    def timezone(self) -> str: ...


@dataclass(frozen=True)
class MerchantInfo:
    id: uuid.UUID
    name: str
    timezone: str
    agent_enabled: bool
    created_at: datetime
    updated_at: datetime
