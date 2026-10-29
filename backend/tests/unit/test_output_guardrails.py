"""Output guardrails: nothing reaches a customer unless code produced its amounts and links."""

import pytest

from app.modules.agent.guardrails import output
from app.modules.agent.guardrails.output import TokenValues

VALUES = TokenValues(
    prices={"i3f9a2c": "₹60"},
    quote_total="₹120",
    order_total="₹120",
    order_number="#1001",
    payment_link="https://pay.example/abc",
)


def check(text: str, customer: str = "rendu cookie venum", **options: object) -> output.Check:
    return output.check_reply(
        text,
        values=VALUES,
        customer_text=customer,
        health_fields_seen=bool(options.get("health_fields_seen", False)),
        never_promise=tuple(options.get("never_promise", ())),  # pyright: ignore[reportArgumentType]
    )


def test_tokens_are_filled_from_code_values() -> None:
    result = check("Chocolate cookie [[price:i3f9a2c]] each, total [[quote_total]]. Seri-aa?")

    assert result.ok, result.problems
    assert result.text == "Chocolate cookie ₹60 each, total ₹120. Seri-aa?"


def test_the_payment_link_token_is_the_only_link_allowed() -> None:
    result = check("Order [[order_number]] confirmed! Pay here: [[payment_link]]")

    assert result.ok, result.problems
    assert result.text == "Order #1001 confirmed! Pay here: https://pay.example/abc"


@pytest.mark.parametrize(
    "text",
    [
        "Total ₹120 aagum",
        "Total Rs. 120",
        "Total Rs120",
        "120 rupees mothham",
        "100 rupa only",
        "மொத்தம் ரூ.100",
        "कुल रु 100",
        "total 100",
        "mothham 120 aagum",
        "price is 60",
        "That's $12.50",
        "12 USD",
        "INR 120",
    ],
)
def test_amounts_the_model_typed_are_rejected(text: str) -> None:
    result = check(text)

    assert not result.ok
    assert any("amount" in problem for problem in result.problems)


@pytest.mark.parametrize("text", ["2 chocolate cookies-aa?", "Pickup at the shop, 3 left today."])
def test_quantities_are_not_amounts(text: str) -> None:
    assert check(text).ok


@pytest.mark.parametrize(
    "text", ["Pay at http://evil.example/x", "see www.example.com", "visit sweetcrumbs.in"]
)
def test_links_the_model_typed_are_rejected(text: str) -> None:
    result = check(text)

    assert not result.ok
    assert any("link" in problem for problem in result.problems)


@pytest.mark.parametrize(
    "text",
    [
        "Free delivery for you!",
        "I'll give you a 10% discount",
        "Special offer today",
        "We'll deliver in 30 minutes",
        "Delivery within 1 hour",
        "இலவசம் delivery",
    ],
)
def test_promises_are_rejected(text: str) -> None:
    result = check(text)

    assert not result.ok
    assert any("promise" in problem for problem in result.problems)


def test_the_shops_own_never_promise_list_is_enforced() -> None:
    result = check("Same-day delivery is fine", never_promise=("same-day delivery",))

    assert not result.ok


def test_health_claims_need_product_details_from_this_turn() -> None:
    assert not check("Yes, it's eggless!").ok
    assert check("Yes, it's eggless!", health_fields_seen=True).ok


def test_an_unknown_or_empty_token_is_rejected() -> None:
    empty = output.check_reply(
        "Total [[quote_total]]",
        values=TokenValues(),
        customer_text="hi",
        health_fields_seen=False,
        never_promise=(),
    )

    assert not check("Price [[price:nope]]").ok
    assert not check("Hello [[discount]]").ok
    assert not empty.ok


def test_a_reply_in_another_script_than_the_customers_is_rejected() -> None:
    assert not check("Your order is ready!", customer="என் ஆர்டர் தயாரா?").ok
    assert check("உங்கள் ஆர்டர் தயார்!", customer="என் ஆர்டர் தயாரா?").ok
    assert not check("உங்கள் ஆர்டர் தயார்!", customer="is my order ready?").ok
    assert check("Order ready-aa irukku!", customer="order ready-aa?").ok


def test_a_reply_too_long_for_two_messages_is_rejected() -> None:
    assert not check("Cake. " * 400).ok


@pytest.mark.parametrize(
    "text",
    [
        "Let me check with the shop and get back to you",
        "Shop kitta check pannitu solren",
        "Shop-la check panni solren!",
        "Main shop se pooch ke batata hoon",
        "கடையில் கேட்டு சொல்கிறேன்",
    ],
)
def test_promising_to_check_with_the_shop_needs_a_question_to_the_owner(text: str) -> None:
    customer = "கேக் கிடைக்குமா?" if "கடை" in text else "photo cake possible?"
    without = output.check_reply(
        text,
        values=VALUES,
        customer_text=customer,
        health_fields_seen=False,
        never_promise=(),
        owner_asked=False,
    )
    with_question = output.check_reply(
        text,
        values=VALUES,
        customer_text=customer,
        health_fields_seen=False,
        never_promise=(),
        owner_asked=True,
    )

    assert not without.ok and any("ask_shop_owner" in p for p in without.problems)
    assert with_question.ok, with_question.problems
