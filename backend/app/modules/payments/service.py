"""Public interface of the payments module: payment links, payment confirmation, refunds, and
each shop's Razorpay account.

An order counts as paid only when Razorpay's own record says so: never from a screenshot, and
never from a webhook body or the customer's return to our page alone. Those only say which link
to look up; the link is then fetched from Razorpay with the shop's keys.
"""

import dataclasses
import math
import time
import uuid
from collections.abc import Mapping
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any, Literal

import structlog
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.db import session_scope
from app.core.locks import advisory_lock
from app.modules.merchants import service as merchants
from app.modules.orders import service as orders
from app.modules.orders.schemas import (
    OrderSummary,
    PaymentResult,
    PlacedOrder,
    RefundStatus,
    RefundTicket,
)
from app.modules.payments import accounts, razorpay, simulator, upi
from app.modules.payments.models import Payment
from app.modules.shop_profile import service as shop_profile

log = structlog.get_logger()

RazorpayError = razorpay.RazorpayError
RAZORPAY_SIGNATURE_HEADER = razorpay.SIGNATURE_HEADER
RAZORPAY_EVENT_ID_HEADER = razorpay.EVENT_ID_HEADER
WEBHOOK_EVENTS = accounts.WEBHOOK_EVENTS
RAZORPAY = "razorpay"

# Razorpay's payment methods, as stored (anything new is "other").
_METHODS = frozenset(
    {"upi", "card", "netbanking", "wallet", "emi", "cardless_emi", "paylater", "bank_transfer"}
)
_PAID_ORDER_STATUSES = frozenset({"paid", "completed", "confirmed", "ready", "delivered"})


class PaymentUnavailable(RuntimeError):
    """No online payment for this order; the message says why (for logs and the merchant)."""


class AccountKeysRejected(ValueError):
    """The key id or key secret is malformed, or Razorpay didn't accept them."""


class ProviderUnreachable(RuntimeError):
    """Razorpay couldn't be reached or failed; trying again later may work."""


RetryReason = Literal["not_payable", "too_many_attempts", "window_over", "cooldown"]


class RetryRefused(RuntimeError):
    """A new payment link isn't allowed for this order: for now (cooldown) or at all."""

    def __init__(self, reason: RetryReason, wait_seconds: int = 0) -> None:
        super().__init__(f"No new payment link: {reason}")
        self.reason: RetryReason = reason
        self.wait_seconds = wait_seconds


@dataclass(frozen=True)
class RetryStatus:
    """Whether the customer may have another payment link for an unpaid order."""

    can_retry: bool  # a new link is allowed now, or will be once `wait_seconds` have passed
    wait_seconds: int  # cooldown left after a failed payment; 0: ask now
    attempts_left: int  # links still allowed for this order, counting from now
    reason: RetryReason | None  # why not, when `can_retry` is False


@dataclass(frozen=True)
class PaymentFailed:
    """A payment try failed; the order is still waiting for payment.

    `link` is set when the same link still takes payments (Razorpay): the customer just tries
    again on it. Without it (the simulator's Reject), a new link is needed.
    """

    order_id: uuid.UUID
    number: int
    conversation_id: uuid.UUID | None
    outcome: Literal["payment_failed"] = "payment_failed"
    link: str | None = None


RefundMode = Literal["razorpay", "manual", "simulator"]


@dataclass(frozen=True)
class RefundOutcome:
    order_id: uuid.UUID
    refund_id: str
    amount_minor: int
    currency: str
    status: RefundStatus
    mode: RefundMode


LinkMethod = Literal["razorpay", "upi", "simulator"]


@dataclass(frozen=True)
class OrderPaymentLink:
    order_id: uuid.UUID
    order_number: int
    payment_method: LinkMethod
    payment_link: str
    currency: str
    total_minor: int


@dataclass(frozen=True)
class Checkout:
    """A payment link the customer pays at `url`."""

    url: str
    provider: Literal["razorpay", "simulator"]


PaymentSource = Literal["own", "shared", "simulator", "none"]


@dataclass(frozen=True)
class AccountStatus:
    """How this shop's customers pay online, for Settings > Payments."""

    source: PaymentSource  # where new payment links come from
    account: accounts.AccountView | None  # the shop's own Razorpay account, if connected
    # Payments found while closing the old account's open links (the caller tells the customers).
    settled: tuple["PaymentResult | PaymentFailed", ...] = ()

    @property
    def payments_ready(self) -> bool:
        return self.source != "none"


@dataclass(frozen=True)
class PaymentView:
    id: uuid.UUID
    provider: str
    method: str | None
    status: str
    amount_minor: int
    currency: str
    fee_minor: int
    link: str | None
    provider_payment_id: str | None
    paid_at: datetime | None
    created_at: datetime
    test_mode: bool  # made with Razorpay test keys: no real money moved


@dataclass(frozen=True)
class RefundView:
    status: str
    amount_minor: int
    reason: str | None
    provider_refund_id: str | None
    created_at: datetime


@dataclass(frozen=True)
class OrderPayments:
    payments: list[PaymentView]
    refund: RefundView | None
    refundable: bool
    refund_mode: RefundMode | None  # how a refund of this order would work


@dataclass(frozen=True)
class WebhookSender:
    """Whose secret checked a webhook delivery: a shop's account, or the shared keys (None)."""

    account_id: uuid.UUID | None
    merchant_id: uuid.UUID | None

    @property
    def tag(self) -> str:
        return str(self.account_id) if self.account_id else "shared"


@dataclass(frozen=True)
class ReturnCheck:
    """The customer's browser came back from Razorpay's page."""

    genuine: bool
    paid: bool
    result: PaymentResult | PaymentFailed | None = None
    shop_name: str | None = None
    order_number: int | None = None


SIMULATOR_SOURCE = simulator.SOURCE  # the webhook inbox's name for the simulator
SIMULATOR_SIGNATURE_HEADER = simulator.SIGNATURE_HEADER


def simulator_enabled() -> bool:
    """Whether the built-in payment simulator is on (never in production)."""
    return simulator.enabled()


def verify_simulator_webhook(body: bytes, signature: str) -> bool:
    return simulator.verify(body, signature)


def accepts(currency: str) -> bool:
    """Whether a payment link can be offered in this currency (if the shop has an account)."""
    return simulator.enabled() or currency in razorpay.SUPPORTED_CURRENCIES


