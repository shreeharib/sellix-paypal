"""Request and response types of the /v1 API: the contract the Flutter client is built from."""

import uuid
from datetime import date, datetime
from typing import Literal

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


# Onboarding -----------------------------------------------------------------------------------


class Onboarding(BaseModel):
    shop_name: str
    answers: OnboardingAnswers
    completed: bool
    channels: list[Channel]
    payments_ready: bool  # online payment links (PayPal) can be sent


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
    rollover_quantity: int = Field(ge=0, description="Quantity to roll over into today's opening stock")


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
    fulfilment: str | None
    delivery_address: str | None
    needed_by: str | None
    notes: str | None
    conversation_id: uuid.UUID | None
    created_at: datetime
    paid_at: datetime | None
    hold_expires_at: datetime | None
    items: list[OrderItem]


class CancelOrderRequest(BaseModel):
    reason: str | None = Field(default=None, max_length=500)


class PaymentLinkResponse(BaseModel):
    order_id: uuid.UUID
    order_number: int
    payment_method: Literal["upi", "paypal"]
    payment_link: str
    currency: str
    total_minor: int


# Ask me ---------------------------------------------------------------------------------------


class Question(BaseModel):
    id: uuid.UUID
    conversation_id: uuid.UUID
    question: str
    status: str
    answer: str | None
    created_at: datetime
    answered_at: datetime | None


class Answer(BaseModel):
    answer: str = Field(min_length=1, max_length=1000)


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


class ChatMessage(BaseModel):
    id: uuid.UUID
    direction: str
    sender: str
    body: str
    status: str
    created_at: datetime


class AgentSwitch(BaseModel):
    active: bool
