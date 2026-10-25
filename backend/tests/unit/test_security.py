import pytest
from cryptography.fernet import Fernet

from app.core import crypto, signing
from app.core.config import get_settings


def test_signed_value_round_trips() -> None:
    token = signing.sign({"merchant_id": "m-1"}, ttl_seconds=60)

    assert signing.verify(token)["merchant_id"] == "m-1"


def test_tampered_signed_value_is_rejected() -> None:
    body, _, mac = signing.sign({"merchant_id": "m-1"}, ttl_seconds=60).partition(".")
    forged_body = signing.sign({"merchant_id": "m-2"}, ttl_seconds=60).partition(".")[0]

    with pytest.raises(signing.InvalidSignature):
        signing.verify(f"{forged_body}.{mac}")
    with pytest.raises(signing.InvalidSignature):
        signing.verify(body)


def test_expired_signed_value_is_rejected() -> None:
    with pytest.raises(signing.InvalidSignature, match="Expired"):
        signing.verify(signing.sign({"merchant_id": "m-1"}, ttl_seconds=-1))


def test_encryption_round_trips_and_hides_the_value() -> None:
    ciphertext = crypto.encrypt("ig-access-token")

    assert "ig-access-token" not in ciphertext
    assert crypto.decrypt(ciphertext) == "ig-access-token"


def test_old_key_still_decrypts_after_rotation(monkeypatch: pytest.MonkeyPatch) -> None:
    old_ciphertext = crypto.encrypt("ig-access-token")
    old_key = get_settings().token_encryption_keys
    rotated = f"{Fernet.generate_key().decode()},{old_key}"
    monkeypatch.setattr(get_settings(), "token_encryption_keys", rotated)

    assert crypto.decrypt(old_ciphertext) == "ig-access-token"
    assert crypto.decrypt(crypto.encrypt("new-token")) == "new-token"


def test_missing_encryption_key_is_a_clear_error(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(get_settings(), "token_encryption_keys", "")

    with pytest.raises(crypto.EncryptionError, match="TOKEN_ENCRYPTION_KEYS"):
        crypto.encrypt("x")
