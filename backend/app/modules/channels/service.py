"""Public interface of the channels module."""

import re
import uuid
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from typing import Any, Literal

import structlog
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core import crypto, signing
from app.core.config import get_settings
from app.modules.channels import instagram
from app.modules.channels.models import ChannelConnection
from app.modules.channels.schemas import ChannelConnectionInfo, IncomingMessage
from app.modules.merchants import service as merchants

log = structlog.get_logger()

OAUTH_STATE_TTL_SECONDS = 15 * 60
MAX_TEXT_LENGTH = instagram.MAX_TEXT_LENGTH  # longest message one send can carry
MAX_TEXT_BYTES = instagram.MAX_TEXT_BYTES  # Instagram counts UTF-8 bytes, not characters
_CONNECT_PURPOSE = "instagram_connect"
_LOGIN_PURPOSE = "app_login"
_PKCE_CHALLENGE = re.compile(r"[A-Za-z0-9_-]{43}")  # base64url SHA-256, unpadded


class ChannelConnectError(RuntimeError):
    """Connecting a channel account failed; the message is safe to show the merchant."""


SendFailureReason = Literal["retryable", "window_closed", "recipient_unavailable", "permanent"]


class SendFailed(RuntimeError):
    """A send didn't go through; `reason` says whether trying again can help."""

    def __init__(self, message: str, *, reason: SendFailureReason = "permanent") -> None:
        super().__init__(message)
        self.reason: SendFailureReason = reason

    @property
    def retryable(self) -> bool:
        return self.reason == "retryable"


@dataclass(frozen=True)
class InstagramOAuthResult:
    connection: ChannelConnectionInfo
    account_id: str
    username: str
    is_login: bool  # an app login ("Continue with Instagram"), not an operator connect
    code_challenge: str | None = None
    app_redirect_uri: str | None = None


@dataclass(frozen=True)
class SendCredentials:
    channel: str
    account_id: str
    access_token: str = field(repr=False)


def parse_webhook(payload: dict[str, Any]) -> list[IncomingMessage]:
    """Turn a Meta webhook payload into channel-neutral messages."""
    return instagram.parse_messages(payload)


async def get_active_connection(
    session: AsyncSession, channel: str, external_account_id: str
) -> ChannelConnectionInfo | None:
    connection = await session.scalar(
        select(ChannelConnection).where(
            ChannelConnection.channel == channel,
            ChannelConnection.external_account_id == external_account_id,
            ChannelConnection.status == "active",
        )
    )
    return _to_info(connection) if connection is not None else None


async def get_send_credentials(session: AsyncSession, connection_id: uuid.UUID) -> SendCredentials:
    connection = await session.get(ChannelConnection, connection_id)
    if connection is None or connection.status != "active":
        raise SendFailed(f"Channel connection {connection_id} isn't active")
    return SendCredentials(
        channel=connection.channel,
        account_id=connection.external_account_id,
        access_token=crypto.decrypt(connection.access_token_encrypted),
    )


async def send_text(credentials: SendCredentials, recipient_id: str, text: str) -> str:
    """Send a message to a customer. Returns the channel's message ID."""
    if credentials.channel != "instagram":
        raise SendFailed(f"Sending on {credentials.channel} isn't supported yet")
    try:
        return await instagram.send_text(
            api_version=get_settings().graph_api_version,
            account_id=credentials.account_id,
            token=credentials.access_token,
            recipient_id=recipient_id,
            text=text,
        )
    except instagram.InstagramAPIError as exc:
        raise SendFailed(str(exc), reason=_send_failure_reason(exc)) from exc


# Meta's error codes for sends. To confirm against real payloads (agent-phase-2.md section 21,
# item 4) and record them in docs/meta-payloads.md.
_RATE_LIMIT_CODES = {4, 17, 32, 613}
_OUTSIDE_WINDOW = (10, 2018278)
_RECIPIENT_UNAVAILABLE_CODE = 551


def _send_failure_reason(exc: instagram.InstagramAPIError) -> SendFailureReason:
    if exc.status == 0 or exc.status == 429 or exc.status >= 500:
        return "retryable"
    if exc.code in _RATE_LIMIT_CODES:
        return "retryable"
    if (exc.code, exc.subcode) == _OUTSIDE_WINDOW:
        return "window_closed"
    if exc.code == _RECIPIENT_UNAVAILABLE_CODE:
        return "recipient_unavailable"
    return "permanent"


