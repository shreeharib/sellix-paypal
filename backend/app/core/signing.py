"""Short-lived signed values, such as OAuth `state`: HMAC-SHA256 over a JSON payload."""

import base64
import hashlib
import hmac
import json
import secrets
import time
from typing import Any

from app.core.config import get_settings


class InvalidSignature(ValueError):
    pass


def sign(data: dict[str, str], *, ttl_seconds: int) -> str:
    payload = {**data, "exp": int(time.time()) + ttl_seconds, "nonce": secrets.token_urlsafe(8)}
    body = _encode(json.dumps(payload, separators=(",", ":"), sort_keys=True).encode())
    return f"{body}.{_encode(_mac(body))}"


def verify(token: str) -> dict[str, Any]:
    body, _, mac = token.partition(".")
    if not body or not mac or not hmac.compare_digest(_encode(_mac(body)), mac):
        raise InvalidSignature("Signature doesn't match")
    try:
        payload: dict[str, Any] = json.loads(_decode(body))
    except ValueError as exc:
        raise InvalidSignature("Malformed payload") from exc
    if int(payload.get("exp", 0)) < time.time():
        raise InvalidSignature("Expired")
    return payload


def _mac(body: str) -> bytes:
    secret = get_settings().oauth_state_secret
    if not secret:
        raise InvalidSignature("OAUTH_STATE_SECRET is not set")
    return hmac.new(secret.encode(), body.encode(), hashlib.sha256).digest()


def _encode(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def _decode(text: str) -> bytes:
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))
