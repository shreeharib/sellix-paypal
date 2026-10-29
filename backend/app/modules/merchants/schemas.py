import uuid
from dataclasses import dataclass
from datetime import datetime
from decimal import Decimal
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
    agent_engine: str = "v1"  # v1 | v2 (agent-phase-2.md section 19)
    never_promise: tuple[str, ...] = ()  # phrases the agent must never promise
    ai_daily_budget_usd: Decimal | None = None  # None: the default from settings
    menu_image_url: str | None = None  # today's menu photo, for send_menu_image