def instagram_redirect_uri() -> str:
    return f"{get_settings().public_base_url.rstrip('/')}/oauth/instagram/callback"


def instagram_authorize_url(merchant_id: uuid.UUID) -> str:
    """Operator link that connects an existing merchant's Instagram account (support tool)."""
    state = signing.sign(
        {"purpose": _CONNECT_PURPOSE, "merchant_id": str(merchant_id)},
        ttl_seconds=OAUTH_STATE_TTL_SECONDS,
    )
    return instagram.authorize_url(
        app_id=get_settings().instagram_app_id,
        redirect_uri=instagram_redirect_uri(),
        state=state,
    )


def allowed_app_redirect_uris() -> list[str]:
    return [uri.strip() for uri in get_settings().app_redirect_uris.split(",") if uri.strip()]


def instagram_login_url(*, code_challenge: str, app_redirect_uri: str) -> str:
    """ "Continue with Instagram": signs the merchant in and connects their shop's account."""
    if app_redirect_uri not in allowed_app_redirect_uris():
        raise ChannelConnectError("This app isn't allowed to sign in here.")
    if not _PKCE_CHALLENGE.fullmatch(code_challenge):
        raise ChannelConnectError("The sign-in request is malformed.")
    _require_instagram_app()
    state = signing.sign(
        {"purpose": _LOGIN_PURPOSE, "challenge": code_challenge, "redirect": app_redirect_uri},
        ttl_seconds=OAUTH_STATE_TTL_SECONDS,
    )
    return instagram.authorize_url(
        app_id=get_settings().instagram_app_id,
        redirect_uri=instagram_redirect_uri(),
        state=state,
    )


def _require_instagram_app() -> None:
    """Without these, Instagram shows its own error page and never returns to the app."""
    settings = get_settings()
    if not settings.instagram_app_id or not settings.instagram_app_secret:
        log.warning("channels.instagram_not_configured", missing="INSTAGRAM_APP_ID/SECRET")
        raise ChannelConnectError("Instagram sign-in isn't set up on this server yet.")
    if not settings.public_base_url.startswith("https://"):
        log.warning("channels.instagram_redirect_not_https", url=settings.public_base_url)
        raise ChannelConnectError(
            "Instagram sign-in needs the server's public https address (PUBLIC_BASE_URL)."
        )


def login_redirect_for(state: str) -> str | None:
    """Where to send the merchant back to for an app login state, if it's genuine."""
    try:
        claims = signing.verify(state)
    except signing.InvalidSignature:
        return None
    redirect = claims.get("redirect")
    if claims.get("purpose") == _LOGIN_PURPOSE and redirect in allowed_app_redirect_uris():
        return str(redirect)
    return None


