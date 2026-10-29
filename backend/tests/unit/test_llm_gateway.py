"""The model gateway: tool calls, JSON fallback mode, retries, fallback models, circuit breaker."""

import json
from typing import Any

import pytest

from app.core.config import get_settings
from app.modules.agent import llm

pytestmark = pytest.mark.anyio

SEARCH = llm.ToolSpec(
    name="search_catalog",
    description="Find items in the shop's catalog.",
    parameters={
        "type": "object",
        "properties": {"query": {"type": "string"}},
        "required": ["query"],
    },
)


def answer(
    content: str | None = "", tool_calls: list[dict[str, Any]] | None = None, model: str = ""
) -> dict[str, Any]:
    message: dict[str, Any] = {"role": "assistant", "content": content}
    if tool_calls:
        message["tool_calls"] = tool_calls
    return {
        "model": model,
        "choices": [{"message": message}],
        "usage": {"prompt_tokens": 1000, "completion_tokens": 200},
    }


def native_call(name: str, arguments: str, call_id: str = "call_1") -> dict[str, Any]:
    return {"id": call_id, "type": "function", "function": {"name": name, "arguments": arguments}}


class Provider:
    """Answers each request with the next scripted reply for the requested model."""

    def __init__(self, **scripts: list[dict[str, Any] | llm.LLMError]) -> None:
        self.scripts = scripts
        self.requests: list[dict[str, Any]] = []

    async def __call__(self, body: dict[str, Any]) -> dict[str, Any]:
        self.requests.append(body)
        reply = self.scripts[body["model"]].pop(0)
        if isinstance(reply, llm.LLMError):
            raise reply
        return reply | {"model": reply.get("model") or body["model"]}

    def models_called(self) -> list[str]:
        return [request["model"] for request in self.requests]


@pytest.fixture(autouse=True)
def gateway(monkeypatch: pytest.MonkeyPatch) -> list[float]:
    """Two models, no real waiting, a fresh circuit breaker; returns the waits asked for."""
    settings = get_settings()
    monkeypatch.setattr(settings, "llm_models", "primary,fallback")
    monkeypatch.setattr(settings, "llm_tool_mode", "native")
    monkeypatch.setattr(llm, "breaker", llm.CircuitBreaker())
    waits: list[float] = []

    async def sleep(seconds: float) -> None:
        waits.append(seconds)

    monkeypatch.setattr(llm, "_sleep", sleep)
    return waits


def use(monkeypatch: pytest.MonkeyPatch, provider: Provider) -> Provider:
    monkeypatch.setattr(llm, "_post", provider)
    return provider


def unavailable(retry_after: float | None = None) -> llm.LLMError:
    return llm.LLMError("Model returned 503", retryable=True, retry_after=retry_after)


