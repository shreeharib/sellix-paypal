from app.modules.agent.context import choose_playbook


def test_an_owner_answer_gets_its_own_playbook_in_any_stage() -> None:
    event: dict[str, object] = {"event": {"event": "owner_answered", "answer": "whenever they can"}}

    assert choose_playbook("payment_pending", "anything else ?", event) == "owner_answer"
    assert choose_playbook("browsing", "hi", event) == "owner_answer"
    assert choose_playbook("collecting_details", "2 cookies", event) == "owner_answer"


def test_other_events_and_messages_keep_their_playbooks() -> None:
    paid: dict[str, object] = {"event": {"event": "payment_received"}}

    assert choose_playbook("payment_pending", "ok", paid) == "payment_problem"
    assert choose_playbook("payment_pending", "ok", {}) == "payment_problem"
    assert choose_playbook("browsing", "where is my order", {}) == "order_status"


def test_a_greeting_is_small_talk_and_a_menu_question_is_the_menu() -> None:
    assert choose_playbook("browsing", "HII", {}) == "small_talk"
    assert choose_playbook("browsing", "hello", {}) == "small_talk"
    for text in (
        "what do you have today?",
        "what are all the products",
        "show me the menu",
        "anything else ?",
        "do you have any other products >",
    ):
        assert choose_playbook("browsing", text, {}) == "menu", text
    # asked while an order waits for payment, it is still the menu and not a payment question
    assert choose_playbook("payment_pending", "anything else ?", {}) == "menu"
    assert choose_playbook("payment_pending", "i paid", {}) == "payment_problem"


def test_questions_about_one_item_are_not_menu_questions() -> None:
    assert (
        choose_playbook("browsing", "Is this product good for oily skin?", {}) == "product_question"
    )
    assert choose_playbook("browsing", "what size is the kurti", {}) == "product_question"
    assert choose_playbook("browsing", "2 items please", {}) == "new_order"
    assert choose_playbook("collecting_details", "what else do you have", {}) == "new_order"