# ---------------------------------------------------------------------------------------------
# The shop's Razorpay account


async def account_status(merchant_id: uuid.UUID) -> AccountStatus:
    async with session_scope() as session:
        account = await accounts.find(session, merchant_id)
        own = accounts.view(account) if account is not None else None
    if simulator.enabled():
        source: PaymentSource = "simulator"
    elif own is not None:
        source = "own"
    elif accounts.shared_credentials() is not None:
        source = "shared"
    else:
        source = "none"
    return AccountStatus(source=source, account=own)


async def ready_for(merchant_id: uuid.UUID) -> bool:
    """Whether this shop's customers can be sent a payment link at all."""
    return (await account_status(merchant_id)).payments_ready


async def connect_account(merchant_id: uuid.UUID, *, key_id: str, key_secret: str) -> AccountStatus:
    """Check the keys with Razorpay, then keep them (the secret encrypted)."""
    key_id, key_secret = key_id.strip(), key_secret.strip()
    if not razorpay.looks_like_key_id(key_id):
        raise AccountKeysRejected(
            "That isn't a Razorpay Key ID. It starts with rzp_test_ or rzp_live_."
        )
    if not razorpay.looks_like_key_secret(key_secret):
        raise AccountKeysRejected("That doesn't look like a Razorpay Key Secret.")
    if get_settings().razorpay_live_keys_only and razorpay.mode_of(key_id) != "live":
        raise AccountKeysRejected(
            "This server takes live keys only (they start with rzp_live_): with test keys, "
            "customers could 'pay' with Razorpay's test cards and no money would move."
        )
    credentials = razorpay.Credentials(key_id, key_secret)
    try:
        await razorpay.check_keys(credentials)
    except razorpay.RazorpayError as exc:
        if exc.retryable:
            raise ProviderUnreachable("Couldn't reach Razorpay. Try again in a minute.") from exc
        raise AccountKeysRejected(
            "Razorpay didn't accept these keys. Check the Key ID and Key Secret, and that both "
            "are from the same mode (test or live)."
        ) from exc
    async with session_scope() as session:
        current = await accounts.find(session, merchant_id)
        old = accounts.credentials(current) if current is not None else None
    settled: list[PaymentResult | PaymentFailed] = []
    if old is not None and old.key_id != credentials.key_id:
        # Links made with the old keys can't be checked once they're replaced (if the shop moved
        # to another Razorpay account): end them now, recording any the customer already paid.
        settled = await _close_open_links(merchant_id, old)
    async with session_scope() as session:
        await accounts.save(session, merchant_id, credentials)
    log.info("payments.account_connected", merchant_id=str(merchant_id), mode=credentials.mode)
    status = await account_status(merchant_id)
    return dataclasses.replace(status, settled=tuple(settled))


async def disconnect_account(merchant_id: uuid.UUID) -> list[PaymentResult | PaymentFailed]:
    """Forget the shop's keys, after ending its open links (paid ones are recorded and
    returned, so the caller can tell those customers)."""
    async with session_scope() as session:
        current = await accounts.find(session, merchant_id)
        old = accounts.credentials(current) if current is not None else None
    settled = await _close_open_links(merchant_id, old) if old is not None else []
    async with session_scope() as session:
        removed = await accounts.remove(session, merchant_id)
    if removed:
        log.info("payments.account_disconnected", merchant_id=str(merchant_id))
    return settled


async def _close_open_links(
    merchant_id: uuid.UUID, credentials: razorpay.Credentials
) -> list[PaymentResult | PaymentFailed]:
    """Cancel the shop's open Razorpay links made with these keys; record any already paid."""
    async with session_scope() as session:
        rows = list(
            (
                await session.execute(
                    select(Payment.id, Payment.provider_order_id).where(
                        Payment.merchant_id == merchant_id,
                        Payment.provider == RAZORPAY,
                        Payment.status == "created",
                        Payment.provider_account == credentials.key_id,
                        Payment.provider_order_id.is_not(None),
                    )
                )
            ).all()
        )
    settled: list[PaymentResult | PaymentFailed] = []
    for payment_id, link_id in rows:
        if link_id is None:
            continue
        try:
            link = await razorpay.fetch_link(credentials, link_id)
            if link.status == "created":
                link = await _cancel(credentials, link)
            result = await _apply_link(payment_id, link, credentials)
        except razorpay.RazorpayError as exc:
            log.warning("payments.close_link_failed", link_id=link_id, error=str(exc))
            continue
        if result is not None:
            settled.append(result)
    return settled


async def rotate_webhook_secret(merchant_id: uuid.UUID) -> AccountStatus:
    async with session_scope() as session:
        await accounts.rotate_webhook_secret(session, merchant_id)
    return await account_status(merchant_id)


def shared_webhook_url() -> str:
    return accounts.webhook_url()


# ---------------------------------------------------------------------------------------------
# Payment links


def create_upi_checkout(placed: PlacedOrder, *, vpa: str, shop_name: str) -> str:
    """The standard UPI link for an INR order. Nobody can see whether it was paid: the shop
    confirms the payment by hand (Mark paid)."""
    return upi.create_upi_link(
        vpa=vpa,
        payee_name=shop_name,
        amount_minor=placed.total_minor,
        order_number=placed.number,
        currency=placed.currency,
    )


async def create_checkout(placed: PlacedOrder, *, shop_name: str) -> str:
    """The link the customer pays this order at (see start_checkout)."""
    return (await start_checkout(placed, shop_name=shop_name)).url


async def start_checkout(placed: PlacedOrder, *, shop_name: str) -> Checkout:
    """The payment link for an order: the one already open, else a new one.

    Asking again while a link is open (the customer wants it resent) returns that link, so an
    order never has two links taking money. A new link is refused (RetryRefused) during the
    cooldown after a rejected payment, once the order has used all its links, and after its hold
    has run out. Raises PaymentUnavailable when the shop has no Razorpay account.

    One order's links are made one at a time (the agent and the owner's "payment link" button
    can ask at the same moment): the second asker waits, then gets the first one's link.
    """
    async with advisory_lock("checkout", str(placed.order_id), wait_seconds=30) as held:
        if not held:
            raise PaymentUnavailable("Another payment link for this order is still being made")
        return await _checkout(placed, shop_name=shop_name)


