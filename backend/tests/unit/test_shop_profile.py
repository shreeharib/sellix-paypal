from app.modules.shop_profile.schemas import OnboardingAnswers
from app.modules.shop_profile.service import render_profile


def test_profile_from_full_answers() -> None:
    answers = OnboardingAnswers(
        category="home bakery",
        area="Anna Nagar",
        city="Chennai",
        hours="Tue–Sun, 9 am – 8 pm",
        weekly_off="Mondays",
        products="cookies, brownies, cupcakes",
        intro="Sweet Crumbs' assistant",
        tone="friendly",
        emoji=True,
        address_customers="sir/madam until they use a name",
        fulfilment="Pickup from Anna Nagar 2nd Avenue, or we deliver nearby.",
        never_promise="same-day custom cakes",
        faqs="- Eggless? Yes, on request.",
    )

    assert render_profile("Sweet Crumbs", answers) == (
        "# Sweet Crumbs (home bakery, Anna Nagar, Chennai)\n"
        '- Introduce yourself as: "Sweet Crumbs\' assistant". Friendly tone. Light emoji. '
        "Address customers as: sir/madam until they use a name.\n"
        "- Open Tue–Sun, 9 am – 8 pm.\n"
        "- Closed Mondays.\n"
        "- We sell: cookies, brownies, cupcakes\n"
        "- Pickup and delivery: Pickup from Anna Nagar 2nd Avenue, or we deliver nearby.\n"
        "## Policies\n"
        "- Never promise: same-day custom cakes\n"
        "## Common questions\n"
        "- Eggless? Yes, on request."
    )


def test_skipped_steps_leave_just_the_shop_name() -> None:
    assert render_profile("Sweet Crumbs", OnboardingAnswers()) == "# Sweet Crumbs"
