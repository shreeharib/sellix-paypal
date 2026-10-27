"""The merchant's onboarding answers. Every field is optional: each step can be skipped."""

from typing import Literal

from pydantic import BaseModel, Field

_SHORT = 200
_LONG = 1500


class OnboardingAnswers(BaseModel):
    # Shop
    category: str | None = Field(default=None, max_length=_SHORT)  # bakery, clothing, ...
    area: str | None = Field(default=None, max_length=_SHORT)
    city: str | None = Field(default=None, max_length=_SHORT)
    address: str | None = Field(default=None, max_length=_LONG)
    hours: str | None = Field(default=None, max_length=_SHORT)  # e.g. "Tue–Sun, 9 am – 8 pm"
    weekly_off: str | None = Field(default=None, max_length=_SHORT)
    # What you sell, in plain words (no prices or quantities)
    products: str | None = Field(default=None, max_length=_LONG)
    # Agent persona
    intro: str | None = Field(default=None, max_length=_SHORT)
    tone: Literal["friendly", "formal"] | None = None
    emoji: bool | None = None
    address_customers: str | None = Field(default=None, max_length=_SHORT)
    # Policies and FAQs
    fulfilment: str | None = Field(default=None, max_length=_LONG)
    custom_orders: str | None = Field(default=None, max_length=_LONG)
    cancellations: str | None = Field(default=None, max_length=_LONG)
    never_promise: str | None = Field(default=None, max_length=_LONG)
    faqs: str | None = Field(default=None, max_length=_LONG)
    # Payments
    upi_id: str | None = Field(default=None, max_length=_SHORT)
