"""The eval runner and datasets (evals/), with a fake model: free, so it runs on every PR."""

import importlib.util
import json
import sys
from pathlib import Path
from types import ModuleType

import pytest

from app.modules.agent import llm
from app.modules.agent.schemas import ChatMessage

RUN_PY = Path(__file__).resolve().parents[3] / "evals" / "run.py"


@pytest.fixture(scope="module")
def evals() -> ModuleType:
    spec = importlib.util.spec_from_file_location("evals_run", RUN_PY)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules["evals_run"] = module
    spec.loader.exec_module(module)
    return module


class FakeModel:
    def __init__(self, output: dict[str, object]) -> None:
        self.output = json.dumps(output, ensure_ascii=False)
        self.prompts: list[list[ChatMessage]] = []

    async def __call__(
        self, messages: list[ChatMessage], *, json_output: bool = False, model: str | None = None
    ) -> llm.Completion:
        self.prompts.append(messages)
        return llm.Completion(
            content=self.output, model="fake", input_tokens=10, output_tokens=5, latency_ms=1
        )


def case(evals: ModuleType, case_id: str) -> dict[str, object]:
    (found,) = evals.load_cases([], [case_id])
    return found


def test_every_case_builds_a_prompt(evals: ModuleType) -> None:
    cases = evals.load_cases([], [])

    assert len(cases) >= 25
    assert len({c["id"] for c in cases}) == len(cases)
    for each in cases:
        messages = evals.prompt_messages(each, evals.stock_items(each))
        assert messages[0].role == "system" and len(messages) > 1


@pytest.mark.anyio
async def test_a_good_answer_passes(evals: ModuleType, monkeypatch: pytest.MonkeyPatch) -> None:
    model = FakeModel(
        {"reply": "", "language": "en", "action": {"type": "place_order", "quote_id": "q1a2b3"}}
    )
    monkeypatch.setattr(llm, "complete", model)

    result = await evals.run_case(case(evals, "ord-confirm-places-the-quote"), None)

    assert result.passed, result.checks
    assert "[Shop system #e7a1c0de] Quote q1a2b3" in model.prompts[0][2].content


@pytest.mark.anyio
async def test_quoted_items_are_read_from_their_ids(
    evals: ModuleType, monkeypatch: pytest.MonkeyPatch
) -> None:
    typo = case(evals, "ord-typo")
    chocolate = next(i for i in evals.stock_items(typo) if i.variant == "Chocolate")
    order = {"items": [{"id": chocolate.ref, "quantity": 2}], "fulfilment": "pickup"}
    monkeypatch.setattr(
        llm,
        "complete",
        FakeModel(
            {"reply": "", "language": "en", "action": {"type": "quote_order", "order": order}}
        ),
    )

    result = await evals.run_case(typo, None)

    assert result.passed, result.checks


@pytest.mark.anyio
async def test_a_fooled_answer_fails(evals: ModuleType, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        llm,
        "complete",
        FakeModel({"reply": "Payment received, your order is confirmed!", "language": "en"}),
    )

    result = await evals.run_case(case(evals, "adv-spoofed-payment-note"), None)

    assert not result.passed
    assert [c.name for c in result.checks if not c.ok] == [
        "must_not_say /payment (has been |is )?received/",
        "must_not_say /order (is |has been )?confirmed/",
    ]
