"""Request and response types of the /v1 API: the contract the Flutter client is built from."""

import uuid
from datetime import date, datetime

from pydantic import BaseModel, Field

from app.modules.merchants.hours import OpeningHours
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
    opening_hours: OpeningHours | None = Field(
        description="Weekly hours in the shop's time zone; a missing day is closed. "
        "Null until set: the agent then can't say whether the shop is open."
    )


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
    opening_hours: OpeningHours | None = Field(
        default=None, description="Replaces the opening hours; send null to clear them"
    )


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
