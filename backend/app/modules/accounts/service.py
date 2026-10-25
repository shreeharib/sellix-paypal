"""Public interface of the accounts module: sign-in, login codes and sessions.

Access tokens are short-lived signed JWTs, checked without a database lookup. Refresh tokens
are random, stored only as hashes, and rotated on every use; presenting a rotated-out token
again revokes the session, because it means the token was copied.
"""

import base64
import hashlib
import hmac
import secrets
import uuid
from datetime import UTC, datetime, timedelta

import jwt
from sqlalchemy import select, update
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.modules.accounts.models import LoginCode, MerchantMember, Session, User, UserIdentity
from app.modules.accounts.schemas import Membership, Principal, TokenPair

ACCESS_TOKEN_TTL = timedelta(minutes=15)
REFRESH_TOKEN_TTL = timedelta(days=60)
LOGIN_CODE_TTL = timedelta(minutes=2)
_ISSUER = "sellix"
_AUDIENCE = "sellix-app"


class AuthFailed(Exception):
    """The login code, token or session isn't valid; the client must sign in again."""


async def sign_in(
    session: AsyncSession,
    *,
    provider: str,
    subject: str,
    merchant_id: uuid.UUID,
    display_name: str | None,
) -> uuid.UUID:
    """Find or create the user behind an identity and make sure they belong to the shop."""
    user_id = await session.scalar(
        select(UserIdentity.user_id).where(
            UserIdentity.provider == provider, UserIdentity.subject == subject
        )
    )
    if user_id is None:
        user = User(display_name=display_name)
        session.add(user)
        await session.flush()
        user_id = user.id
        session.add(UserIdentity(user_id=user_id, provider=provider, subject=subject))
    await session.execute(
        pg_insert(MerchantMember)
        .values(merchant_id=merchant_id, user_id=user_id, role="owner")
        .on_conflict_do_nothing(index_elements=[MerchantMember.merchant_id, MerchantMember.user_id])
    )
    await session.execute(
        update(User).where(User.id == user_id).values(last_login_at=datetime.now(UTC))
    )
    return user_id


async def create_login_code(session: AsyncSession, user_id: uuid.UUID, code_challenge: str) -> str:
    code = secrets.token_urlsafe(32)
    session.add(
        LoginCode(
            code_hash=_hash(code),
            user_id=user_id,
            code_challenge=code_challenge,
            expires_at=datetime.now(UTC) + LOGIN_CODE_TTL,
        )
    )
    await session.flush()
    return code


async def redeem_login_code(
    session: AsyncSession, *, code: str, code_verifier: str, user_agent: str | None
) -> TokenPair:
    """Exchange the one-time code for a session, proving the app started this login (PKCE)."""
    login = await session.scalar(
        select(LoginCode).where(LoginCode.code_hash == _hash(code)).with_for_update()
    )
    if login is None or login.used_at is not None or login.expires_at < datetime.now(UTC):
        raise AuthFailed("This login link has expired. Please sign in again.")
    if not hmac.compare_digest(pkce_challenge(code_verifier), login.code_challenge):
        raise AuthFailed("This login wasn't started by this app. Please sign in again.")
    login.used_at = datetime.now(UTC)
    return await _start_session(session, login.user_id, user_agent)


async def refresh(
    session: AsyncSession, *, refresh_token: str, user_agent: str | None
) -> TokenPair | None:
    """Rotate a refresh token. None means "sign in again"; if a rotated-out token was
    reused, its session is revoked in this transaction (so the caller must commit)."""
    token_hash = _hash(refresh_token)
    now = datetime.now(UTC)
    current = await session.scalar(
        select(Session).where(Session.refresh_token_hash == token_hash).with_for_update()
    )
    if current is None:
        reused = await session.scalar(
            select(Session).where(Session.previous_refresh_token_hash == token_hash)
        )
        if reused is not None and reused.revoked_at is None:
            reused.revoked_at = now  # a copied token was used: end that session
        return None
    if current.revoked_at is not None or current.expires_at < now:
        return None

    new_refresh_token = secrets.token_urlsafe(32)
    current.previous_refresh_token_hash = current.refresh_token_hash
    current.refresh_token_hash = _hash(new_refresh_token)
    current.last_used_at = now
    current.user_agent = user_agent or current.user_agent
    return TokenPair(
        access_token=_access_token(current.user_id, current.id),
        refresh_token=new_refresh_token,
        expires_in=int(ACCESS_TOKEN_TTL.total_seconds()),
    )


async def revoke_session(session: AsyncSession, session_id: uuid.UUID) -> None:
    await session.execute(
        update(Session)
        .where(Session.id == session_id, Session.revoked_at.is_(None))
        .values(revoked_at=datetime.now(UTC))
    )


def verify_access_token(token: str) -> Principal:
    try:
        claims = jwt.decode(
            token,
            _signing_key(),
            algorithms=["HS256"],
            audience=_AUDIENCE,
            issuer=_ISSUER,
            options={"require": ["exp", "sub", "sid"]},
        )
        return Principal(user_id=uuid.UUID(claims["sub"]), session_id=uuid.UUID(claims["sid"]))
    except (jwt.PyJWTError, ValueError, KeyError) as exc:
        raise AuthFailed("Please sign in again.") from exc


async def membership(session: AsyncSession, user_id: uuid.UUID) -> Membership | None:
    row = (
        await session.execute(
            select(MerchantMember.merchant_id, MerchantMember.role)
            .where(MerchantMember.user_id == user_id)
            .order_by(MerchantMember.created_at)
            .limit(1)
        )
    ).first()
    return Membership(merchant_id=row[0], role=row[1]) if row else None


def pkce_challenge(code_verifier: str) -> str:
    """The S256 challenge for a verifier (RFC 7636)."""
    digest = hashlib.sha256(code_verifier.encode()).digest()
    return base64.urlsafe_b64encode(digest).rstrip(b"=").decode()


async def _start_session(
    session: AsyncSession, user_id: uuid.UUID, user_agent: str | None
) -> TokenPair:
    refresh_token = secrets.token_urlsafe(32)
    record = Session(
        user_id=user_id,
        refresh_token_hash=_hash(refresh_token),
        user_agent=(user_agent or "")[:300] or None,
        expires_at=datetime.now(UTC) + REFRESH_TOKEN_TTL,
    )
    session.add(record)
    await session.flush()
    return TokenPair(
        access_token=_access_token(user_id, record.id),
        refresh_token=refresh_token,
        expires_in=int(ACCESS_TOKEN_TTL.total_seconds()),
    )


def _access_token(user_id: uuid.UUID, session_id: uuid.UUID) -> str:
    now = datetime.now(UTC)
    return jwt.encode(
        {
            "iss": _ISSUER,
            "aud": _AUDIENCE,
            "sub": str(user_id),
            "sid": str(session_id),
            "iat": now,
            "exp": now + ACCESS_TOKEN_TTL,
        },
        _signing_key(),
        algorithm="HS256",
    )


def _signing_key() -> str:
    key = get_settings().session_signing_key
    if len(key) < 32:
        raise AuthFailed("SESSION_SIGNING_KEY isn't set (it needs at least 32 characters)")
    return key


def _hash(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()
