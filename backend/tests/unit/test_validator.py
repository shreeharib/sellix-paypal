import pytest

from app.modules.agent import templates, validator

FACTS = validator.ReplyFacts(
    amounts_minor=frozenset({6000, 9000, 12000}), customer_text="rendu cookie venum"
)


def problems(reply: str, facts: validator.ReplyFacts = FACTS) -> list[str]:
    return validator.check(reply, facts)


@pytest.mark.parametrize(
    "reply",
    [
        "2 chocolate cookies, total ₹120. Confirm pannalama?",
        "Rs. 60 each, Rs 120 for two.",
        "120 rupees total, pickup at 6 pm?",
        "Brownie is 90/- only.",
        "Here's your payment link: {payment_link}",
        "We open at 9 tomorrow, 2 cookies left!",
        "No discounts, sorry! Prices are fixed.",
    ],
)
def test_good_replies_pass(reply: str) -> None:
    assert problems(reply) == []


@pytest.mark.parametrize(
    ("reply", "problem"),
    [
        ("Total ₹100 for two!", "The amount(s) 100 aren't prices or totals"),
        ("That's $12.50", "The amount(s) 12.50 aren't prices or totals"),
        ("Pay here: https://paypal.me/sweetcrumbs", "Don't write links"),
        ("Pay at paypal.com/checkout", "Don't write links"),
        ("Special for you: 10% off today!", "Don't promise discounts"),
        ("Free delivery in Anna Nagar!", "Don't promise free delivery"),
        ("We'll deliver it within 30 minutes", "Don't promise delivery times"),
        ("It will reach you in 2 hours", "Don't promise delivery times"),
        ("x" * 900, "The reply is too long"),
    ],
)
def test_bad_replies_are_caught(reply: str, problem: str) -> None:
    assert any(found.startswith(problem) for found in problems(reply)), problems(reply)


def test_tamil_script_customer_gets_tamil_script() -> None:
    tamil = validator.ReplyFacts(frozenset({6000}), "ரெண்டு சாக்லேட் குக்கீ வேணும்")

    assert problems("Sure, 2 chocolate cookies!", tamil) == [
        "The customer writes in Tamil script: reply in Tamil script too."
    ]
    assert problems("சரி, 2 சாக்லேட் குக்கீ ₹60 ஒன்று", tamil) == []


def test_amounts_are_read_in_minor_units() -> None:
    assert validator.amounts_in("₹60, Rs 1,200 and $12.50 or 90/-") == {6000, 120000, 1250, 9000}
    assert validator.amounts_in("2 cookies at 6 pm") == set()


@pytest.mark.parametrize(
    ("language", "customer", "expected"),
    [
        ("ta-en", "rendu cookie", "Shop-la check panni seekiram solren."),
        ("en", "ரெண்டு குக்கீ", "கடையிடம் கேட்டுவிட்டு விரைவில் பதில் சொல்கிறேன்."),
        ("hi-en", "do cookie chahiye", "Shop se check karke jaldi batate hain."),
        ("fr", "deux cookies", "Let me check with the shop and get back to you shortly."),
    ],
)
def test_holding_message_matches_the_customer(language: str, customer: str, expected: str) -> None:
    assert templates.holding_message(language, customer) == expected
