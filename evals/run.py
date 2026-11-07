"""Run multi-turn eval scenarios against a running sellix through the simulator API.

The simulator goes through the real pipeline (webhook handling, turn engine, tools, guardrails,
outbox) with the configured live model, so this measures what customers would get.

    python evals/run.py --base-url http://localhost:8000 --token "$TOKEN" \\
        evals/datasets/scenarios.jsonl evals/datasets/adversarial.jsonl --min-score 0.9

The token comes from `just cli issue-token --merchant-id <id>` for a shop seeded with
evals/demo_stock.json and switched to the v2 engine. Exits non-zero below --min-score.
Standard library only, so it runs anywhere.
"""

import argparse
import json
import sys
import time
import urllib.request
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).parent))

from scoring import Report, TurnResult, check_turn  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("datasets", nargs="+", type=Path)
    parser.add_argument("--base-url", default="http://localhost:8000")
    parser.add_argument("--token", required=True)
    parser.add_argument("--min-score", type=float, default=0.0)
    parser.add_argument("--out", type=Path, help="write the full report as JSON")
    args = parser.parse_args()

    report = Report()
    run_id = time.strftime("%Y%m%d%H%M%S")
    for dataset in args.datasets:
        for line in dataset.read_text(encoding="utf-8").splitlines():
            if line.strip():
                run_scenario(json.loads(line), args.base_url, args.token, run_id, report)

    summary = report.summary()
    print(json.dumps(summary, indent=2, ensure_ascii=False))
    if args.out:
        args.out.write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")
    return 0 if summary["score"] >= args.min_score else 1


def run_scenario(
    scenario: dict[str, Any], base_url: str, token: str, run_id: str, report: Report
) -> None:
    customer = f"eval-{scenario['id']}-{run_id}"
    seen = 0
    chat: dict[str, Any] = {"messages": []}
    for number, turn in enumerate(scenario["turns"]):
        text = turn.get("customer", "")
        if "customer_repeat" in turn:  # e.g. ["cake ", 1000]: a huge message, kept short here
            piece, times = turn["customer_repeat"]
            text = piece * times
        body: dict[str, Any] = {"text": text, "customer": customer}
        if "tap" in turn:  # tap a button the agent sent, e.g. "CONFIRM"
            button = _button(chat["messages"], turn["tap"])
            if button is None:
                report.turns.append(
                    TurnResult(
                        scenario["id"], number, [f"no {turn['tap']} button"], None, None, None
                    )
                )
                return
            body |= {"text": button["title"], "quick_reply": button["payload"]}
        chat = _post(f"{base_url}/v1/simulator/messages", token, body)
        new = chat["messages"][seen:]
        seen = len(chat["messages"])
        agent_messages = [m["body"] for m in new if m["sender"] == "agent"]
        info = chat.get("turn") or {}
        report.turns.append(
            TurnResult(
                scenario["id"],
                number,
                check_turn(turn.get("expect", {}), info, agent_messages),
                info.get("status"),
                info.get("latency_ms"),
                info.get("cost_usd"),
            )
        )


def _button(messages: list[dict[str, Any]], action: str) -> dict[str, Any] | None:
    for message in reversed(messages):
        for button in message.get("buttons", []):
            if button["payload"].startswith(f"{action}:"):
                return button
    return None


def _post(url: str, token: str, body: dict[str, Any]) -> dict[str, Any]:
    request = urllib.request.Request(
        url,
        data=json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=120) as response:  # noqa: S310 (our own API)
        return json.loads(response.read())


if __name__ == "__main__":
    sys.exit(main())
