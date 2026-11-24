"""Meta's data-deletion callback: the signed_request is checked before anything is deleted."""

import base64
import hashlib
import hmac
import json
import time
from typing import Any

import pytest

from app.modules.channels import service as channels

SECRET = "test-instagram-app-secret"  # tests/conftest.py


def _encode(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def signed(claims: dict[str, Any], secret: str = SECRET) -> str:
    payload = _encode(json.dumps(claims).encode())
    signature = _encode(hmac.new(secret.encode(), payload.encode(), hashlib.sha256).digest())
    return f"{signature}.{payload}"


GOOD = {"algorithm": "HMAC-SHA256", "issued_at": int(time.time()), "user_id": "17841400000000001"}


def test_a_genuine_request_gives_the_user_id() -> None:
    assert channels.data_deletion_user_id(signed(GOOD)) == "17841400000000001"


def test_the_meta_app_secret_is_accepted_too() -> None:
    assert channels.data_deletion_user_id(signed(GOOD, secret="test-meta-app-secret"))


@pytest.mark.parametrize(
    "request_value",
    [
        "",
        "no-dot",
        "!!!.???",
        signed(GOOD, secret="someone-else"),
        signed({**GOOD, "algorithm": "none"}),
        signed({"algorithm": "HMAC-SHA256"}),  # no user_id
        signed({**GOOD, "issued_at": int(time.time()) - 2 * 24 * 3600}),  # a replay
        signed({**GOOD, "issued_at": None}),
        signed(GOOD).split(".")[0] + "." + _encode(b'{"algorithm":"HMAC-SHA256","user_id":"1"}'),
    ],
)
def test_anything_else_is_refused(request_value: str) -> None:
    with pytest.raises(channels.InvalidSignedRequest):
        channels.data_deletion_user_id(request_value)
