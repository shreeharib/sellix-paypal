"""Encryption at rest for secrets stored in the database, such as channel access tokens.

TOKEN_ENCRYPTION_KEYS holds comma-separated Fernet keys. The first one encrypts; all of them
decrypt, so a key can be rotated by putting the new key first and re-encrypting over time.
"""

from functools import lru_cache

from cryptography.fernet import Fernet, InvalidToken, MultiFernet

from app.core.config import get_settings


class EncryptionError(RuntimeError):
    pass


@lru_cache
def _fernet(keys: str) -> MultiFernet:
    parts = [key.strip() for key in keys.split(",") if key.strip()]
    if not parts:
        raise EncryptionError("TOKEN_ENCRYPTION_KEYS is not set")
    try:
        return MultiFernet([Fernet(key) for key in parts])
    except ValueError as exc:
        raise EncryptionError("TOKEN_ENCRYPTION_KEYS contains an invalid Fernet key") from exc


def encrypt(plaintext: str) -> str:
    return _fernet(get_settings().token_encryption_keys).encrypt(plaintext.encode()).decode()


def decrypt(ciphertext: str) -> str:
    try:
        return _fernet(get_settings().token_encryption_keys).decrypt(ciphertext.encode()).decode()
    except InvalidToken as exc:
        raise EncryptionError("Can't decrypt: wrong key or corrupted value") from exc
