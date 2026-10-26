"""Model gateway: every LLM call goes through here, so changing provider is a config change.

Speaks the OpenAI-compatible chat completions format, which xAI (Grok), Google (Gemini),
OpenAI, Groq, OpenRouter and many others accept.
"""

import time
from dataclasses import dataclass
from typing import Any

import httpx2

from app.core.config import get_settings
from app.modules.agent.schemas import ChatMessage

TIMEOUT_SECONDS = 45


class LLMError(RuntimeError):
    pass


@dataclass(frozen=True)
class Completion:
    content: str
    model: str
    input_tokens: int | None
    output_tokens: int | None
    latency_ms: int


async def complete(
    messages: list[ChatMessage], *, json_output: bool = False, model: str | None = None
) -> Completion:
    """`model` overrides LLM_MODEL (same provider), e.g. to compare models in evals."""
    settings = get_settings()
    model = model or settings.llm_model
    body: dict[str, Any] = {
        "model": model,
        "messages": [{"role": m.role, "content": m.content} for m in messages],
    }
    if json_output and settings.llm_json_mode == "json_object":
        body["response_format"] = {"type": "json_object"}
    if settings.llm_reasoning_effort:
        body["reasoning_effort"] = settings.llm_reasoning_effort

    started = time.perf_counter()
    try:
        async with httpx2.AsyncClient(timeout=TIMEOUT_SECONDS) as client:
            response = await client.post(
                f"{settings.llm_base_url.rstrip('/')}/chat/completions",
                headers={"Authorization": f"Bearer {settings.llm_api_key}"},
                json=body,
            )
    except httpx2.HTTPError as exc:
        raise LLMError(f"Model request failed: {exc.__class__.__name__}") from exc
    latency_ms = round((time.perf_counter() - started) * 1000)

    if response.is_error:
        raise LLMError(f"Model returned {response.status_code}: {response.text[:300]}")
    try:
        data = response.json()
        content = data["choices"][0]["message"].get("content") or ""
    except (ValueError, KeyError, IndexError, TypeError) as exc:
        raise LLMError("Model response wasn't in the expected format") from exc

    usage = data.get("usage") or {}
    return Completion(
        content=content.strip(),
        model=str(data.get("model") or model),
        input_tokens=usage.get("prompt_tokens"),
        output_tokens=usage.get("completion_tokens"),
        latency_ms=latency_ms,
    )
