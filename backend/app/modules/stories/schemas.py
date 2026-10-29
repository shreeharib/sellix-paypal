import uuid
from dataclasses import dataclass
from datetime import datetime


@dataclass(frozen=True)
class StoryInfo:
    story_id: str
    variant_ids: tuple[uuid.UUID, ...]
    confirmed: bool
    caption: str | None
    expires_at: datetime
