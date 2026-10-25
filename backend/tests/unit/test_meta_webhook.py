import hashlib
import hmac

from fastapi.testclient import TestClient

from app.main import create_app
from app.webhooks.meta import is_valid_signature

BODY = b'{"object": "instagram", "entry": []}'


def sign(body: bytes, secret: str) -> str:
    return "sha256=" + hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()


def test_handshake_returns_the_challenge() -> None:
    response = TestClient(create_app()).get(
        "/webhooks/meta",
        params={
            "hub.mode": "subscribe",
            "hub.verify_token": "test-verify-token",
            "hub.challenge": "1158201444",
        },
    )

    assert response.status_code == 200
    assert response.text == "1158201444"


def test_handshake_rejects_a_wrong_token() -> None:
    response = TestClient(create_app()).get(
        "/webhooks/meta",
        params={"hub.mode": "subscribe", "hub.verify_token": "wrong", "hub.challenge": "1"},
    )

    assert response.status_code == 403


def test_event_without_a_valid_signature_is_rejected_before_any_storage() -> None:
    client = TestClient(create_app())

    unsigned = client.post("/webhooks/meta", content=BODY)
    forged = client.post(
        "/webhooks/meta", content=BODY, headers={"X-Hub-Signature-256": "sha256=" + "0" * 64}
    )

    assert unsigned.status_code == 401
    assert forged.status_code == 401


def test_signature_from_either_app_secret_is_accepted() -> None:
    assert is_valid_signature(BODY, sign(BODY, "meta-secret"), "meta-secret", "ig-secret")
    assert is_valid_signature(BODY, sign(BODY, "ig-secret"), "meta-secret", "ig-secret")
    assert not is_valid_signature(BODY, sign(BODY, "other"), "meta-secret", "ig-secret")


def test_signature_check_fails_closed_without_secrets() -> None:
    assert not is_valid_signature(BODY, sign(BODY, ""), "", "")
    assert not is_valid_signature(BODY, None, "meta-secret")
