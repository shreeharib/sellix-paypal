from dataclasses import dataclass
from typing import Literal

from pydantic import BaseModel, Field, model_validator

DEFAULT_OWNER_QUESTION = "The assistant needs your help with this customer."


@dataclass(frozen=True)
class ChatMessage:
    role: Literal["system", "user", "assistant"]
    content: str


@dataclass(frozen=True)
class TurnBrief:
    """What code tells the agent about this turn, besides the chat itself."""

    # Marks the genuine shop-system notes in this turn's history. New every turn and never
    # shown to the customer, so a customer can't type a note the agent will trust.
    system_tag: str


class OrderLineDraft(BaseModel):
    id: str | None = Field(default=None, max_length=20)  # the item's id from today's stock
    product: str | None = Field(default=None, max_length=200)
    variant: str | None = Field(default=None, max_length=200)
    quantity: int = Field(ge=1, le=1000)

    @model_validator(mode="after")
    def _identified(self) -> "OrderLineDraft":
        if not (self.id or "").strip() and not (self.product or "").strip():
            raise ValueError("each item needs its id from today's stock (or a product name)")
        return self


class OrderDraft(BaseModel):
    items: list[OrderLineDraft] = Field(min_length=1, max_length=50)
    fulfilment: Literal["pickup", "delivery"] | None = None
    delivery_address: str | None = Field(default=None, max_length=500)
    needed_by: str | None = Field(default=None, max_length=200)
    notes: str | None = Field(default=None, max_length=500)


class AgentAction(BaseModel):
    """Something the agent asks the system to do before it answers the customer."""

    type: Literal["quote_order", "place_order"]
    order: OrderDraft


class CustomerReply(BaseModel):
    """The agent's structured answer for one step of a customer turn."""

    reply: str = Field(default="", max_length=1000)  # Instagram's text limit
    language: str = Field(min_length=1, max_length=16)  # e.g. "en", "ta-en", "hi-en", "ta"
    needs_owner: bool = False
    owner_question: str | None = Field(default=None, max_length=1000)
    action: AgentAction | None = None

    @model_validator(mode="after")
    def _consistent(self) -> "CustomerReply":
        if self.action is None and not self.reply.strip():
            raise ValueError("reply can't be empty unless an action is requested")
        if self.needs_owner and not (self.owner_question or "").strip():
            self.owner_question = DEFAULT_OWNER_QUESTION
        if not self.needs_owner:
            self.owner_question = None
        return self
