"""Request and response types of the /v1 API: the contract the Flutter client is built from."""

import uuid
from datetime import date, datetime
from typing import Any, Literal

from pydantic import BaseModel, Field

from app.modules.shop_profile.schemas import OnboardingAnswers

# Auth -----------------------------------------------------------------------------------------


class InstagramLoginStart(BaseModel):
    code_challenge: str = Field(description="PKCE S256 challenge (base64url, 43 characters)")
    redirect_uri: str = Field(
        description="Where to return after Instagram, e.g. sellix://auth/callback"
    )


class InstagramLoginUrl(BaseModel):
    authorize_url: str


class TokenRequest(BaseModel):
    code: str
    code_verifier: str = Field(min_length=43, max_length=128)


class RefreshRequest(BaseModel):
    refresh_token: str


class Tokens(BaseModel):
    access_token: str
    refresh_token: str
    expires_in: int
    token_type: str = "Bearer"


# Shop -----------------------------------------------------------------------------------------


class Channel(BaseModel):
    channel: str
    username: str | None
    status: str
    token_expires_at: datetime | None


class Merchant(BaseModel):
    id: uuid.UUID
    name: str
    timezone: str
    agent_enabled: bool


class Me(BaseModel):
    user_id: uuid.UUID
    merchant: Merchant
    role: str
    channels: list[Channel]
    onboarding_completed: bool


class MerchantUpdate(BaseModel):
    name: str | None = Field(default=None, max_length=120)
    timezone: str | None = None
    agent_enabled: bool | None = None


class ShopProfile(BaseModel):
    version: int
    content_md: str
    created_at: datetime


class ShopProfileUpdate(BaseModel):
    content_md: str = Field(min_length=1, max_length=8000)


class ShopDeletion(BaseModel):
    confirm_name: str = Field(min_length=1, max_length=120)  # the shop's exact name


# Onboarding -----------------------------------------------------------------------------------


class Onboarding(BaseModel):
    shop_name: str
    answers: OnboardingAnswers
    completed: bool
    channels: list[Channel]
    payments_ready: bool  # online payment links (Razorpay, or the simulator) can be sent


class OnboardingUpdate(BaseModel):
    shop_name: str = Field(min_length=1, max_length=120)
    answers: OnboardingAnswers
    complete: bool = False  # finish the setup; skipped steps can be done later in Settings


# Today ----------------------------------------------------------------------------------------


class StockRow(BaseModel):
    variant_id: uuid.UUID
    product: str
    variant: str | None
    price_minor: int
    currency: str
    opening: int
    restocked: int
    held: int
    sold: int
    counter_sales: int
    available: int
    stock_mode: str = "daily"
    shelf_life_days: int | None = None


class Today(BaseModel):
    business_date: date
    agent_enabled: bool
    stock: list[StockRow]
    open_questions: int
    orders_awaiting_payment: int
    orders_paid: int
    revenue_minor_by_currency: dict[str, int]


class StockLine(BaseModel):
    product: str = Field(min_length=1, max_length=200)
    variant: str | None = Field(default=None, max_length=200)
    price_minor: int = Field(ge=0)
    currency: str = Field(default="INR", pattern=r"^[A-Z]{3}$")
    quantity: int = Field(ge=0, le=100_000)
    # How long the shop can sell it (the app's "How long can you sell it?"). Left out: the
    # product keeps what it has; a new product is a daily item.
    stock_mode: Literal["daily", "inventory", "made_to_order", "unlimited"] | None = None
    shelf_life_days: int | None = Field(default=None, ge=1, le=3650)


class OpeningStock(BaseModel):
    lines: list[StockLine] = Field(min_length=1, max_length=200)


class RestockRequest(BaseModel):
    variant_id: uuid.UUID
    quantity: int = Field(
        gt=0, le=100_000, description="Number of additional units to add to stock"
    )


class SoldOutRequest(BaseModel):
    variant_id: uuid.UUID


class CounterSaleRequest(BaseModel):
    variant_id: uuid.UUID
    quantity: int = Field(
        gt=0, le=100_000, description="Number of units sold at physical store counter"
    )


class CounterSaleResponse(BaseModel):
    variant_id: uuid.UUID
    business_date: date
    quantity_sold: int
    remaining_available: int
    today: Today


class ParseStockTextRequest(BaseModel):
    text: str = Field(min_length=1, max_length=5000, description="Raw stock items text")
    default_currency: str = Field(default="INR", pattern=r"^[A-Z]{3}$")