async def _checkout(placed: PlacedOrder, *, shop_name: str) -> Checkout:
    simulated = simulator.enabled()
    async with session_scope() as session:
        order = await orders.get_order(session, placed.order_id)
        if order is None or order.merchant_id is None:
            raise LookupError(f"No order {placed.order_id}")
        attempts = await _attempts(session, placed.order_id)
        credentials = (
            None if simulated else await accounts.credentials_for(session, order.merchant_id)
        )
    if not simulated:
        if credentials is None:
            raise PaymentUnavailable("Razorpay isn't connected for this shop")
        if placed.currency not in razorpay.SUPPORTED_CURRENCIES:
            raise PaymentUnavailable(f"Razorpay links are offered in rupees, not {placed.currency}")
        if get_settings().razorpay_live_keys_only and credentials.mode != "live":
            raise PaymentUnavailable("This server takes live Razorpay keys only")
    current_key = credentials.key_id if credentials is not None else None
    open_attempt = next(
        (
            a
            for a in reversed(attempts)
            if a.status in ("created", "approved")
            and a.approve_url
            and (a.provider != RAZORPAY or a.provider_account == current_key)
        ),
        None,
    )
    if open_attempt is not None and open_attempt.approve_url:
        provider: Literal["razorpay", "simulator"] = (
            "simulator" if open_attempt.provider == simulator.PROVIDER else "razorpay"
        )
        return Checkout(open_attempt.approve_url, provider)
    if attempts:
        status = _retry_policy(order, attempts, datetime.now(UTC))
        if not status.can_retry or status.wait_seconds > 0:
            raise RetryRefused(status.reason or "cooldown", status.wait_seconds)
    if simulated:
        return await _start_simulated_checkout(placed)
    assert credentials is not None
    return await _start_razorpay_checkout(placed, order, credentials, shop_name=shop_name)


async def _start_razorpay_checkout(
    placed: PlacedOrder,
    order: OrderSummary,
    credentials: razorpay.Credentials,
    *,
    shop_name: str,
) -> Checkout:
    settings = get_settings()
    payment_id = uuid.uuid4()
    hold_ends = order.hold_expires_at or datetime.now(UTC) + timedelta(
        minutes=settings.payment_hold_minutes
    )
    # Razorpay wants 15+ minutes; once the hold is over the settle job cancels the link.
    expire_by = max(
        int(hold_ends.timestamp()), int(time.time()) + razorpay.MIN_LINK_LIFETIME_SECONDS
    )
    base_url = settings.public_base_url.rstrip("/")
    try:
        link = await razorpay.create_link(
            credentials,
            amount_minor=placed.total_minor,
            currency=placed.currency,
            reference_id=f"SX{placed.number}-{payment_id.hex[:12]}",
            description=f"{shop_name} order #{placed.number}",
            expire_by=expire_by,
            callback_url=f"{base_url}/payments/razorpay/return",
            notes={
                "sellix_order_id": str(placed.order_id),
                "sellix_payment_id": str(payment_id),
                "order_number": str(placed.number),
            },
        )
    except razorpay.RazorpayError as exc:
        raise PaymentUnavailable(str(exc)) from exc
    if not link.id or not link.short_url:
        raise PaymentUnavailable("Razorpay returned no payment link")
    async with session_scope() as session:
        session.add(
            Payment(
                id=payment_id,
                merchant_id=order.merchant_id,
                order_id=order.id,
                provider=RAZORPAY,
                method=None,
                provider_order_id=link.id,
                provider_checkout_id=link.order_id or None,
                provider_account=credentials.key_id,
                status="created",
                currency=placed.currency,
                amount_minor=placed.total_minor,
                approve_url=link.short_url,
            )
        )
    log.info("payments.link_created", order_id=str(placed.order_id), link_id=link.id)
    return Checkout(link.short_url, "razorpay")


async def _start_simulated_checkout(placed: PlacedOrder) -> Checkout:
    """A link to this server's own Accept / Reject page."""
    payment_id = uuid.uuid4()
    url = f"{get_settings().public_base_url.rstrip('/')}/payments/simulator/{payment_id}"
    async with session_scope() as session:
        order = await orders.get_order(session, placed.order_id)
        if order is None or order.merchant_id is None:
            raise LookupError(f"No order {placed.order_id}")
        session.add(
            Payment(
                id=payment_id,
                merchant_id=order.merchant_id,
                order_id=order.id,
                provider=simulator.PROVIDER,
                method="simulator",
                provider_order_id=f"SIM-{payment_id.hex[:16]}",
                status="created",
                currency=placed.currency,
                amount_minor=placed.total_minor,
                approve_url=url,
            )
        )
    return Checkout(url, "simulator")


async def _attempts(session: AsyncSession, order_id: uuid.UUID) -> list[Payment]:
    """Every payment link made for this order, oldest first."""
    return list(
        await session.scalars(
            select(Payment)
            .where(
                Payment.order_id == order_id,
                Payment.provider.in_((RAZORPAY, simulator.PROVIDER)),
                Payment.provider_order_id.is_not(None),
            )
            .order_by(Payment.created_at)
        )
    )


def _retry_policy(
    order: OrderSummary | None, attempts: list[Payment], now: datetime
) -> RetryStatus:
    """May the customer have another payment link, and if not yet, how long until they may?

    The rules: the order must still be waiting for payment and held; at most
    PAYMENT_MAX_ATTEMPTS links in all; and PAYMENT_RETRY_COOLDOWN_SECONDS after a rejected payment
    before the next one. The hold (PAYMENT_HOLD_MINUTES) is the retry window.
    """
    settings = get_settings()
    left = max(settings.payment_max_attempts - len(attempts), 0)
    if order is None or order.status != "awaiting_payment":
        return RetryStatus(False, 0, left, "not_payable")
    if left == 0:
        return RetryStatus(False, 0, 0, "too_many_attempts")
    window_ends = order.hold_expires_at
    if window_ends is not None and window_ends <= now:
        return RetryStatus(False, 0, left, "window_over")
    wait = 0
    last = attempts[-1] if attempts else None
    if last is not None and last.status in ("denied", "failed"):
        ready_at = last.updated_at + timedelta(seconds=settings.payment_retry_cooldown_seconds)
        wait = max(math.ceil((ready_at - now).total_seconds()), 0)
        if window_ends is not None and now + timedelta(seconds=wait) >= window_ends:
            return RetryStatus(False, 0, left, "window_over")
    return RetryStatus(True, wait, left, None)


