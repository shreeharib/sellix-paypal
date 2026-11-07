"""Model gateway: every LLM call goes through here, so changing provider is a config change.

Speaks the OpenAI-compatible chat completions format, which xAI (Grok), Google (Gemini),
OpenAI, Groq, OpenRouter and many others accept.

Every call (agent-phase-2.md section 13.1):
- is retried on timeouts, HTTP 429 and 5xx, up to MAX_RETRIES times with backoff and jitter,
  respecting Retry-After;
- falls back to the next model in LLM_MODELS when a model's retries run out;
- skips a model whose circuit is open (THRESHOLD failures within a minute -> 2 minutes off);
- fails at once on a non-retryable error (400, 401, ...): retrying can't fix the request.

`generate` is the v2 entry point with tool calling. When the provider has no native tool
calls (LLM_TOOL_MODE=json), it asks for {"tool_calls": [...]} as JSON and parses that into
the same structure, so callers can't tell the difference. `complete` is the v1 entry point
(one JSON answer, no tools).
"""

import asyncio
import json
import random
import time
from collections import deque
from collections.abc import Callable, Sequence
from dataclasses import dataclass, field
from typing import Any, Literal

import httpx2
import structlog

from app.core.config import get_settings
from app.modules.agent import prompt_store
from app.modules.agent.schemas import ChatMessage

log = structlog.get_logger()

MAX_RETRIES = 2
RETRY_DELAYS = (0.5, 1.5)  # seconds, before jitter
MAX_RETRY_AFTER_SECONDS = 10.0


class LLMError(RuntimeError):
    def __init__(
        self, message: str, *, retryable: bool = True, retry_after: float | None = None
    ) -> None:
        super().__init__(message)
        self.retryable = retryable
        self.retry_after = retry_after


@dataclass(frozen=True)
class ToolSpec:
    name: str
    description: str
    parameters: dict[str, Any]  # JSON schema of the arguments


@dataclass(frozen=True)
class ToolCall:
    id: str
    name: str
    arguments: dict[str, Any]
    # Set when the model's arguments weren't a JSON object; the engine tells the model.
    arguments_error: str | None = None


@dataclass(frozen=True)
class Message:
    role: Literal["system", "user", "assistant", "tool"]
    content: str = ""
    tool_calls: tuple[ToolCall, ...] = ()
    tool_call_id: str | None = None  # for role "tool": the call this is the result of
    name: str | None = None  # for role "tool": the tool's name (used in JSON mode)
    images: tuple[str, ...] = ()  # image links for a vision model (role "user")


@dataclass(frozen=True)
class Completion:
    content: str
    model: str
    input_tokens: int | None
    output_tokens: int | None
    latency_ms: int
    tool_calls: tuple[ToolCall, ...] = ()
    cost_usd: float | None = None
    failed_models: tuple[str, ...] = field(default=())  # tried before this one answered


class CircuitBreaker:
    """Stops calling a model that keeps failing, for a while."""

    THRESHOLD = 5
    WINDOW_SECONDS = 60.0
    COOLDOWN_SECONDS = 120.0

    def __init__(self, clock: Callable[[], float] = time.monotonic) -> None:
        self._clock = clock
        self._failures: dict[str, deque[float]] = {}
        self._open_until: dict[str, float] = {}

    def available(self, model: str) -> bool:
        return self._clock() >= self._open_until.get(model, 0.0)

    def failure(self, model: str) -> None:
        now = self._clock()
        failures = self._failures.setdefault(model, deque())
        failures.append(now)
        while failures and failures[0] < now - self.WINDOW_SECONDS:
            failures.popleft()
        if len(failures) >= self.THRESHOLD:
            self._open_until[model] = now + self.COOLDOWN_SECONDS
            failures.clear()
            log.error("llm.circuit_open", model=model, seconds=self.COOLDOWN_SECONDS)

    def success(self, model: str) -> None:
        self._failures.pop(model, None)


breaker = CircuitBreaker()


async def generate(messages: Sequence[Message], *, tools: Sequence[ToolSpec] = ()) -> Completion:
    """A model step: the model answers with text, tool calls, or both."""
    json_mode = bool(tools) and get_settings().llm_tool_mode == "json"

    def body(model: str) -> dict[str, Any]:
        if json_mode:
            return {
                "model": model,
                "messages": _json_mode_messages(messages, tools),
                **_json_format(),
            }
        request: dict[str, Any] = {"model": model, "messages": [_wire(m) for m in messages]}
        if tools:
            request["tools"] = [
                {
                    "type": "function",
                    "function": {
                        "name": tool.name,
                        "description": tool.description,
                        "parameters": tool.parameters,
                    },
                }
                for tool in tools
            ]
        return request

    completion = await _with_fallbacks(body)
    if json_mode:
        return _with_json_tool_calls(completion)
    return completion