async def test_native_tool_calls_are_parsed_and_tools_are_offered(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    provider = use(
        monkeypatch,
        Provider(primary=[answer(None, [native_call("search_catalog", '{"query": "cake"}')])]),
    )
    history = [
        llm.Message("system", "You sell cakes."),
        llm.Message("user", "cake irukka?"),
        llm.Message("assistant", "", (llm.ToolCall("call_0", "search_catalog", {"query": "x"}),)),
        llm.Message("tool", '{"ok": true}', tool_call_id="call_0"),
    ]

    completion = await llm.generate(history, tools=[SEARCH])

    assert completion.tool_calls == (llm.ToolCall("call_1", "search_catalog", {"query": "cake"}),)
    body = provider.requests[0]
    assert body["tools"] == [
        {
            "type": "function",
            "function": {
                "name": "search_catalog",
                "description": SEARCH.description,
                "parameters": SEARCH.parameters,
            },
        }
    ]
    assert body["messages"][2]["tool_calls"][0]["function"] == {
        "name": "search_catalog",
        "arguments": '{"query": "x"}',
    }
    assert body["messages"][3] == {
        "role": "tool",
        "tool_call_id": "call_0",
        "content": '{"ok": true}',
    }


async def test_tool_arguments_that_arent_json_come_back_as_an_error_for_the_model(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    use(monkeypatch, Provider(primary=[answer(None, [native_call("search_catalog", "{query")])]))

    completion = await llm.generate([llm.Message("user", "hi")], tools=[SEARCH])

    [call] = completion.tool_calls
    assert call.arguments == {}
    assert call.arguments_error is not None


async def test_a_temporary_failure_is_retried_on_the_same_model(
    monkeypatch: pytest.MonkeyPatch, gateway: list[float]
) -> None:
    provider = use(monkeypatch, Provider(primary=[unavailable(), answer("Vanakkam!")]))

    completion = await llm.generate([llm.Message("user", "hi")])

    assert completion.content == "Vanakkam!"
    assert provider.models_called() == ["primary", "primary"]
    assert len(gateway) == 1


async def test_retry_after_is_respected(
    monkeypatch: pytest.MonkeyPatch, gateway: list[float]
) -> None:
    use(monkeypatch, Provider(primary=[unavailable(retry_after=4), answer("ok")]))

    await llm.generate([llm.Message("user", "hi")])

    assert gateway == [4]


async def test_the_fallback_model_answers_when_the_primary_keeps_failing(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    provider = use(
        monkeypatch,
        Provider(primary=[unavailable()] * 3, fallback=[answer("from the fallback")]),
    )

    completion = await llm.generate([llm.Message("user", "hi")])

    assert completion.content == "from the fallback"
    assert completion.model == "fallback"
    assert provider.models_called() == ["primary"] * 3 + ["fallback"]


async def test_a_bad_request_fails_at_once_without_retries_or_fallback(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    provider = use(
        monkeypatch, Provider(primary=[llm.LLMError("Model returned 400", retryable=False)])
    )

    with pytest.raises(llm.LLMError, match="400"):
        await llm.generate([llm.Message("user", "hi")])

    assert provider.models_called() == ["primary"]


async def test_when_every_model_fails_the_error_says_so(monkeypatch: pytest.MonkeyPatch) -> None:
    use(monkeypatch, Provider(primary=[unavailable()] * 3, fallback=[unavailable()] * 3))

    with pytest.raises(llm.LLMError, match="primary.*fallback"):
        await llm.generate([llm.Message("user", "hi")])


async def test_a_failing_model_is_skipped_for_a_while(monkeypatch: pytest.MonkeyPatch) -> None:
    provider = use(
        monkeypatch,
        Provider(primary=[unavailable()] * 6, fallback=[answer("a"), answer("b"), answer("c")]),
    )

    for _ in range(3):
        await llm.generate([llm.Message("user", "hi")])

    # Two turns of 3 failures open the circuit; the third goes straight to the fallback.
    assert provider.models_called().count("primary") == 6
    assert provider.models_called()[-1] == "fallback"
    assert provider.models_called()[-2] == "fallback"


def test_the_circuit_closes_again_after_the_cooldown() -> None:
    now = [0.0]
    breaker = llm.CircuitBreaker(clock=lambda: now[0])
    for _ in range(llm.CircuitBreaker.THRESHOLD):
        breaker.failure("primary")

    assert not breaker.available("primary")
    now[0] += llm.CircuitBreaker.COOLDOWN_SECONDS + 1
    assert breaker.available("primary")


async def test_json_mode_asks_for_tool_calls_as_json_and_parses_them(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(get_settings(), "llm_tool_mode", "json")
    reply = json.dumps({"tool_calls": [{"name": "search_catalog", "arguments": {"query": "cake"}}]})
    provider = use(monkeypatch, Provider(primary=[answer(reply)]))
    history = [
        llm.Message("system", "You sell cakes."),
        llm.Message("user", "cake?"),
        llm.Message("assistant", "", (llm.ToolCall("c0", "search_catalog", {"query": "x"}),)),
        llm.Message("tool", '{"ok": true}', tool_call_id="c0"),
    ]

    completion = await llm.generate(history, tools=[SEARCH])

    assert [(c.name, c.arguments) for c in completion.tool_calls] == [
        ("search_catalog", {"query": "cake"})
    ]
    body = provider.requests[0]
    assert "tools" not in body
    roles = [message["role"] for message in body["messages"]]
    assert roles == ["system", "user", "assistant", "user"]  # no tool roles in JSON mode
    assert "search_catalog" in body["messages"][0]["content"]
    assert json.loads(body["messages"][2]["content"])["tool_calls"][0]["name"] == "search_catalog"


async def test_json_mode_text_without_tool_calls_is_plain_content(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(get_settings(), "llm_tool_mode", "json")
    use(monkeypatch, Provider(primary=[answer("Just text")]))

    completion = await llm.generate([llm.Message("user", "hi")], tools=[SEARCH])

    assert completion.tool_calls == ()
    assert completion.content == "Just text"


async def test_cost_is_worked_out_from_the_configured_prices(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(get_settings(), "llm_prices", "primary=0.20/0.50")
    use(monkeypatch, Provider(primary=[answer("hi")]))

    completion = await llm.generate([llm.Message("user", "hi")])

    # 1,000 input tokens at $0.20/M + 200 output tokens at $0.50/M
    assert completion.cost_usd == pytest.approx(0.0003)
