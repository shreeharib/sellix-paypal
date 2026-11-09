"""The merchant's onboarding answers. Every field is optional: each step can be skipped."""

from typing import Literal, Self

from pydantic import BaseModel, Field, model_validator

_SHORT = 200
_LONG = 1500


class OnboardingAnswers(BaseModel):
    # Shop
    category: str | None = Field(default=None, max_length=_SHORT)  # bakery, clothing, ...
    # An id from shop_types.yaml; unset, the add-product form follows the category above.
    shop_type: str | None = Field(default=None, max_length=_SHORT)
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


# The add-product form for one kind of shop (templates live in shop_types.yaml) ---------------

StockModeId = Literal["daily", "inventory", "made_to_order", "unlimited"]


class StockModeOption(BaseModel):
    id: StockModeId
    label: str
    hint: str
    asks_shelf_life: bool


class ShelfLifeOption(BaseModel):
    id: str
    label: str
    days: int = Field(ge=1, le=3650)


class DetailField(BaseModel):
    key: str = Field(pattern=r"^[a-z][a-z0-9_]*$")
    label: str
    type: Literal["multi_choice", "text"]
    options: list[str] = Field(default_factory=list)
    note: str = ""

    @model_validator(mode="after")
    def _choices_need_options(self) -> Self:
        if self.type == "multi_choice" and not self.options:
            raise ValueError(f"{self.key}: a multi_choice field needs options")
        return self


class Vocabulary(BaseModel):
    stock_question: str
    example_product: str
    alias_example: str


class ProductSchema(BaseModel):
    """What the add-product form asks one shop (sent to the app as is)."""

    shop_type: str
    label: str
    version: int
    default_stock_mode: StockModeId
    stock_modes: list[StockModeOption] = Field(min_length=1)
    shelf_life_options: list[ShelfLifeOption]
    detail_fields: list[DetailField]
    vocabulary: Vocabulary

    @model_validator(mode="after")
    def _default_is_allowed(self) -> Self:
        if self.default_stock_mode not in {mode.id for mode in self.stock_modes}:
            raise ValueError(f"{self.shop_type}: the default stock mode isn't one of its modes")
        keys = [field.key for field in self.detail_fields]
        if len(keys) != len(set(keys)):
            raise ValueError(f"{self.shop_type}: duplicate detail field keys")
        return self