async def retry_status(order_id: uuid.UUID) -> RetryStatus:
    """Where an order stands on getting another payment link (see `_retry_policy`)."""
    async with session_scope() as session:
        order = await orders.get_order(session, order_id)
        attempts = await _attempts(session, order_id)
    return _retry_policy(order, attempts, datetime.now(UTC))


async def open_link(order_id: uuid.UUID) -> str | None:
    """The order's payment link if Razorpay says it still takes payments, else None."""
    async with session_scope() as session:
        order = await orders.get_order(session, order_id)
        if order is None or order.status != "awaiting_payment":
            return None
        attempts = [a for a in await _attempts(session, order_id) if a.status == "created"]
        last = attempts[-1] if attempts else None
        if last is None or last.provider != RAZORPAY or not last.provider_order_id:
            return None
        credentials = await accounts.credentials_for_key(
            session, last.merchant_id, last.provider_account
        )
    if credentials is None:
        return None
    try:
        link = await razorpay.fetch_link(credentials, last.provider_order_id)
    except razorpay.RazorpayError as exc:
        log.warning("payments.link_lookup_failed", order_id=str(order_id), error=str(exc))
        return last.approve_url  # can't tell: the link most likely still works
    if link.status != "created":
        return None
    return link.short_url or last.approve_url


async def get_order_payment_link(
    order_id: uuid.UUID, *, merchant_id: uuid.UUID
) -> OrderPaymentLink:
    """The payment link for an order, for the owner to share: Razorpay when the shop has an
    account (or the simulator), else the shop's UPI id as a plain UPI link."""
    async with session_scope() as session:
        order = await orders.get_order(session, order_id, merchant_id)
        if order is None:
            raise LookupError(f"No order {order_id}")
        merchant = await merchants.find_merchant(session, merchant_id)
        shop_name = merchant.name if merchant else "Sellix Shop"
        onboarding = await shop_profile.get_onboarding(session, merchant_id)
        vpa = onboarding.answers.get("upi_id") if onboarding and onboarding.answers else None
    if order.status != "awaiting_payment":
        raise RetryRefused("not_payable")
    placed = PlacedOrder(
        order_id=order.id,
        number=order.number,
        currency=order.currency,
        total_minor=order.total_minor,
        hold_minutes=get_settings().payment_hold_minutes,
    )
    link: str | None = None
    method: LinkMethod = "razorpay"
    if accepts(order.currency):
        try:
            checkout = await start_checkout(placed, shop_name=shop_name)
        except PaymentUnavailable as exc:
            log.info("payments.no_online_link", order_id=str(order_id), reason=str(exc))
        else:
            link, method = checkout.url, checkout.provider
    if link is None and order.currency == "INR" and vpa:
        link, method = create_upi_checkout(placed, vpa=vpa, shop_name=shop_name), "upi"
    if link is None:
        raise PaymentUnavailable(
            "Connect Razorpay in Settings > Payments (or add your UPI ID) to send payment links."
        )
    return OrderPaymentLink(
        order_id=order.id,
        order_number=order.number,
        payment_method=method,
        payment_link=link,
        currency=order.currency,
        total_minor=order.total_minor,
    )


# ---------------------------------------------------------------------------------------------
# Confirming payments


async def verify_and_record(
    link_id: str, *, merchant_id: uuid.UUID | None = None
) -> PaymentResult | PaymentFailed | None:
    """Look the link up at Razorpay and apply what it says: the only way an order gets paid.

    Webhooks, the customer's return and the settle job all end here. Razorpay's record must show
    the link paid in full, with our order and payment ids in its notes and our amount; the amount
    then goes to orders.record_payment, which refuses a mismatch and alerts the merchant.
    """
    async with session_scope() as session:
        payment = await _razorpay_payment(session, link_id)
        if payment is None:
            log.warning("payments.unknown_link", link_id=link_id)
            return None
        if merchant_id is not None and payment.merchant_id != merchant_id:
            log.warning("payments.webhook_wrong_shop", link_id=link_id)
            return None
        if payment.status in ("completed", "refunded"):
            return None  # already recorded: a repeated webhook or a second return
        credentials = await accounts.credentials_for_key(
            session, payment.merchant_id, payment.provider_account
        )
        payment_id = payment.id
    if credentials is None:
        log.error("payments.account_missing", link_id=link_id)
        return None
    link = await razorpay.fetch_link(credentials, link_id)
    return await _apply_link(payment_id, link, credentials)


async def _apply_link(
    payment_id: uuid.UUID, link: razorpay.Link, credentials: razorpay.Credentials
) -> PaymentResult | None:
    async with session_scope() as session:
        payment = await session.scalar(
            select(Payment).where(Payment.id == payment_id).with_for_update()
        )
        if payment is None or payment.status in ("completed", "refunded"):
            return None
        if not _link_matches(payment, link):
            log.error("payments.link_verification_failed", link_id=link.id)
            return None
        if link.order_id and not payment.provider_checkout_id:
            payment.provider_checkout_id = link.order_id
        if link.status in ("expired", "cancelled"):
            if payment.status == "created":
                payment.status = link.status
                payment.updated_at = datetime.now(UTC)
            return None
        if link.status != "paid":
            if link.status == "partially_paid":
                log.error("payments.partially_paid_link", link_id=link.id)
            return None
        captured = link.captured_payment
        if captured is None:
            log.warning("payments.paid_link_without_payment", link_id=link.id)
            return None
        order_id = payment.order_id
    # Razorpay says how it was paid and its fee; worth one more look-up, never worth failing for.
    method, fee = captured.method, 0
    try:
        details = await razorpay.fetch_payment(credentials, captured.payment_id)
    except razorpay.RazorpayError as exc:
        log.warning(
            "payments.payment_details_failed", payment_id=captured.payment_id, error=str(exc)
        )
    else:
        method, fee = details.method or method, details.fee_minor
    async with session_scope() as session:
        payment = await session.scalar(
            select(Payment).where(Payment.id == payment_id).with_for_update()
        )
        if payment is None or payment.status in ("completed", "refunded"):
            return None
        now = datetime.now(UTC)
        payment.status = "completed"
        payment.provider_capture_id = captured.payment_id
        payment.method = _method(method)
        payment.fee_minor = fee
        payment.paid_at = now
        payment.updated_at = now
        result = await orders.record_payment(
            session,
            order_id,
            amount_minor=link.amount_paid_minor,
            currency=link.currency,
            actor=RAZORPAY,
        )
    if result.outcome == "already_paid":
        # Real money for an order that was already paid (a second link, or the shop marked it
        # paid by hand): the owner must refund one of the two.
        result = dataclasses.replace(result, outcome="paid_twice")
        log.warning("payments.paid_twice", order_id=str(order_id), link_id=link.id)
    log.info("payments.paid", order_id=str(order_id), link_id=link.id, outcome=result.outcome)
    return result


