"""Shops' own Razorpay accounts, and which keys a payment uses.

A shop connects its account by entering its key id and key secret in the app. sellix checks them
with Razorpay, stores the secret encrypted, and makes a webhook secret and address for the shop
to paste into Razorpay's dashboard. Webhooks are optional: the settle job asks Razorpay about
every open link each minute, so payments confirm without them, only more slowly.
"""

import secrets
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core import crypto
from app.core.config import get_settings
from app.modules.payments import razorpay
from app.modules.payments.models import PaymentAccount

# What the shop ticks under "Active events" when it adds the webhook in Razorpay's dashboard.
WEBHOOK_EVENTS = (
    "payment_link.paid",
    "payment_link.expired",
    "payment_link.cancelled",
    "payment.failed",
    "refund.processed",
    "refund.failed",
)


@dataclass(frozen=True)
class AccountView:
    """A connected account as the owner sees it (the key secret never leaves the server)."""

    merchant_id: uuid.UUID
    key_id: str
    mode: str
    webhook_url: str
    webhook_secret: str
    verified_at: datetime
    last_webhook_at: datetime | None

    @property
    def key_id_hint(self) -> str:
        return key_id_hint(self.key_id)


def key_id_hint(key_id: str) -> str:
    """rzp_test_••••ab12: enough to recognise the key, not to use it."""
    prefix, _, rest = key_id.rpartition("_")
    return f"{prefix}_••••{rest[-4:]}" if prefix and len(rest) > 4 else "••••"


def shared_credentials() -> razorpay.Credentials | None:
    """The server's own Razorpay keys, when shops without an account may use them."""
    settings = get_settings()
    if not (settings.razorpay_key_id and settings.razorpay_key_secret):
        return None
    if settings.app_env == "prod" and not settings.razorpay_shared_account_in_prod:
        return None
    return razorpay.Credentials(settings.razorpay_key_id, settings.razorpay_key_secret)


def webhook_url(token: str | None = None) -> str:
    base = get_settings().public_base_url.rstrip("/")
    return f"{base}/webhooks/razorpay/{token}" if token else f"{base}/webhooks/razorpay"


async def find(session: AsyncSession, merchant_id: uuid.UUID) -> PaymentAccount | None:
    return await session.scalar(
        select(PaymentAccount).where(
            PaymentAccount.merchant_id == merchant_id, PaymentAccount.provider == "razorpay"
        )
    )


async def by_webhook_token(session: AsyncSession, token: str) -> PaymentAccount | None:
    if not token or len(token) > 100:
        return None
    return await session.scalar(select(PaymentAccount).where(PaymentAccount.webhook_token == token))


def view(account: PaymentAccount) -> AccountView:
    return AccountView(
        merchant_id=account.merchant_id,
        key_id=account.key_id,
        mode=account.mode,
        webhook_url=webhook_url(account.webhook_token),
        webhook_secret=crypto.decrypt(account.webhook_secret_encrypted),
        verified_at=account.verified_at,
        last_webhook_at=account.last_webhook_at,
    )


def credentials(account: PaymentAccount) -> razorpay.Credentials:
    return razorpay.Credentials(account.key_id, crypto.decrypt(account.key_secret_encrypted))


def webhook_secret(account: PaymentAccount) -> str:
    return crypto.decrypt(account.webhook_secret_encrypted)


async def save(
    session: AsyncSession, merchant_id: uuid.UUID, credentials: razorpay.Credentials
) -> PaymentAccount:
    """Store keys Razorpay has already accepted. Reconnecting keeps the webhook address and
    secret, so a shop that re-enters or changes its keys needn't set the webhook up again."""
    mode = credentials.mode
    if mode is None:
        raise ValueError("Not a Razorpay key id")
    now = datetime.now(UTC)
    account = await find(session, merchant_id)
    if account is None:
        account = PaymentAccount(
            merchant_id=merchant_id,
            provider="razorpay",
            key_id=credentials.key_id,
            key_secret_encrypted=crypto.encrypt(credentials.key_secret),
            webhook_secret_encrypted=crypto.encrypt(_new_webhook_secret()),
            webhook_token=_new_webhook_token(),
            mode=mode,
            verified_at=now,
        )
        session.add(account)
    else:
        account.key_id = credentials.key_id
        account.key_secret_encrypted = crypto.encrypt(credentials.key_secret)
        account.mode = mode
        account.verified_at = now
        account.updated_at = now
    await session.flush()
    return account


async def rotate_webhook_secret(session: AsyncSession, merchant_id: uuid.UUID) -> PaymentAccount:
    account = await find(session, merchant_id)
    if account is None:
        raise LookupError("No Razorpay account connected")
    account.webhook_secret_encrypted = crypto.encrypt(_new_webhook_secret())
    account.updated_at = datetime.now(UTC)
    await session.flush()
    return account


async def remove(session: AsyncSession, merchant_id: uuid.UUID) -> bool:
    result = await session.execute(
        delete(PaymentAccount).where(
            PaymentAccount.merchant_id == merchant_id, PaymentAccount.provider == "razorpay"
        )
    )
    return bool(getattr(result, "rowcount", 0))


async def note_webhook(session: AsyncSession, account_id: uuid.UUID) -> None:
    account = await session.get(PaymentAccount, account_id)
    if account is not None:
        account.last_webhook_at = datetime.now(UTC)


async def credentials_for(
    session: AsyncSession, merchant_id: uuid.UUID
) -> razorpay.Credentials | None:
    """The keys a new payment link for this shop is made with: its own, else the shared ones."""
    account = await find(session, merchant_id)
    if account is not None:
        return credentials(account)
    return shared_credentials()


async def credentials_for_key(
    session: AsyncSession, merchant_id: uuid.UUID, key_id: str | None
) -> razorpay.Credentials | None:
    """The keys to look up an existing payment with: the ones it was made with (its row records
    the key id), else the shop's current keys. A shop that regenerated its key gets a new key id,
    and the new key still reads the links of the same Razorpay account."""
    account = await find(session, merchant_id)
    own = credentials(account) if account is not None else None
    shared = shared_credentials()
    for candidate in (own, shared):
        if candidate is not None and (key_id is None or candidate.key_id == key_id):
            return candidate
    return own


def _new_webhook_secret() -> str:
    return secrets.token_urlsafe(24)


def _new_webhook_token() -> str:
    return secrets.token_urlsafe(18)
