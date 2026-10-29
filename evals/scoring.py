"""Scoring for the multi-turn evals: what each turn was expected to do, and what it did.

A turn's expectations (all optional):
- tools_include / tools_exclude: tool names the turn must / must not have used
- status: how the turn ended (replied, fallback, gated, handed_off)
- stage_after: the conversation's stage after the turn
- reply_regex / no_reply_regex: patterns the agent's new messages must / must not match
"""

import re
from dataclasses import dataclass, field
from typing import Any


@dataclass
class TurnResult:
    scenario: str
    turn: int
    failures: list[str]
    status: str | None
    latency_ms: int | None
    cost_usd: float | None


@dataclass
class Report:
    turns: list[TurnResult] = field(default_factory=list)

    def scenarios(self) -> dict[str, bool]:
        passed: dict[str, bool] = {}
        for turn in self.turns:
            passed[turn.scenario] = passed.get(turn.scenario, True) and not turn.failures
        return passed

    def summary(self) -> dict[str, Any]:
        scenarios = self.scenarios()
        statuses = [t.status for t in self.turns]
        latencies = sorted(t.latency_ms for t in self.turns if t.latency_ms is not None)
        costs = [t.cost_usd for t in self.turns if t.cost_usd is not None]
        return {
            "scenarios": len(scenarios),
            "passed": sum(scenarios.values()),
            "score": round(sum(scenarios.values()) / len(scenarios), 3) if scenarios else 0.0,
            "turns": len(self.turns),
            "fallback_rate": round(statuses.count("fallback") / len(statuses), 3)
            if statuses
            else 0.0,
            "p95_latency_ms": latencies[int(0.95 * (len(latencies) - 1))] if latencies else None,
            "cost_usd": round(sum(costs), 6) if costs else None,
            "failures": [
                {"scenario": t.scenario, "turn": t.turn, "failures": t.failures}
                for t in self.turns
                if t.failures
            ],
        }


def check_turn(
    expect: dict[str, Any], turn: dict[str, Any] | None, agent_messages: list[str]
) -> list[str]:
    """What went wrong in one turn (empty: it met every expectation)."""
    failures: list[str] = []
    tools = (turn or {}).get("tools") or []
    for name in expect.get("tools_include", []):
        if name not in tools:
            failures.append(f"expected tool {name}, used {tools}")
    for name in expect.get("tools_exclude", []):
        if name in tools:
            failures.append(f"must not use {name}")
    for key in ("status", "stage_after"):
        if key in expect and (turn or {}).get(key) != expect[key]:
            failures.append(f"{key}: expected {expect[key]}, got {(turn or {}).get(key)}")
    text = "\n".join(agent_messages)
    if "reply_regex" in expect and not re.search(expect["reply_regex"], text, re.IGNORECASE):
        failures.append(f"reply should match {expect['reply_regex']!r}: {text[:200]!r}")
    if "no_reply_regex" in expect and re.search(expect["no_reply_regex"], text, re.IGNORECASE):
        failures.append(f"reply must not match {expect['no_reply_regex']!r}: {text[:200]!r}")
    return failures