def _link_matches(payment: Payment, link: razorpay.Link) -> bool:
    """Razorpay's link is the one we made for this payment row."""
    return (
        link.id == payment.provider_order_id
        and link.notes.get("sellix_order_id") == str(payment.order_id)
        and link.notes.get("sellix_payment_id", str(payment.id)) == str(payment.id)
        and link.amount_minor == payment.amount_minor
        and link.currency == payment.currency
    )


def _method(method: str | None) -> str | None:
    if method is None:
        return None
    return method if method in _METHODS else "other"


async def _razorpay_payment(session: AsyncSession, link_id: str) -> Payment | None:
    if not link_id:
        return None
    return await session.scalar(
        select(Payment).where(Payment.provider == RAZORPAY, Payment.provider_order_id == link_id)
    )


async def check_return(
    *,
    link_id: str,
    reference_id: str,
    status: str,
    payment_id: str,
    signature: str,
) -> ReturnCheck:
    """The customer's browser is back from Razorpay: check the signature, then Razorpay itself."""
    async with session_scope() as session:
        payment = await _razorpay_payment(session, link_id)
        if payment is None:
            return ReturnCheck(genuine=False, paid=False)
        credentials = await accounts.credentials_for_key(
            session, payment.merchant_id, payment.provider_account
        )
        order = await orders.get_order(session, payment.order_id)
        merchant = await merchants.find_merchant(session, payment.merchant_id)
        already_paid = payment.status in ("completed", "refunded")
    shop_name = merchant.name if merchant else None
    number = order.number if order else None
    if credentials is None or not razorpay.verify_callback(
        link_id=link_id,
        reference_id=reference_id,
        status=status,
        payment_id=payment_id,
        signature=signature,
        key_secret=credentials.key_secret,
    ):
        log.warning("payments.return_signature_invalid", link_id=link_id)
        return ReturnCheck(genuine=False, paid=False, shop_name=shop_name, order_number=number)
    if already_paid:
        return ReturnCheck(True, True, None, shop_name, number)
    result = await verify_and_record(link_id)
    paid = isinstance(result, PaymentResult) and result.outcome != "amount_mismatch"
    return ReturnCheck(True, paid, result, shop_name, number)


async def settle_open_payments(
    max_age: timedelta = timedelta(days=1),
) -> list[PaymentResult | PaymentFailed]:
    """Each minute: ask Razorpay about every open link, so payments confirm without webhooks.

    A paid link is recorded; an expired or cancelled one is closed; a link whose order is no
    longer waiting for payment (it expired, or the owner cancelled it) is cancelled at Razorpay
    so nobody pays for an order that has let its stock go.
    """
    async with session_scope() as session:
        rows = list(
            (
                await session.execute(
                    select(
                        Payment.id,
                        Payment.provider_order_id,
                        Payment.merchant_id,
                        Payment.provider_account,
                        Payment.order_id,
                    )
                    .where(
                        Payment.provider == RAZORPAY,
                        Payment.status == "created",
                        Payment.created_at > datetime.now(UTC) - max_age,
                        Payment.provider_order_id.is_not(None),
                    )
                    .order_by(Payment.created_at)
                    .limit(500)
                )
            ).all()
        )
    settled: list[PaymentResult | PaymentFailed] = []
    for payment_id, link_id, merchant_id, key_id, order_id in rows:
        if link_id is None:
            continue
        async with session_scope() as session:
            credentials = await accounts.credentials_for_key(session, merchant_id, key_id)
            order = await orders.get_order(session, order_id)
        if credentials is None:
            continue
        try:
            link = await razorpay.fetch_link(credentials, link_id)
            if link.status == "created" and (order is None or order.status != "awaiting_payment"):
                link = await _cancel(credentials, link)
            result = await _apply_link(payment_id, link, credentials)
        except razorpay.RazorpayError as exc:
            log.warning("payments.settle_failed", link_id=link_id, error=str(exc))
            continue
        if result is not None:
            settled.append(result)
    return settled


async def _cancel(credentials: razorpay.Credentials, link: razorpay.Link) -> razorpay.Link:
    """Cancel a link at Razorpay; if it was paid meanwhile, return its paid state instead."""
    try:
        return await razorpay.cancel_link(credentials, link.id)
    except razorpay.RazorpayError as exc:
        if exc.retryable:
            raise
        return await razorpay.fetch_link(credentials, link.id)


# ---------------------------------------------------------------------------------------------
# Manual payments


def record_manual_payment(
    session: AsyncSession,
    *,
    merchant_id: uuid.UUID,
    order_id: uuid.UUID,
    order_number: int,
    currency: str,
    amount_minor: int,
    method: str = "upi",
    reference_id: str | None = None,
) -> None:
    """Record a UPI payment the shop saw itself, or cash at the counter, in the payments ledger."""
    provider = "upi_manual" if method == "upi" else ("cash" if method == "cash" else "manual")
    payment = Payment(
        merchant_id=merchant_id,
        order_id=order_id,
        provider=provider,
        method=method if method in _METHODS or method == "cash" else None,
        kind="full",
        provider_order_id=reference_id or f"MANUAL-{order_number}",
        status="completed",
        currency=currency,
        amount_minor=amount_minor,
        paid_at=datetime.now(UTC),
    )
    session.add(payment)