class YesterdayLeftoverItem(BaseModel):
    variant_id: uuid.UUID
    product: str
    variant: str | None
    price_minor: int
    currency: str
    leftover_quantity: int
    stock_mode: str
    shelf_life_days: int | None


class YesterdayLeftoversResponse(BaseModel):
    business_date: date
    yesterday_date: date
    leftovers: list[YesterdayLeftoverItem]


class RolloverItem(BaseModel):
    variant_id: uuid.UUID
    rollover_quantity: int = Field(
        ge=0, description="Quantity to roll over into today's opening stock"
    )


class RolloverRequest(BaseModel):
    items: list[RolloverItem] = Field(min_length=1)


class RolloverResponse(BaseModel):
    rolled_count: int
    today: Today


# Orders ---------------------------------------------------------------------------------------


class OrderItem(BaseModel):
    product: str
    variant: str | None
    quantity: int
    unit_price_minor: int


class Order(BaseModel):
    id: uuid.UUID
    number: int
    status: str
    currency: str
    total_minor: int
    conversation_id: uuid.UUID | None
    created_at: datetime
    paid_at: datetime | None
    hold_expires_at: datetime | None
    items: list[OrderItem]
    payment_status: str = "unpaid"
    fulfilment_status: str = "unfulfilled"
    fulfilment_method: str | None = "pickup"
    channel: str = "instagram"
    delivery_address: str | None = None
    customer_note: str | None = None
    order_number: str | None = None

    # Backwards-compatibility aliases for API consumers
    fulfilment: str | None = None
    delivery_type: str | None = None
    source_channel: str = "instagram"
    total_amount_minor: int = 0
    needed_by: str | None = None
    notes: str | None = None


class MarkPaidRequest(BaseModel):
    method: Literal["upi", "cash", "card"] = "upi"
    reference_id: str | None = None


class OrderTimelineEvent(BaseModel):
    id: uuid.UUID
    order_id: uuid.UUID
    from_status: str | None
    to_status: str
    triggered_by: str
    comment: str | None
    created_at: datetime


class UpdateOrderStatusRequest(BaseModel):
    status: str = Field(description="Target status: confirmed, ready, delivered, completed, etc.")
    comment: str | None = None


class CancelOrderRequest(BaseModel):
    reason: str | None = Field(default=None, max_length=500)


class PaymentLinkResponse(BaseModel):
    order_id: uuid.UUID
    order_number: int
    payment_method: Literal["razorpay", "upi", "simulator"]
    payment_link: str
    currency: str
    total_minor: int


# Payments -------------------------------------------------------------------------------------


class PaymentAccount(BaseModel):
    """How this shop's customers pay online (Settings > Payments)."""

    provider: Literal["razorpay"] = "razorpay"
    # Where new payment links come from: the shop's own Razorpay account, the server's shared
    # one (not in production), the dev simulator, or nowhere (no online payments).
    source: Literal["own", "shared", "simulator", "none"]
    payments_ready: bool
    connected: bool  # the shop's own account is connected
    key_id_hint: str | None  # rzp_test_••••ab12
    mode: Literal["test", "live"] | None
    # For Razorpay Dashboard > Settings > Webhooks: the address, the secret and the events to tick.
    webhook_url: str | None
    webhook_secret: str | None
    webhook_events: list[str]
    last_webhook_at: datetime | None
    connected_at: datetime | None


class PaymentAccountConnect(BaseModel):
    key_id: str = Field(min_length=1, max_length=64)
    key_secret: str = Field(min_length=1, max_length=128)


class OrderPayment(BaseModel):
    id: uuid.UUID
    provider: str  # razorpay | simulator | upi_manual | cash | manual
    method: str | None  # upi | card | netbanking | wallet | ... | cash; None until paid
    status: str  # created | completed | failed | denied | cancelled | expired | refunded
    amount_minor: int
    currency: str
    fee_minor: int  # Razorpay's fee, when it said
    link: str | None  # the payment link, while it is open
    provider_payment_id: str | None  # Razorpay's pay_... id, or the reference typed in
    paid_at: datetime | None
    created_at: datetime
    test_mode: bool = False  # made with Razorpay test keys: no real money moved


class OrderRefund(BaseModel):
    status: Literal["pending", "completed", "failed"]
    amount_minor: int
    reason: str | None
    provider_refund_id: str | None
    created_at: datetime


class OrderPayments(BaseModel):
    payments: list[OrderPayment]
    refund: OrderRefund | None
    refundable: bool
    # razorpay: the money goes back to the customer automatically; manual: you return it
    # yourself (UPI you confirmed, cash) and sellix records it; simulator: dev payments.
    refund_mode: Literal["razorpay", "manual", "simulator"] | None


