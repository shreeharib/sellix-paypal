import uuid
from datetime import datetime

from sqlalchemy import func, text
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, server_default=text("gen_random_uuid()")
    )
    display_name: Mapped[str | None]
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
    last_login_at: Mapped[datetime | None]


class UserIdentity(Base):
    """A way a user logs in: their Instagram account today; phone or email later."""

    __tablename__ = "user_identities"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, server_default=text("gen_random_uuid()")
    )
    user_id: Mapped[uuid.UUID]
    provider: Mapped[str]  # instagram | phone | email
    subject: Mapped[str]
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())


class MerchantMember(Base):
    __tablename__ = "merchant_members"

    merchant_id: Mapped[uuid.UUID] = mapped_column(primary_key=True)
    user_id: Mapped[uuid.UUID] = mapped_column(primary_key=True)
    role: Mapped[str] = mapped_column(server_default="owner")  # owner | staff
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())


class Session(Base):
    __tablename__ = "sessions"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, server_default=text("gen_random_uuid()")
    )
    user_id: Mapped[uuid.UUID]
    refresh_token_hash: Mapped[str]
    previous_refresh_token_hash: Mapped[str | None]
    user_agent: Mapped[str | None]
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
    last_used_at: Mapped[datetime] = mapped_column(server_default=func.now())
    expires_at: Mapped[datetime]
    revoked_at: Mapped[datetime | None]


class LoginCode(Base):
    """One-time code handing a finished login back to the app (redeemed with PKCE)."""

    __tablename__ = "login_codes"

    code_hash: Mapped[str] = mapped_column(primary_key=True)
    user_id: Mapped[uuid.UUID]
    code_challenge: Mapped[str]
    expires_at: Mapped[datetime]
    used_at: Mapped[datetime | None]
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
