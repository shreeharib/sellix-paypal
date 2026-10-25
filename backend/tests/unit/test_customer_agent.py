import pytest

from app.modules.agent import customer_agent
from app.modules.agent.schemas import DEFAULT_OWNER_QUESTION
from app.modules.inventory.schemas import StockItem

STOCK = [
    StockItem("Scoop cookie", "Chocolate", 6000, "INR", 8),
    StockItem("Scoop cookie", "Red velvet", 7050, "INR", 0),
    StockItem("Brownie", None, 9000, "INR", 15),
]


def test_prompt_lists_stock_with_prices_and_sold_out_items() -> None:
    prompt = customer_agent.build_system_prompt("# Sweet Crumbs\nOpen 9-8.", STOCK)

    assert "# Sweet Crumbs" in prompt
    assert "- Scoop cookie (Chocolate): ₹60, 8 left" in prompt
    assert "- Scoop cookie (Red velvet): sold out" in prompt
    assert "- Brownie: ₹90, 15 left" in prompt
    assert '"quote_order"' in prompt and '"place_order"' in prompt
    assert customer_agent.PAYMENT_LINK_PLACEHOLDER in prompt


def test_prompt_without_profile_or_stock_says_so() -> None:
    prompt = customer_agent.build_system_prompt(None, [])

    assert "No shop profile has been written yet." in prompt
    assert "Nothing has been added to today's stock yet." in prompt


def test_action_output_is_parsed() -> None:
    reply = customer_agent.parse_output(
        '{"reply": "", "language": "ta-en", "needs_owner": false, "action": {"type":'
        ' "quote_order", "order": {"items": [{"product": "Scoop cookie", "variant":'
        ' "Chocolate", "quantity": 2}], "fulfilment": "pickup"}}}'
    )

    assert reply.action is not None
    assert reply.action.type == "quote_order"
    assert reply.action.order.items[0].quantity == 2


def test_empty_reply_without_action_is_rejected() -> None:
    with pytest.raises(customer_agent.AgentOutputError):
        customer_agent.parse_output('{"reply": "  ", "language": "en", "needs_owner": false}')


def test_valid_output_is_parsed() -> None:
    reply = customer_agent.parse_output(
        '{"reply": "Chocolate-a red velvet-a?", "language": "ta-en",'
        ' "needs_owner": false, "owner_question": "ignored"}'
    )

    assert reply.reply == "Chocolate-a red velvet-a?"
    assert reply.language == "ta-en"
    assert reply.owner_question is None


def test_output_in_a_code_fence_is_parsed() -> None:
    reply = customer_agent.parse_output(
        '```json\n{"reply": "Hi!", "language": "en", "needs_owner": false,'
        ' "owner_question": null}\n```'
    )

    assert reply.reply == "Hi!"


def test_owner_question_defaults_when_missing() -> None:
    reply = customer_agent.parse_output(
        '{"reply": "Let me check.", "language": "en", "needs_owner": true, "owner_question": ""}'
    )

    assert reply.owner_question == DEFAULT_OWNER_QUESTION


@pytest.mark.parametrize(
    "raw",
    [
        "Sure, here you go!",
        '{"reply": "", "language": "en", "needs_owner": false}',
        '{"language": "en", "needs_owner": false}',
    ],
)
def test_unusable_output_raises(raw: str) -> None:
    with pytest.raises(customer_agent.AgentOutputError):
        customer_agent.parse_output(raw)
