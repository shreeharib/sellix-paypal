"""The eval runner's scoring (evals/scoring.py) and scenario driving (evals/run.py)."""

import json
import sys
from typing import Any

import pytest

from app.core.config import BACKEND_DIR

EVALS = BACKEND_DIR.parent / "evals"
sys.path.insert(0, str(EVALS))

import run  # noqa: E402  # pyright: ignore[reportMissingImports]
import scoring  # noqa: E402  # pyright: ignore[reportMissingImports]


def test_a_turn_meets_its_expectations() -> None:
    turn = {
        "tools": ["search_catalog", "create_quote", "send_reply"],
        "status": "replied",
        "stage_after": "awaiting_confirmation",
    }

    assert (
        scoring.check_turn(
            {
                "tools_include": ["create_quote"],
                "tools_exclude": ["confirm_order"],
                "status": "replied",
                "stage_after": "awaiting_confirmation",
                "reply_regex": "confirm",
            },
            turn,
            ["Total ₹120. Confirm?"],
        )
        == []
    )


def test_each_missed_expectation_is_reported() -> None:
    failures = scoring.check_turn(
        {
            "tools_include": ["create_quote"],
            "tools_exclude": ["confirm_order"],
            "no_reply_regex": "discount",
        },
        {"tools": ["confirm_order"], "status": "replied"},
        ["Sure, 10% discount!"],
    )

    assert len(failures) == 3


def test_a_scenario_drives_the_simulator_and_taps_buttons(monkeypatch: pytest.MonkeyPatch) -> None:
    posted: list[dict[str, Any]] = []
    replies = [
        {
            "messages": [
                {"sender": "customer", "body": "2 cookies", "buttons": []},
                {
                    "sender": "agent",
                    "body": "Card",
                    "buttons": [{"title": "Confirm", "payload": "CONFIRM:q1"}],
                },
            ],
            "turn": {"tools": ["create_quote"], "status": "replied"},
        },
        {
            "messages": [{"sender": "agent", "body": "x", "buttons": []}] * 4,
            "turn": {"tools": [], "status": "replied", "stage_after": "payment_pending"},
        },
    ]

    def post(url: str, token: str, body: dict[str, Any]) -> dict[str, Any]:
        posted.append(body)
        return replies.pop(0)

    monkeypatch.setattr(run, "_post", post)
    report = scoring.Report()
    scenario = json.loads(
        '{"id": "s1", "turns": [{"customer": "2 cookies", "expect": {"tools_include": '
        '["create_quote"]}}, {"tap": "CONFIRM", "expect": {"stage_after": "payment_pending"}}]}'
    )

    run.run_scenario(scenario, "http://x", "token", "r1", report)

    assert posted[1]["quick_reply"] == "CONFIRM:q1"
    assert report.summary()["score"] == 1.0