async def mark_order_paid(
    session: AsyncSession,
    order_id: uuid.UUID,
    *,
    merchant_id: uuid.UUID,
    actor: str = "merchant",
    method: str = "upi",
    reference_id: str | None = None,
) -> PaymentResult:
    """Confirm a manual UPI or counter cash payment and mark the order paid."""
    order = await orders.get_order(session, order_id, merchant_id)
    if order is None:
        raise LookupError(f"No order {order_id}")
    if order.status in ("cancelled", "expired"):
        raise ValueError(f"Cannot mark order as paid when status is '{order.status}'")

    if order.status not in ("paid", "completed", "refunded"):
        record_manual_payment(
            session,
            merchant_id=merchant_id,
            order_id=order.id,
            order_number=order.number,
            currency=order.currency,
            amount_minor=order.total_minor,
            method=method,
            reference_id=reference_id,
        )

    return await orders.record_payment(
        session,
        order_id,
        amount_minor=order.total_minor,
        currency=order.currency,
        actor=actor,
    )


# ---------------------------------------------------------------------------------------------
# An order's payments, for the order screen


async def order_payments(order_id: uuid.UUID, *, merchant_id: uuid.UUID) -> OrderPayments:
    async with session_scope() as session:
        order = await orders.get_order(session, order_id, merchant_id)
        if order is None:
            raise LookupError(f"No order {order_id}")
        rows = list(
            await session.scalars(
                select(Payment)
                .where(Payment.order_id == order_id, Payment.merchant_id == merchant_id)
                .order_by(Payment.created_at)
            )
        )
        refund = await orders.latest_refund(session, order_id)
    views = [
        PaymentView(
            id=row.id,
            provider=row.provider,
            method=row.method,
            status=row.status,
            amount_minor=row.amount_minor,
            currency=row.currency,
            fee_minor=row.fee_minor,
            link=row.approve_url if row.status == "created" else None,
            provider_payment_id=row.provider_capture_id
            if row.provider in (RAZORPAY, simulator.PROVIDER)
            else row.provider_order_id,
            paid_at=row.paid_at,
            created_at=row.created_at,
            test_mode=(row.provider_account or "").startswith("rzp_test_"),
        )
        for row in rows
    ]
    paid = next((row for row in reversed(rows) if row.status in ("completed", "refunded")), None)
    mode = _refund_mode(paid) if paid is not None or _is_paid(order) else None
    open_refund = refund is not None and refund.status in ("pending", "completed")
    return OrderPayments(
        payments=views,
        refund=RefundView(
            status=refund.status,
            amount_minor=refund.amount_minor,
            reason=refund.reason,
            provider_refund_id=refund.provider_refund_id,
            created_at=refund.created_at,
        )
        if refund is not None
        else None,
        refundable=_is_paid(order) and not open_refund,
        refund_mode=mode,
    )


def _is_paid(order: OrderSummary) -> bool:
    return order.payment_status == "paid" or (
        order.status in _PAID_ORDER_STATUSES and order.paid_at is not None
    )


def _refund_mode(paid: Payment | None) -> RefundMode:
    if paid is not None and paid.provider == RAZORPAY:
        return "razorpay"
    if paid is not None and paid.provider == simulator.PROVIDER:
        return "simulator"
    return "manual"


# ---------------------------------------------------------------------------------------------
# Refunds


@dataclass(frozen=True)
class _PaidWith:
    """The Razorpay payment a refund goes back to."""

    row_id: uuid.UUID
    merchant_id: uuid.UUID
    key_id: str | None
    payment_id: str
    amount_minor: int
    currency: str


async def refund_order(
    order_id: uuid.UUID,
    *,
    merchant_id: uuid.UUID,
    reason: str | None = None,
    restock: bool = True,
) -> RefundOutcome:
    """Refund a paid order of this shop in full.

    Paid through Razorpay: the refund is committed as pending before Razorpay is asked, so money
    Razorpay sends back is always on record; its answer settles it, or if that answer is lost,
    the refund webhook or reconcile_refunds does. Paid by hand (UPI the shop saw, cash) or through
    the simulator: the shop returns the money itself and the refund is recorded at once.
    """
    async with session_scope() as session:
        order = await orders.get_order(session, order_id, merchant_id)
        if order is None:
            raise LookupError(f"No order {order_id}")
        paid = await session.scalar(
            select(Payment)
            .where(
                Payment.order_id == order_id,
                Payment.merchant_id == merchant_id,
                Payment.status.in_(("completed", "refunded")),
            )
            .order_by(Payment.created_at.desc())
            .limit(1)
            .with_for_update()
        )
        if paid is None and not _is_paid(order):
            raise RuntimeError("This order hasn't been paid, so there's nothing to refund.")
        mode = _refund_mode(paid)
        ticket = await orders.open_refund(session, order_id, restock=restock, reason=reason)
        if mode != "razorpay":
            await orders.settle_refund(session, ticket.id, status="completed")
            if paid is not None:
                paid.status = "refunded"
                paid.updated_at = datetime.now(UTC)
            return RefundOutcome(
                order_id, str(ticket.id), order.total_minor, order.currency, "completed", mode
            )
        assert paid is not None
        if not paid.provider_capture_id:
            raise RuntimeError("Razorpay's payment id for this order is missing.")
        paid_with = _PaidWith(
            paid.id,
            paid.merchant_id,
            paid.provider_account,
            paid.provider_capture_id,
            paid.amount_minor,
            paid.currency,
        )
    if ticket.status == "completed":
        return RefundOutcome(
            order_id, str(ticket.id), paid_with.amount_minor, paid_with.currency, "completed", mode
        )
    status = await _request_refund(ticket, paid_with)
    return RefundOutcome(
        order_id, str(ticket.id), paid_with.amount_minor, paid_with.currency, status, mode
    )


async def _credentials_for(paid_with: _PaidWith) -> razorpay.Credentials:
    async with session_scope() as session:
        credentials = await accounts.credentials_for_key(
            session, paid_with.merchant_id, paid_with.key_id
        )
    if credentials is None:
        raise RuntimeError(
            "The Razorpay account this order was paid into isn't connected any more. "
            "Reconnect it in Settings > Payments, or refund from Razorpay's dashboard."
        )
    return credentials


