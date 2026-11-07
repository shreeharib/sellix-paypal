"""The v1 customer-facing sales agent: prompt, structured output, and validation.

The prompt text lives in prompts/v1/ (see prompt_store).
"""

from pydantic import ValidationError

from app.core.money import format_money
from app.modules.agent import prompt_store
from app.modules.agent.schemas import CustomerReply
from app.modules.inventory.schemas import StockItem

PAYMENT_LINK_PLACEHOLDER = "{payment_link}"
SYSTEM_NOTE_PREFIX = "[Shop system]"


class AgentOutputError(ValueError):
    pass


def build_system_prompt(shop_profile: str | None, stock: list[StockItem]) -> str:
    return prompt_store.render(
        "v1.customer_agent",
        profile=(shop_profile or "").strip(),
        stock=[
            {
                "label": item.label,
                "price": format_money(item.price_minor, item.currency),
                "available": item.available,
            }
            for item in stock
        ],
    )


def system_note(text: str) -> str:
    return f"{SYSTEM_NOTE_PREFIX} {text}"


def parse_output(raw: str) -> CustomerReply:
    text = raw.strip()
    if text.startswith("```"):
        text = text.strip("`").removeprefix("json").strip()
    try:
        return CustomerReply.model_validate_json(text)
    except ValidationError as exc:
        raise AgentOutputError(str(exc)) from exc


def repair_instruction(error: AgentOutputError) -> str:
    return prompt_store.render("v1.repair", error=str(error)[:500])
