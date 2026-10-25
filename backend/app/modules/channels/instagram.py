"""Instagram API with Instagram login: OAuth, account lookup, webhooks, sending DMs."""

from dataclasses import dataclass, field
from typing import Any
from urllib.parse import urlencode

import httpx2

from app.modules.channels.schemas import IncomingMessage

AUTHORIZE_URL = "https://www.instagram.com/oauth/authorize"
TOKEN_URL = "https://api.instagram.com/oauth/access_token"
GRAPH_URL = "https://graph.instagram.com"
SCOPES = ("instagram_business_basic", "instagram_business_manage_messages")
WEBHOOK_FIELDS = "messages,messaging_postbacks"
MAX_TEXT_LENGTH = 1000  # Instagram's limit for one text message
TIMEOUT_SECONDS = 15


class InstagramAPIError(RuntimeError):
    def __init__(self, status: int, message: str) -> None:
        super().__init__(f"Instagram API error {status}: {message}")
        self.status = status


@dataclass(frozen=True)
class TokenGrant:
    access_token: str = field(repr=False)
    expires_in: int | None  # seconds
    scopes: tuple[str, ...] = ()


@dataclass(frozen=True)
class InstagramAccount:
    account_id: str  # the professional account ID that webhooks use
    username: str


def parse_messages(payload: dict[str, Any]) -> list[IncomingMessage]:
    """Extract DMs (including echoes and story replies); other event types are ignored."""
    if payload.get("object") != "instagram":
        return []

    messages: list[IncomingMessage] = []
    for entry in payload.get("entry", []):
        for event in entry.get("messaging", []):
            message = event.get("message")
            if not message or message.get("is_deleted"):
                continue
            is_echo = bool(message.get("is_echo"))
            sender = event.get("sender", {}).get("id", "")
            recipient = event.get("recipient", {}).get("id", "")
            story = (message.get("reply_to") or {}).get("story") or {}
            messages.append(
                IncomingMessage(
                    channel="instagram",
                    shop_account_id=sender if is_echo else recipient,
                    customer_id=recipient if is_echo else sender,
                    message_id=message.get("mid", ""),
                    text=message.get("text", ""),
                    attachment_types=tuple(
                        attachment.get("type", "unknown")
                        for attachment in message.get("attachments", [])
                    ),
                    story_reply_url=story.get("url"),
                    is_echo=is_echo,
                )
            )
    return messages


def authorize_url(*, app_id: str, redirect_uri: str, state: str) -> str:
    query = {
        "client_id": app_id,
        "redirect_uri": redirect_uri,
        "response_type": "code",
        "scope": ",".join(SCOPES),
        "state": state,
    }
    return f"{AUTHORIZE_URL}?{urlencode(query)}"


async def exchange_code(
    *, app_id: str, app_secret: str, redirect_uri: str, code: str
) -> TokenGrant:
    """Authorization code -> short-lived token."""
    data = await _request(
        "POST",
        TOKEN_URL,
        data={
            "client_id": app_id,
            "client_secret": app_secret,
            "grant_type": "authorization_code",
            "redirect_uri": redirect_uri,
            "code": code,
        },
    )
    # The response is either flat or wrapped in {"data": [ ... ]}.
    grant = data["data"][0] if isinstance(data.get("data"), list) and data["data"] else data
    permissions = grant.get("permissions") or ""
    scopes = permissions if isinstance(permissions, list) else permissions.split(",")
    return TokenGrant(
        access_token=grant["access_token"],
        expires_in=None,
        scopes=tuple(scope.strip() for scope in scopes if scope.strip()),
    )


async def exchange_long_lived(*, app_secret: str, short_lived_token: str) -> TokenGrant:
    """Short-lived token -> long-lived token (about 60 days)."""
    data = await _request(
        "GET",
        f"{GRAPH_URL}/access_token",
        params={
            "grant_type": "ig_exchange_token",
            "client_secret": app_secret,
            "access_token": short_lived_token,
        },
    )
    return TokenGrant(access_token=data["access_token"], expires_in=data.get("expires_in"))


async def refresh_long_lived(*, token: str) -> TokenGrant:
    """Extend a long-lived token. It must be at least 24 hours old and not expired."""
    data = await _request(
        "GET",
        f"{GRAPH_URL}/refresh_access_token",
        params={"grant_type": "ig_refresh_token", "access_token": token},
    )
    return TokenGrant(access_token=data["access_token"], expires_in=data.get("expires_in"))


async def fetch_account(*, api_version: str, token: str) -> InstagramAccount:
    data = await _request(
        "GET",
        f"{GRAPH_URL}/{api_version}/me",
        params={"fields": "user_id,username"},
        token=token,
    )
    return InstagramAccount(account_id=str(data["user_id"]), username=data.get("username", ""))


async def subscribe_webhooks(*, api_version: str, token: str) -> None:
    """Ask Meta to send this account's messaging events to our webhook."""
    await _request(
        "POST",
        f"{GRAPH_URL}/{api_version}/me/subscribed_apps",
        params={"subscribed_fields": WEBHOOK_FIELDS},
        token=token,
    )


async def send_text(
    *, api_version: str, account_id: str, token: str, recipient_id: str, text: str
) -> str:
    """Send a DM from the shop's account. Returns Instagram's message ID."""
    data = await _request(
        "POST",
        f"{GRAPH_URL}/{api_version}/{account_id}/messages",
        json={"recipient": {"id": recipient_id}, "message": {"text": text[:MAX_TEXT_LENGTH]}},
        token=token,
    )
    return str(data.get("message_id", ""))


async def _request(
    method: str,
    url: str,
    *,
    params: dict[str, str] | None = None,
    data: dict[str, str] | None = None,
    json: dict[str, Any] | None = None,
    token: str | None = None,
) -> dict[str, Any]:
    headers = {"Authorization": f"Bearer {token}"} if token else None
    try:
        async with httpx2.AsyncClient(timeout=TIMEOUT_SECONDS) as client:
            response = await client.request(
                method, url, params=params, data=data, json=json, headers=headers
            )
    except httpx2.HTTPError as exc:
        raise InstagramAPIError(0, f"network error: {exc.__class__.__name__}") from exc
    try:
        body: dict[str, Any] = response.json()
    except ValueError:
        body = {}
    if response.is_error:
        raise InstagramAPIError(response.status_code, _error_message(body) or response.text[:300])
    return body


def _error_message(body: dict[str, Any]) -> str:
    error = body.get("error")
    if isinstance(error, dict):
        return str(error.get("message", ""))
    return str(body.get("error_message", ""))