async def _request_refund(ticket: RefundTicket, paid_with: _PaidWith) -> RefundStatus:
    """Ask Razorpay to refund the payment and record its answer.

    Every try sends the refund request's own id as the idempotency key and receipt, so retrying
    never refunds twice.
    """
    credentials = await _credentials_for(paid_with)
    key = ticket.id.hex
    try:
        info = await razorpay.create_refund(
            credentials,
            paid_with.payment_id,
            amount_minor=paid_with.amount_minor,
            idempotency_key=key,
            notes={"sellix_order_id": str(ticket.order_id), "reason": (ticket.reason or "")[:200]},
        )
    except razorpay.RazorpayError as exc:
        if exc.retryable:
            log.warning("payments.refund_unconfirmed", refund_id=str(ticket.id), error=str(exc))
            return "pending"
        found = await _refund_by_receipt(credentials, paid_with.payment_id, key)
        if found is None:
            await _record_refund(ticket.id, paid_with.row_id, None, "failed")
            raise RuntimeError(f"Razorpay refused the refund: {exc.description}") from exc
        info = found
    return await _record_refund(ticket.id, paid_with.row_id, info.id, _refund_status(info))


async def _refund_by_receipt(
    credentials: razorpay.Credentials, payment_id: str, receipt: str
) -> razorpay.RefundInfo | None:
    try:
        refunds = await razorpay.payment_refunds(credentials, payment_id)
    except razorpay.RazorpayError:
        return None
    return next((r for r in refunds if r.receipt == receipt), None)


def _refund_status(info: razorpay.RefundInfo) -> RefundStatus:
    if info.status == "processed":
        return "completed"
    if info.status == "failed":
        return "failed"
    return "pending"


async def _record_refund(
    refund_id: uuid.UUID,
    payment_row_id: uuid.UUID,
    provider_refund_id: str | None,
    status: RefundStatus,
) -> RefundStatus:
    async with session_scope() as session:
        if status == "completed":
            payment = await session.scalar(
                select(Payment).where(Payment.id == payment_row_id).with_for_update()
            )
            if payment is not None:
                payment.status = "refunded"
                payment.updated_at = datetime.now(UTC)
        await orders.settle_refund(
            session, refund_id, status=status, provider_refund_id=provider_refund_id
        )
    return status


async def _paid_with(session: AsyncSession, order_id: uuid.UUID) -> _PaidWith | None:
    paid = await session.scalar(
        select(Payment)
        .where(
            Payment.order_id == order_id,
            Payment.provider == RAZORPAY,
            Payment.status.in_(("completed", "refunded")),
        )
        .order_by(Payment.created_at.desc())
        .limit(1)
    )
    if paid is None or not paid.provider_capture_id:
        return None
    return _PaidWith(
        paid.id,
        paid.merchant_id,
        paid.provider_account,
        paid.provider_capture_id,
        paid.amount_minor,
        paid.currency,
    )


async def reconcile_refunds(older_than: timedelta = timedelta(minutes=5)) -> int:
    """Settle refunds still pending after `older_than`; returns how many completed."""
    async with session_scope() as session:
        stuck = [
            (ticket, await _paid_with(session, ticket.order_id))
            for ticket in await orders.pending_refunds(session, older_than=older_than)
        ]
    completed = 0
    for ticket, paid_with in stuck:
        if paid_with is None:
            log.error("payments.refund_without_payment", refund_id=str(ticket.id))
            continue
        try:
            credentials = await _credentials_for(paid_with)
            if ticket.provider_refund_id:
                info = await razorpay.fetch_refund(credentials, ticket.provider_refund_id)
                status = await _record_refund(
                    ticket.id, paid_with.row_id, info.id, _refund_status(info)
                )
            else:
                status = await _request_refund(ticket, paid_with)
        except (razorpay.RazorpayError, RuntimeError) as exc:
            log.warning(
                "payments.refund_reconcile_failed", refund_id=str(ticket.id), error=str(exc)
            )
            continue
        if status == "completed":
            completed += 1
    return completed


async def _refund_reported(entity: Mapping[str, Any], merchant_id: uuid.UUID | None) -> None:
    """Razorpay reports a refund: re-fetch it rather than trusting the event body, and settle a
    pending sellix refund only with the refund sellix asked for (same payment, full amount, our
    receipt): a partial refund made in Razorpay's dashboard settles nothing."""
    refund_id = str(entity.get("id") or "")
    payment_id = str(entity.get("payment_id") or "")
    if not refund_id or not payment_id:
        log.warning("payments.refund_event_incomplete", refund_id=refund_id)
        return
    async with session_scope() as session:
        payment = await session.scalar(
            select(Payment).where(
                Payment.provider == RAZORPAY, Payment.provider_capture_id == payment_id
            )
        )
        if payment is not None and merchant_id is not None and payment.merchant_id != merchant_id:
            log.warning("payments.webhook_wrong_shop", refund_id=refund_id)
            payment = None
        pending = (
            await orders.pending_refunds(session, order_id=payment.order_id) if payment else []
        )
        paid_with = await _paid_with(session, payment.order_id) if payment else None
    if not pending or paid_with is None:
        log.info("payments.refund_event_ignored", refund_id=refund_id)
        return
    info = await razorpay.fetch_refund(await _credentials_for(paid_with), refund_id)
    ticket = next(
        (t for t in pending if t.provider_refund_id in (None, info.id)),
        None,
    )
    if (
        ticket is None
        or info.receipt != ticket.id.hex
        or info.payment_id != paid_with.payment_id
        or info.amount_minor != paid_with.amount_minor
    ):
        log.info("payments.refund_event_unmatched", refund_id=refund_id)
        return
    await _record_refund(ticket.id, paid_with.row_id, info.id, _refund_status(info))


# ---------------------------------------------------------------------------------------------
# Webhooks


async def verify_razorpay_webhook(
    token: str | None, body: bytes, signature: str
) -> WebhookSender | None:
    """Whose secret signed this delivery, or None if nobody's does."""
    if token is not None:
        async with session_scope() as session:
            account = await accounts.by_webhook_token(session, token)
            if account is None:
                return None
            secret = accounts.webhook_secret(account)
            if not razorpay.verify_webhook(body, signature, secret):
                return None
            await accounts.note_webhook(session, account.id)
            return WebhookSender(account.id, account.merchant_id)
    secret = get_settings().razorpay_webhook_secret
    if accounts.shared_credentials() is None or not razorpay.verify_webhook(
        body, signature, secret
    ):
        return None
    return WebhookSender(None, None)


_SENDER = "_sellix_sender"  # added to a stored event: whose webhook delivered it


def stored_event(event: Mapping[str, Any], sender: WebhookSender) -> dict[str, Any]:
    """The event as the inbox keeps it, with the shop whose webhook delivered it."""
    merchant = str(sender.merchant_id) if sender.merchant_id else None
    return {**event, _SENDER: {"merchant_id": merchant}}