# Ask me ---------------------------------------------------------------------------------------


class Question(BaseModel):
    id: uuid.UUID
    conversation_id: uuid.UUID
    question: str
    status: str
    answer: str | None
    created_at: datetime
    answered_at: datetime | None
    # Instagram's 24-hour window for this customer: the Ask me countdown.
    window_closes_at: datetime | None = None
    window_state: Literal["open", "closing", "human_agent_only", "closed"] | None = None
    # How the answer reached the customer: sent | pending_window | human_agent | expired
    answer_delivery: str | None = None
    # The assistant's suggested answers: one tap fills the reply (up to 3).
    suggested_answers: list[str] = Field(default_factory=list)


class Answer(BaseModel):
    answer: str = Field(min_length=1, max_length=1000)
    # "Always answer this way": the agent gives this answer to the same question from now on.
    always: bool = False


class MemoryFact(BaseModel):
    key: str
    value: Any
    updated_at: datetime


# Chats ----------------------------------------------------------------------------------------


class Conversation(BaseModel):
    id: uuid.UUID
    channel: str
    customer_handle: str
    agent_active: bool
    agent_paused_reason: str | None
    last_message_sender: str | None
    last_message_body: str | None
    last_message_at: datetime | None
    # Set while the owner's reply has paused the assistant (agent_paused_reason
    # "merchant_replied"); it answers again from the customer's next message after this.
    agent_paused_until: datetime | None = None


class ChatMessage(BaseModel):
    id: uuid.UUID
    direction: str
    sender: str
    body: str
    status: str
    created_at: datetime


class AgentSwitch(BaseModel):
    active: bool


class MerchantMessageCreate(BaseModel):
    text: str = Field(min_length=1, max_length=1000)


class MerchantMessageSent(BaseModel):
    id: uuid.UUID
    text: str
    status: Literal["queued"] = "queued"
    created_at: datetime


class Rule(BaseModel):
    """A saved "always" answer (Settings > Rules)."""

    id: uuid.UUID
    text: str  # "<question>: <answer>", as the app lists it
    question: str
    answer: str
    created_at: datetime


# Catalog --------------------------------------------------------------------------------------


class ProductVariantDetail(BaseModel):
    id: uuid.UUID
    sku: str | None
    name: str | None
    price_minor: int
    compare_at_price_minor: int | None = None
    cost_price_minor: int | None = None
    currency: str
    stock_mode: str | None = None
    shelf_life_days: int | None = None
    attributes: dict[str, Any] = Field(default_factory=dict)
    is_active: bool


class ProductAliasDetail(BaseModel):
    id: uuid.UUID
    alias_text: str
    confidence_source: str
    created_at: datetime


class ProductDetail(BaseModel):
    id: uuid.UUID
    name: str
    title: str | None = None
    description: str | None = None
    category: str | None = None
    base_image_url: str | None = None
    stock_mode: str
    shelf_life_days: int | None = None
    available_on: date | None = None  # sold on this one day only; None: any day
    order_by_date: date | None = None  # last day to order; None: until the stock is gone
    attributes: dict[str, Any] = Field(default_factory=dict)
    is_active: bool
    variants: list[ProductVariantDetail] = Field(default_factory=list)
    aliases: list[ProductAliasDetail] = Field(default_factory=list)


class ProductUpdate(BaseModel):
    name: str | None = Field(default=None, max_length=200)
    title: str | None = Field(default=None, max_length=200)
    description: str | None = Field(default=None, max_length=2000)
    category: str | None = Field(default=None, max_length=100)
    base_image_url: str | None = Field(default=None, max_length=500)
    attributes: dict[str, Any] | None = None
    # Send null to clear, leave out to keep.
    available_on: date | None = None
    order_by_date: date | None = None
    # false removes the product (off stock lists, menus and the assistant; past orders keep
    # it); true brings it back.
    is_active: bool | None = None


class CreateAliasRequest(BaseModel):
    alias_text: str = Field(min_length=1, max_length=150)


class CatalogSearchItem(BaseModel):
    product_id: uuid.UUID
    product_name: str
    category: str | None = None
    attributes: dict[str, Any] = Field(default_factory=dict)
    matched_alias: str | None = None
    similarity: float = 0.0
    variants: list[ProductVariantDetail] = Field(default_factory=list)


class CatalogSearchResponse(BaseModel):
    query: str
    total_results: int
    items: list[CatalogSearchItem]
