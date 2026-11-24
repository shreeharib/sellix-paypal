import uuid
from datetime import datetime

from sqlalchemy import func, text
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base


class Payment(Base):
    """One payment attempt for an order with a payment provider."""

    __tablename__ = "payments"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, server_default=text("gen_random_uuid()")
    )
    merchant_id: Mapped[uuid.UUID]
    order_id: Mapped[uuid.UUID]
    provider: Mapped[str]  # razorpay | simulator | upi_manual | manual | cash (paypal: old rows)
    # upi | card | netbanking | wallet | emi | ... | cash | simulator; None until the customer pays
    method: Mapped[str | None] = mapped_column(nullable=True, default=None)
    kind: Mapped[str] = mapped_column(server_default=text("'full'"))  # full | deposit | balance
    # Razorpay: the Payment Link id (plink_...)
    provider_order_id: Mapped[str | None] = mapped_column(nullable=True, default=None)
    # Razorpay: the payment id (pay_...), once paid
    provider_capture_id: Mapped[str | None] = mapped_column(nullable=True, default=None)
    # Razorpay: its own order behind the link (order_...), named by payment.failed events
    provider_checkout_id: Mapped[str | None] = mapped_column(nullable=True, default=None)
    # Razorpay: the key id the link was made with
    provider_account: Mapped[str | None] = mapped_column(nullable=True, default=None)
    # created | completed | failed | denied | cancelled | expired | refunded (approved: old rows)
    status: Mapped[str]
    currency: Mapped[str]
    amount_minor: Mapped[int]
    fee_minor: Mapped[int] = mapped_column(server_default=text("0"))
    approve_url: Mapped[str | None] = mapped_column(nullable=True, default=None)
    paid_at: Mapped[datetime | None] = mapped_column(nullable=True, default=None)
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(server_default=func.now())


class PaymentAccount(Base):
    """A shop's own Razorpay account: its keys and the webhook secret sellix made for it."""

    __tablename__ = "payment_accounts"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, server_default=text("gen_random_uuid()")
    )
    merchant_id: Mapped[uuid.UUID]
    provider: Mapped[str] = mapped_column(server_default=text("'razorpay'"))
    key_id: Mapped[str]
    key_secret_encrypted: Mapped[str]
    webhook_secret_encrypted: Mapped[str]
    webhook_token: Mapped[str]
    mode: Mapped[str]  # test | live
    verified_at: Mapped[datetime] = mapped_column(server_default=func.now())
    last_webhook_at: Mapped[datetime | None] = mapped_column(nullable=True, default=None)
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(server_default=func.now())
