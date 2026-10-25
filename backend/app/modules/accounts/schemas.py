import uuid
from dataclasses import dataclass, field


@dataclass(frozen=True)
class TokenPair:
    access_token: str = field(repr=False)
    refresh_token: str = field(repr=False)
    expires_in: int  # seconds until the access token expires


@dataclass(frozen=True)
class Principal:
    """Who is calling the API: verified from the access token."""

    user_id: uuid.UUID
    session_id: uuid.UUID


@dataclass(frozen=True)
class Membership:
    merchant_id: uuid.UUID
    role: str  # owner | staff