async def complete(messages: list[ChatMessage], *, json_output: bool = False) -> Completion:
    """The v1 call: one answer as text (JSON when asked), no tools."""

    def body(model: str) -> dict[str, Any]:
        request: dict[str, Any] = {
            "model": model,
            "messages": [{"role": m.role, "content": m.content} for m in messages],
        }
        if json_output:
            request |= _json_format()
        return request

    return await _with_fallbacks(body)


async def describe_image(image_url: str, *, catalog_names: list[str]) -> dict[str, Any]:
    """Which of the shop's items an image shows: {"products": [names], "caption": str}.

    The image is passed to the model as a link and never stored (agent-phase-2.md 11).
    """

    def body(model: str) -> dict[str, Any]:
        settings = get_settings()
        return {
            "model": settings.llm_vision_model or model,
            "messages": [
                _wire(
                    Message(
                        "user",
                        prompt_store.render("vision.describe", catalog=catalog_names),
                        images=(image_url,),
                    )
                )
            ],
            **_json_format(),
        }

    completion = await _with_fallbacks(body)
    try:
        parsed = json.loads(completion.content.strip().strip("`").removeprefix("json"))
    except ValueError:
        return {"products": [], "caption": None}
    return parsed if isinstance(parsed, dict) else {"products": [], "caption": None}


def models() -> list[str]:
    settings = get_settings()
    configured = [name.strip() for name in settings.llm_models.split(",") if name.strip()]
    return configured or [settings.llm_model]


async def _with_fallbacks(body: Callable[[str], dict[str, Any]]) -> Completion:
    failed: list[str] = []
    errors: list[str] = []
    for model in models():
        if not breaker.available(model):
            errors.append(f"{model}: circuit open")
            continue
        for attempt in range(MAX_RETRIES + 1):
            started = time.perf_counter()
            try:
                data = await _post(body(model))
                completion = _parse(data, model, round((time.perf_counter() - started) * 1000))
            except LLMError as exc:
                breaker.failure(model)
                log.warning(
                    "llm.call_failed",
                    model=model,
                    attempt=attempt + 1,
                    retryable=exc.retryable,
                    error=str(exc),
                )
                if not exc.retryable:
                    raise
                if attempt < MAX_RETRIES:
                    await _sleep(_delay(attempt, exc.retry_after))
                    continue
                errors.append(f"{model}: {exc}")
                failed.append(model)
                break
            breaker.success(model)
            if failed:
                log.warning("llm.fallback_used", model=model, failed=failed)
            return _priced(completion, failed)
    raise LLMError(f"No model answered ({'; '.join(errors)})")


def _delay(attempt: int, retry_after: float | None) -> float:
    if retry_after is not None:
        return min(retry_after, MAX_RETRY_AFTER_SECONDS)
    base = RETRY_DELAYS[min(attempt, len(RETRY_DELAYS) - 1)]
    return base * random.uniform(0.8, 1.2)


async def _sleep(seconds: float) -> None:
    await asyncio.sleep(seconds)


async def _post(body: dict[str, Any]) -> dict[str, Any]:
    settings = get_settings()
    if settings.llm_reasoning_effort:
        body = body | {"reasoning_effort": settings.llm_reasoning_effort}
    try:
        async with httpx2.AsyncClient(timeout=settings.llm_timeout_seconds) as client:
            response = await client.post(
                f"{settings.llm_base_url.rstrip('/')}/chat/completions",
                headers={"Authorization": f"Bearer {settings.llm_api_key}"},
                json=body,
            )
    except httpx2.HTTPError as exc:
        raise LLMError(f"Model request failed: {exc.__class__.__name__}") from exc
    if response.is_error:
        status = response.status_code
        raise LLMError(
            f"Model returned {status}: {response.text[:300]}",
            retryable=status in (408, 409, 429) or status >= 500,
            retry_after=_retry_after(response.headers.get("retry-after")),
        )
    try:
        data: dict[str, Any] = response.json()
    except ValueError as exc:
        raise LLMError("Model response wasn't JSON") from exc
    return data


def _retry_after(header: str | None) -> float | None:
    try:
        return float(header) if header else None
    except ValueError:
        return None


def _parse(data: dict[str, Any], model: str, latency_ms: int) -> Completion:
    try:
        message = data["choices"][0]["message"]
        content = message.get("content") or ""
        raw_calls = message.get("tool_calls") or []
    except (KeyError, IndexError, TypeError) as exc:
        raise LLMError("Model response wasn't in the expected format") from exc
    usage = data.get("usage") or {}
    return Completion(
        content=str(content).strip(),
        model=str(data.get("model") or model),
        input_tokens=usage.get("prompt_tokens"),
        output_tokens=usage.get("completion_tokens"),
        latency_ms=latency_ms,
        tool_calls=tuple(
            _tool_call(
                str(call.get("id") or f"call_{number}"),
                str((call.get("function") or {}).get("name", "")),
                (call.get("function") or {}).get("arguments"),
            )
            for number, call in enumerate(raw_calls)
        ),
    )


