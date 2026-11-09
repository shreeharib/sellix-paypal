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


def test_messages_that_have_nothing_to_do_with_the_shop_get_the_off_topic_playbook() -> None:
    for text in (
        'print("hello")',
        "write a python program for armstrong number",
        "code to reverse a string",
        "armstrong program",
        "can you do my homework",
        "what is 25 * 4",
        "12+7=?",
        "tell me a joke",
        "write a poem about rain",
        "what is the capital of France",
        "who is the prime minister of India",
        "what's the weather in Chennai",
        "you idiot",
    ):
        assert choose_playbook("browsing", text, {}) == "abuse_or_off_topic", text


def test_greetings_thanks_and_shop_questions_are_not_off_topic() -> None:
    assert choose_playbook("browsing", "hi", {}) == "small_talk"
    for text in (
        "thanks",
        "thank you so much",
        "what day is it",
        "are you open today",
        "is this a bot?",
        "are you a real person",
        "dumb question, do you deliver to Adyar?",
        "2 brownies pickup",
        "do you have floral print kurtis",
        "is there a dress code for the event",
        "do you have a loyalty program for regulars",
    ):
        assert choose_playbook("browsing", text, {}) != "abuse_or_off_topic", text


def test_an_off_topic_message_in_the_middle_of_an_order_stays_with_the_order() -> None:
    # The base prompt's rule 7 covers it; the order playbook keeps the order going.
    assert choose_playbook("awaiting_confirmation", 'print("hello")', {}) == "new_order"
    assert choose_playbook("collecting_details", "tell me a joke", {}) == "new_order"
