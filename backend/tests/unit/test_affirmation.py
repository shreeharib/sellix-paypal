"""A typed reply to a quote card places the order only when it clearly asks for it."""

from typing import Any

import pytest

from app.modules.agent import affirmation, llm

pytestmark = pytest.mark.anyio


class Model:
    """Stands in for the model call; records whether the code needed it."""

    def __init__(self, answer: str = "unclear") -> None:
        self.answer = answer
        self.calls = 0

    async def complete(self, *_: Any, **__: Any) -> llm.Completion:
        self.calls += 1
        return llm.Completion(
            content=f'{{"answer": "{self.answer}"}}',
            model="fake",
            input_tokens=None,
            output_tokens=None,
            latency_ms=0,
        )


@pytest.fixture
def model(monkeypatch: pytest.MonkeyPatch) -> Model:
    fake = Model()
    monkeypatch.setattr(llm, "complete", fake.complete)
    return fake


@pytest.mark.parametrize(
    "text",
    [
        "ok",
        "okay",
        "Okay!",
        "ok bro",
        "sure",
        "yes",
        "fine",
        "done",
        "seri",
        "sari bro",
        "haan",
        "theek hai",
        "👍",
        "சரி",
        "हाँ",
        "okay, when can I pick it up?",
    ],
)
async def test_an_acknowledgement_is_unclear_without_asking_the_model(
    model: Model, text: str
) -> None:
    assert await affirmation.classify(text) == "unclear"
    assert model.calls == 0


@pytest.mark.parametrize(
    "text",
    [
        "confirm",
        "Confirm my order",
        "yes confirm",
        "ok confirm it",
        "please place the order",
        "place order",
        "book it",
        "go ahead",
        "seri confirm pannunga",
        "order podunga",
        "haan theek hai confirm",
        "order kar do",
        "book karo",
        "உறுதி செய்யுங்கள்",
        "ऑर्डर कर दो",
    ],
)
async def test_a_clear_request_places_the_order(model: Model, text: str) -> None:
    assert await affirmation.classify(text) == "yes"
    assert model.calls == 0


@pytest.mark.parametrize("text", ["no", "venam", "nahi", "cancel it", "don't confirm"])
async def test_a_no_is_a_no(model: Model, text: str) -> None:
    assert await affirmation.classify(text) == "no"


@pytest.mark.parametrize("text", ["change it to 3", "add one brownie", "maathanum", "badal do"])
async def test_a_change_is_a_change(model: Model, text: str) -> None:
    assert await affirmation.classify(text) == "change"


@pytest.mark.parametrize("text", ["confirm?", "how do I confirm", "wait, confirm later"])
async def test_a_question_or_a_wait_next_to_confirm_is_left_to_the_model(
    model: Model, text: str
) -> None:
    assert await affirmation.classify(text) == "unclear"
    assert model.calls == 1


async def test_the_model_decides_what_the_code_cant_read(model: Model) -> None:
    model.answer = "yes"
    assert await affirmation.classify("let's do this one") == "yes"
    assert model.calls == 1


async def test_a_model_answer_outside_the_choices_is_unclear(model: Model) -> None:
    model.answer = "maybe"
    assert await affirmation.classify("hmm") == "unclear"