def _sender_merchant(event: Mapping[str, Any]) -> uuid.UUID | None:
    raw = (event.get(_SENDER) or {}).get("merchant_id")
    try:
        return uuid.UUID(str(raw)) if raw else None
    except ValueError:
        return None


async def handle_razorpay_event(event: Mapping[str, Any]) -> PaymentResult | PaymentFailed | None:
    """Apply a verified Razorpay webhook. The body only says what to look up; Razorpay decides.

    A delivery to a shop's own webhook address only acts on that shop's payments (an owner sees
    their webhook secret, so could sign events naming another shop's payments).
    """
    name = str(event.get("event") or "")
    payload: Mapping[str, Any] = event.get("payload") or {}
    merchant_id = _sender_merchant(event)

    def entity(key: str) -> Mapping[str, Any]:
        return (payload.get(key) or {}).get("entity") or {}

    if name.startswith("payment_link."):
        link_id = str(entity("payment_link").get("id") or "")
        return await verify_and_record(link_id, merchant_id=merchant_id)
    if name in ("payment.captured", "payment.authorized"):
        link_id = await _link_of(entity("payment"), merchant_id)
        return await verify_and_record(link_id, merchant_id=merchant_id) if link_id else None
    if name == "payment.failed":
        return await _attempt_failed(entity("payment"), merchant_id)
    if name.startswith("refund."):
        await _refund_reported(entity("refund"), merchant_id)
        return None
    log.info("payments.webhook_ignored", event_type=name)
    return None


async def _payment_row(
    session: AsyncSession, entity: Mapping[str, Any], merchant_id: uuid.UUID | None
) -> Payment | None:
    """Our link row for a Razorpay payment: by the notes we put on the link, else by the order.
    With `merchant_id`, only that shop's rows."""
    row = await _find_payment_row(session, entity)
    if row is not None and merchant_id is not None and row.merchant_id != merchant_id:
        log.warning("payments.webhook_wrong_shop", payment_id=str(entity.get("id")))
        return None
    return row


async def _find_payment_row(session: AsyncSession, entity: Mapping[str, Any]) -> Payment | None:
    notes = entity.get("notes")
    raw_id = notes.get("sellix_payment_id") if isinstance(notes, Mapping) else None
    if raw_id:
        try:
            row = await session.get(Payment, uuid.UUID(str(raw_id)))
        except ValueError:
            row = None
        if row is not None and row.provider == RAZORPAY:
            return row
    order_id = str(entity.get("order_id") or "")
    if not order_id:
        return None
    return await session.scalar(
        select(Payment).where(
            Payment.provider == RAZORPAY, Payment.provider_checkout_id == order_id
        )
    )


async def _link_of(entity: Mapping[str, Any], merchant_id: uuid.UUID | None) -> str | None:
    async with session_scope() as session:
        row = await _payment_row(session, entity, merchant_id)
    return row.provider_order_id if row is not None else None


async def _attempt_failed(
    entity: Mapping[str, Any], merchant_id: uuid.UUID | None
) -> PaymentFailed | None:
    """A try failed but the link still takes payments: the customer may be told to try again."""
    async with session_scope() as session:
        row = await _payment_row(session, entity, merchant_id)
        if row is None or row.status != "created":
            return None
        order = await orders.get_order(session, row.order_id)
    if order is None or order.status != "awaiting_payment":
        return None
    log.info("payments.attempt_failed", order_id=str(order.id), reason=entity.get("error_reason"))
    return PaymentFailed(order.id, order.number, order.conversation_id, link=row.approve_url)


# ---------------------------------------------------------------------------------------------
# The simulator


@dataclass(frozen=True)
class SimulatedCheckout:
    """What the simulator's checkout page shows for one payment."""

    payment_id: uuid.UUID
    status: str
    shop_name: str
    order_number: int
    amount_minor: int
    currency: str


async def simulated_checkout(payment_id: uuid.UUID) -> SimulatedCheckout | None:
    async with session_scope() as session:
        payment = await session.get(Payment, payment_id)
        if payment is None or payment.provider != simulator.PROVIDER:
            return None
        order = await orders.get_order(session, payment.order_id)
        if order is None or order.merchant_id is None:
            return None
        merchant = await merchants.find_merchant(session, order.merchant_id)
        return SimulatedCheckout(
            payment_id=payment.id,
            status=payment.status,
            shop_name=merchant.name if merchant else "Sellix Shop",
            order_number=order.number,
            amount_minor=payment.amount_minor,
            currency=payment.currency,
        )


async def handle_simulator_event(event: Mapping[str, Any]) -> PaymentResult | PaymentFailed | None:
    """Apply an Accept or Reject from the simulator's checkout page (its webhook, after the job).

    The payment row decides: only a payment still waiting can be settled, so a replayed delivery
    or a second button press does nothing.
    """
    if not simulator.enabled():
        log.error("payments.simulator_event_while_off")
        return None
    event_type = event.get("event_type")
    resource: Mapping[str, Any] = event.get("resource") or {}
    try:
        payment_id = uuid.UUID(str(resource.get("payment_id", "")))
    except ValueError:
        log.warning("payments.simulator_event_without_payment")
        return None
    async with session_scope() as session:
        payment = await session.scalar(
            select(Payment)
            .where(Payment.id == payment_id, Payment.provider == simulator.PROVIDER)
            .with_for_update()
        )
        if payment is None or payment.status != "created":
            return None  # unknown, or already settled: a repeat does nothing
        if event_type == simulator.ACCEPTED:
            payment.status = "completed"
            payment.provider_capture_id = f"SIMCAP-{payment.id.hex[:12]}"
            payment.paid_at = datetime.now(UTC)
            return await orders.record_payment(
                session,
                payment.order_id,
                amount_minor=payment.amount_minor,
                currency=payment.currency,
                actor="simulator",
            )
        if event_type == simulator.REJECTED:
            payment.status = "denied"
            payment.updated_at = datetime.now(UTC)  # the retry cooldown counts from here
            order = await orders.get_order(session, payment.order_id)
            if order is None:
                return None
            return PaymentFailed(order.id, order.number, order.conversation_id)
    log.info("payments.simulator_event_ignored", event_type=event_type)
    return None