def _tool_call(call_id: str, name: str, arguments: Any) -> ToolCall:
    if isinstance(arguments, dict):
        return ToolCall(call_id, name, arguments)  # pyright: ignore[reportUnknownArgumentType]
    try:
        parsed = json.loads(arguments or "{}")
    except (TypeError, ValueError) as exc:
        return ToolCall(call_id, name, {}, f"The arguments weren't valid JSON: {exc}")
    if not isinstance(parsed, dict):
        return ToolCall(call_id, name, {}, "The arguments must be a JSON object")
    return ToolCall(call_id, name, parsed)  # pyright: ignore[reportUnknownArgumentType]


def _wire(message: Message) -> dict[str, Any]:
    if message.role == "tool":
        return {"role": "tool", "tool_call_id": message.tool_call_id, "content": message.content}
    wired: dict[str, Any] = {"role": message.role, "content": message.content}
    if message.images:
        wired["content"] = [
            {"type": "text", "text": message.content},
            *({"type": "image_url", "image_url": {"url": url}} for url in message.images),
        ]
    if message.tool_calls:
        wired["content"] = message.content or None
        wired["tool_calls"] = [
            {
                "id": call.id,
                "type": "function",
                "function": {"name": call.name, "arguments": json.dumps(call.arguments)},
            }
            for call in message.tool_calls
        ]
    return wired


def _json_mode_messages(
    messages: Sequence[Message], tools: Sequence[ToolSpec]
) -> list[dict[str, str]]:
    instructions = prompt_store.render(
        "gateway.json_tools",
        tools=[
            {"name": t.name, "description": t.description, "parameters": json.dumps(t.parameters)}
            for t in tools
        ],
    )
    wired: list[dict[str, str]] = []
    system_done = False
    for message in messages:
        if message.role == "system" and not system_done:
            wired.append({"role": "system", "content": f"{message.content}\n\n{instructions}"})
            system_done = True
        elif message.role == "tool":
            content = prompt_store.render(
                "gateway.json_tool_result",
                name=message.name or "tool",
                call_id=message.tool_call_id or "",
                content=message.content,
            )
            wired.append({"role": "user", "content": content})
        elif message.tool_calls:
            calls = [{"name": c.name, "arguments": c.arguments} for c in message.tool_calls]
            wired.append({"role": "assistant", "content": json.dumps({"tool_calls": calls})})
        else:
            wired.append({"role": message.role, "content": message.content})
    if not system_done:
        wired.insert(0, {"role": "system", "content": instructions})
    return wired


def _with_json_tool_calls(completion: Completion) -> Completion:
    text = completion.content.strip()
    if text.startswith("```"):
        text = text.strip("`").removeprefix("json").strip()
    try:
        parsed = json.loads(text)
    except ValueError:
        return completion  # plain text: the engine asks the model to use its tools
    if not isinstance(parsed, dict) or not isinstance(parsed.get("tool_calls"), list):
        return completion
    calls = tuple(
        _tool_call(f"call_{number}", str(call.get("name", "")), call.get("arguments"))
        for number, call in enumerate(parsed["tool_calls"])
        if isinstance(call, dict)
    )
    return Completion(
        content="",
        model=completion.model,
        input_tokens=completion.input_tokens,
        output_tokens=completion.output_tokens,
        latency_ms=completion.latency_ms,
        tool_calls=calls,
        cost_usd=completion.cost_usd,
        failed_models=completion.failed_models,
    )


def _json_format() -> dict[str, Any]:
    if get_settings().llm_json_mode == "json_object":
        return {"response_format": {"type": "json_object"}}
    return {}


def _priced(completion: Completion, failed: list[str]) -> Completion:
    price = _prices().get(completion.model)
    cost = None
    if price is not None and completion.input_tokens is not None:
        cost = (
            completion.input_tokens * price[0] + (completion.output_tokens or 0) * price[1]
        ) / 1_000_000
    return Completion(
        content=completion.content,
        model=completion.model,
        input_tokens=completion.input_tokens,
        output_tokens=completion.output_tokens,
        latency_ms=completion.latency_ms,
        tool_calls=completion.tool_calls,
        cost_usd=cost,
        failed_models=tuple(failed),
    )


def _prices() -> dict[str, tuple[float, float]]:
    """LLM_PRICES: "model=input/output,..." in US dollars per million tokens."""
    prices: dict[str, tuple[float, float]] = {}
    for entry in get_settings().llm_prices.split(","):
        name, _, value = entry.strip().partition("=")
        rates = value.split("/")
        try:
            prices[name.strip()] = (float(rates[0]), float(rates[1]))
        except (IndexError, ValueError):
            continue
    return prices