async def complete_instagram_oauth(
    session: AsyncSession, *, code: str, state: str
) -> InstagramOAuthResult:
    """Finish Instagram's OAuth: exchange the code, subscribe webhooks, store the encrypted
    token. For an app login on a new account, this also creates the merchant."""
    try:
        claims = signing.verify(state)
    except signing.InvalidSignature as exc:
        raise ChannelConnectError(
            "This link has expired or is invalid. Please start again."
        ) from exc
    purpose = claims.get("purpose")
    if purpose not in (_CONNECT_PURPOSE, _LOGIN_PURPOSE):
        raise ChannelConnectError("This link is invalid. Please start again.")
    merchant = (
        await merchants.get_merchant(session, uuid.UUID(claims["merchant_id"]))
        if purpose == _CONNECT_PURPOSE
        else None
    )

    settings = get_settings()
    try:
        short = await instagram.exchange_code(
            app_id=settings.instagram_app_id,
            app_secret=settings.instagram_app_secret,
            redirect_uri=instagram_redirect_uri(),
            code=code,
        )
        grant = await instagram.exchange_long_lived(
            app_secret=settings.instagram_app_secret, short_lived_token=short.access_token
        )
        account = await instagram.fetch_account(
            api_version=settings.graph_api_version, token=grant.access_token
        )
        await instagram.subscribe_webhooks(
            api_version=settings.graph_api_version, token=grant.access_token
        )
    except instagram.InstagramAPIError as exc:
        log.warning("channels.instagram_oauth_failed", purpose=purpose, error=str(exc))
        if "Unsupported request" in str(exc):
            # What Instagram answers for accounts it won't serve through this app.
            raise ChannelConnectError(
                "Instagram didn't allow this account. Use your shop's professional "
                "(Business or Creator) account."
            ) from exc
        raise ChannelConnectError(
            "Instagram didn't accept the connection. Please try again."
        ) from exc

    existing = await session.scalar(
        select(ChannelConnection).where(
            ChannelConnection.channel == "instagram",
            ChannelConnection.external_account_id == account.account_id,
        )
    )
    if merchant is not None:
        if existing is not None and existing.merchant_id != merchant.id:
            raise ChannelConnectError(f"@{account.username} is already connected to another shop.")
        merchant_id = merchant.id
    elif existing is not None:
        merchant_id = existing.merchant_id  # returning merchant: same shop
    else:
        merchant_id = (
            await merchants.create_merchant(session, name=account.username or "My shop")
        ).id

    connection = existing or ChannelConnection(
        merchant_id=merchant_id, channel="instagram", external_account_id=account.account_id
    )
    now = datetime.now(UTC)
    connection.username = account.username
    connection.access_token_encrypted = crypto.encrypt(grant.access_token)
    connection.token_expires_at = _expiry(now, grant.expires_in)
    connection.token_refreshed_at = now
    connection.scopes = list(short.scopes or instagram.SCOPES)
    connection.status = "active"
    session.add(connection)
    await session.flush()
    log.info(
        "channels.instagram_connected",
        merchant_id=str(merchant_id),
        account_id=account.account_id,
        username=account.username,
        purpose=purpose,
    )
    is_login = purpose == _LOGIN_PURPOSE
    return InstagramOAuthResult(
        connection=_to_info(connection),
        account_id=account.account_id,
        username=account.username,
        is_login=is_login,
        code_challenge=str(claims["challenge"]) if is_login else None,
        app_redirect_uri=str(claims["redirect"]) if is_login else None,
    )


async def list_connections(
    session: AsyncSession, merchant_id: uuid.UUID
) -> list[ChannelConnectionInfo]:
    rows = await session.scalars(
        select(ChannelConnection)
        .where(ChannelConnection.merchant_id == merchant_id)
        .order_by(ChannelConnection.created_at)
    )
    return [_to_info(c) for c in rows]


def _to_info(connection: ChannelConnection) -> ChannelConnectionInfo:
    return ChannelConnectionInfo(
        id=connection.id,
        merchant_id=connection.merchant_id,
        channel=connection.channel,
        external_account_id=connection.external_account_id,
        username=connection.username,
        status=connection.status,
        token_expires_at=connection.token_expires_at,
        token_refreshed_at=connection.token_refreshed_at,
        scopes=tuple(connection.scopes or ()),
        created_at=connection.created_at,
        updated_at=connection.updated_at,
    )


async def refresh_expiring_tokens(session: AsyncSession, *, within: timedelta) -> int:
    """Refresh Instagram tokens that expire soon. Returns how many were refreshed."""
    now = datetime.now(UTC)
    connections = await session.scalars(
        select(ChannelConnection).where(
            ChannelConnection.channel == "instagram",
            ChannelConnection.status == "active",
            ChannelConnection.token_expires_at < now + within,
            ChannelConnection.token_refreshed_at < now - timedelta(days=1),
        )
    )
    refreshed = 0
    for connection in connections:
        try:
            grant = await instagram.refresh_long_lived(
                token=crypto.decrypt(connection.access_token_encrypted)
            )
        except instagram.InstagramAPIError as exc:
            connection.status = "error"
            log.error(
                "channels.token_refresh_failed", connection_id=str(connection.id), error=str(exc)
            )
            continue
        connection.access_token_encrypted = crypto.encrypt(grant.access_token)
        connection.token_expires_at = _expiry(now, grant.expires_in)
        connection.token_refreshed_at = now
        refreshed += 1
    return refreshed


def _expiry(now: datetime, expires_in: int | None) -> datetime | None:
    return now + timedelta(seconds=expires_in) if expires_in else None
