"""A turn's playbook is chosen by a small model call; the old rules are only the fallback."""

import asyncio
import uuid
from datetime import UTC, datetime
from typing import Any

import pytest

from app.core.config import get_settings
from app.modules.agent import context, llm, prompt_store, router
from app.modules.agent.schemas import ChatMessage
from app.modules.conversations.schemas import ChatLine

pytestmark = pytest.mark.anyio

ALL_PLAYBOOKS = {
    "abuse_or_off_topic",
    "complaint",
    "custom_or_future_order",
    "menu",
    "new_order",
    "order_status",
    "owner_answer",
    "payment_problem",
    "product_question",
    "small_talk",
    "story_or_photo",
}


def line(sender: str, body: str = "", **details: Any) -> ChatLine:
    return ChatLine(
        id=uuid.uuid4(), sender=sender, body=body, created_at=datetime.now(UTC), details=details
    )


class Model:
    """Stands in for the router's model call and records what it was sent."""

    def __init__(self) -> None:
        self.content = '{"playbook": "menu"}'
        self.error: Exception | None = None
        self.delay = 0.0
        self.calls: list[list[ChatMessage]] = []
        self.chains: list[Any] = []

    async def complete(
        self, messages: list[ChatMessage], *, json_output: bool = False, model_chain: Any = None
    ) -> llm.Completion:
        self.calls.append(list(messages))
        self.chains.append(model_chain)
        if self.delay:
            await asyncio.sleep(self.delay)
        if self.error is not None:
            raise self.error
        return llm.Completion(
            content=self.content,
            model="router-model",
            input_tokens=50,
            output_tokens=5,
            latency_ms=3,
        )


@pytest.fixture
def model(monkeypatch: pytest.MonkeyPatch) -> Model:
    fake = Model()
    monkeypatch.setattr(llm, "complete", fake.complete)
    monkeypatch.setattr(get_settings(), "agent_playbook_router", "model")
    monkeypatch.setattr(get_settings(), "llm_router_model", "")
    return fake


async def choose(history: list[ChatLine], stage: str = "browsing") -> router.Choice:
    customer = next((x.body for x in reversed(history) if x.sender == "customer"), "")
    return await router.choose(
        stage=stage, history=history, trigger=history[-1], customer_text=customer
    )


async def test_the_model_picks_the_playbook_the_rules_would_miss(model: Model) -> None:
    history = [
        line("customer", "2 chocolate cookies please"),
        line("agent", "Sure! Pickup or delivery?"),
        line("customer", "what else do you have"),
    ]

    choice = await choose(history)

    assert (choice.playbook, choice.by) == ("menu", "model")
    assert choice.completion is not None
    assert context.choose_playbook("browsing", "what else do you have", {}) == "new_order"


async def test_the_prompt_lists_the_playbooks_and_keeps_the_customer_out_of_it(
    model: Model,
) -> None:
    await choose([line("customer", "what else do you have")], stage="payment_pending")

    [system, user] = model.calls[0]
    assert system.role == "system"
    assert "payment_pending" in system.content
    for name in router.routable():
        assert f"- {name}: {prompt_store.applies_when(f'playbook.{name}')}" in system.content
    assert "what else do you have" not in system.content
    assert user.role == "user"
    assert user.content.endswith("Customer: what else do you have")


def test_every_playbook_says_when_it_applies_and_only_code_picks_owner_answer() -> None:
    for name in ALL_PLAYBOOKS:
        assert prompt_store.applies_when(f"playbook.{name}"), name
    assert set(router.routable()) == ALL_PLAYBOOKS - {"owner_answer"}


async def test_only_the_latest_messages_are_sent(model: Model) -> None:
    history = [line("customer", f"message {n}") for n in range(10)]
    history.insert(8, line("agent", "We have brownies"))

    await choose(history)

    user = model.calls[0][1].content
    assert "Shop: We have brownies" in user
    assert "message 9" in user
    assert "message 5" in user
    assert "message 4" not in user
    assert len(user.splitlines()) == router.RECENT_MESSAGES


async def test_a_shop_event_reaches_the_router_as_an_event(model: Model) -> None:
    model.content = '{"playbook": "order_status"}'
    event = {"event": "payment_received", "order": "#1004"}
    history = [line("customer", "Perfect, place the order"), line("system", "paid", event=event)]

    choice = await choose(history)

    assert choice.playbook == "order_status"
    assert model.calls[0][1].content.endswith("[Shop event: payment_received #1004]")


async def test_the_owner_answer_needs_no_model_call(model: Model) -> None:
    answered = {"event": "owner_answered", "question": "Name on cake?", "answer": "Yes"}
    history = [line("customer", "can you write a name"), line("system", "answer", event=answered)]

    choice = await choose(history)

    assert (choice.playbook, choice.by) == ("owner_answer", "event")
    assert model.calls == []


@pytest.mark.parametrize(
    ("content", "error"),
    [
        ("", llm.LLMError("No model answered")),
        ("menu please", None),
        ('{"playbook": "pizza"}', None),
        ('{"playbook": "owner_answer"}', None),
        ('["menu"]', None),
    ],
)
async def test_a_failed_or_unusable_answer_falls_back_to_the_rules(
    model: Model, content: str, error: Exception | None
) -> None:
    model.content, model.error = content, error

    choice = await choose([line("customer", "2 cookies for pickup")])

    assert (choice.playbook, choice.by) == ("new_order", "rules")


async def test_a_slow_router_falls_back_to_the_rules(
    model: Model, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(get_settings(), "agent_router_timeout_seconds", 0.05)
    model.delay = 5

    choice = await choose([line("customer", "hi")])

    assert (choice.playbook, choice.by) == ("small_talk", "rules")


@pytest.mark.parametrize(
    ("content", "expected"),
    [
        ('{"playbook": "menu"}', "menu"),
        ('```json\n{"playbook": "complaint"}\n```', "complaint"),
        ('{"playbook": "playbook.small_talk"}', "small_talk"),
    ],
)
async def test_answer_formats_the_router_accepts(model: Model, content: str, expected: str) -> None:
    model.content = content

    choice = await choose([line("customer", "hello")])

    assert (choice.playbook, choice.by) == (expected, "model")


async def test_the_rules_setting_skips_the_model(
    model: Model, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(get_settings(), "agent_playbook_router", "rules")

    choice = await choose([line("customer", "what do you have")])

    assert (choice.playbook, choice.by) == ("menu", "rules")
    assert model.calls == []


async def test_a_separate_router_model_can_be_configured(
    model: Model, monkeypatch: pytest.MonkeyPatch
) -> None:
    await choose([line("customer", "hi")])
    monkeypatch.setattr(get_settings(), "llm_router_model", "small-fast-model")
    await choose([line("customer", "hi")])

    assert model.chains == [None, ["small-fast-model"]]
