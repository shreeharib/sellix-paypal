"""Runs eval datasets against live models and scores the agent's answers.

Uses the production prompt, output parser and reply checks (backend/app/modules/agent), with
the model settings from backend/.env. It costs model credits: run it on demand.

    cd backend && uv run python ../evals/run.py                      # every dataset
    cd backend && uv run python ../evals/run.py --dataset adversarial --min-score 0.9
    cd backend && uv run python ../evals/run.py --model grok-4-fast --model gemini-2.5-flash

Each line of a dataset (.jsonl) is one case; see evals/README.md for the format.
"""

import argparse
import asyncio
import json
import re
import sys
import time
import uuid
from collections import Counter
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

EVALS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(EVALS_DIR.parent / "backend"))

from app.core.config import get_settings  # noqa: E402
from app.modules.agent import customer_agent, llm, validator  # noqa: E402
from app.modules.agent.schemas import ChatMessage, CustomerReply, TurnBrief  # noqa: E402
from app.modules.inventory.schemas import StockItem  # noqa: E402
from app.modules.merchants import hours  # noqa: E402

# The shop every case uses unless it gives its own profile, hours or stock.
DEFAULT_PROFILE = """# Sweet Crumbs (home bakery, Anna Nagar, Chennai)
- Friendly tone. Light emoji.
- Address: 12 2nd Avenue, Anna Nagar (pickup only from here)
- Pickup and delivery: pickup, or delivery within Anna Nagar (the shop confirms the charge)
## Policies
- Custom orders: cakes need 2 days' notice; ask the owner
- Never promise: delivery times, discounts"""
DEFAULT_HOURS = "mon=closed tue-sun=09:00-20:00"
DEFAULT_NOW = "2026-10-27T15:00:00+05:30"  # a Tuesday afternoon, open
DEFAULT_STOCK = [
    {"product": "Scoop cookie", "variant": "Chocolate", "price": 60, "available": 8},
    {"product": "Scoop cookie", "variant": "Red velvet", "price": 70, "available": 4},
    {"product": "Brownie", "variant": None, "price": 90, "available": 15},
]
SYSTEM_TAG = "e7a1c0de"  # fixed, so every run sees the same prompt
_STOCK_IDS = uuid.UUID("5e11c0de-0000-4000-8000-000000000000")


@dataclass(frozen=True)
class Check:
    name: str
    ok: bool
    detail: str = ""


@dataclass
class Result:
    case_id: str
    model: str
    checks: list[Check] = field(default_factory=list)
    reply: str = ""
    language: str = ""
    action: dict[str, Any] | None = None
    latency_ms: int = 0
    input_tokens: int = 0
    output_tokens: int = 0

    @property
    def passed(self) -> bool:
        return all(check.ok for check in self.checks)


def stock_items(case: dict[str, Any]) -> list[StockItem]:
    """The case's stock, with variant IDs that stay the same between runs."""
    items = []
    for row in case.get("stock", DEFAULT_STOCK):
        label = f"{row['product']}|{row.get('variant') or ''}"
        items.append(
            StockItem(
                product=row["product"],
                variant=row.get("variant"),
                price_minor=round(float(row["price"]) * 100),
                currency=row.get("currency", "INR"),
                available=int(row.get("available", 10)),
                variant_id=uuid.uuid5(_STOCK_IDS, label),
            )
        )
    return items


def prompt_messages(case: dict[str, Any], stock: list[StockItem]) -> list[ChatMessage]:
    """The system prompt and chat, exactly as a production turn would build them."""
    now = datetime.fromisoformat(case.get("now", DEFAULT_NOW))
    timezone = case.get("timezone", "Asia/Kolkata")
    spec = case.get("hours", DEFAULT_HOURS)
    opening = hours.parse_spec(spec) if spec else None
    clock = customer_agent.ShopClock(
        now=hours.describe_now(opening, timezone, now),
        week=hours.describe_week(opening, now.date()),
    )
    brief = brief_for(case)
    system = customer_agent.build_system_prompt(
        case.get("profile", DEFAULT_PROFILE), stock, brief, clock
    )
    return [ChatMessage("system", system), *(_chat_message(m, stock) for m in _turns(case))]


def brief_for(case: dict[str, Any]) -> TurnBrief:
    return TurnBrief(
        system_tag=SYSTEM_TAG,
        order=case.get("order", "No order in progress."),
        waiting=case.get("waiting"),
    )


def _turns(case: dict[str, Any]) -> list[dict[str, str]]:
    """`history` gives every turn; `messages` is shorthand for customer messages only."""
    if "history" in case:
        return case["history"]
    return [{"from": "customer", "text": text} for text in case["messages"]]


def _chat_message(turn: dict[str, str], stock: list[StockItem]) -> ChatMessage:
    text = _with_refs(turn["text"], stock)
    match turn["from"]:
        case "customer":
            return ChatMessage("user", customer_agent.neutralise_customer_text(text))
        case "system":
            return ChatMessage("user", customer_agent.system_note(text, SYSTEM_TAG))
        case "owner":
            return ChatMessage("assistant", f"(Shop owner) {text}")
        case "agent":
            return ChatMessage("assistant", text)
        case other:
            raise ValueError(f"Unknown sender {other!r}: use customer, agent, system or owner")


def _with_refs(text: str, stock: list[StockItem]) -> str:
    """`{id:Product|Variant}` in a case becomes that item's stock ID."""
    by_label = {f"{item.product}|{item.variant or ''}": item.ref or "" for item in stock}
    return re.sub(r"\{id:([^}]+)\}", lambda m: by_label.get(m.group(1), m.group(0)), text)


async def run_case(case: dict[str, Any], model: str | None) -> Result:
    stock = stock_items(case)
    messages = prompt_messages(case, stock)
    result = Result(case_id=case["id"], model=model or get_settings().llm_model)
    reply: CustomerReply | None = None
    error = ""
    for _ in range(2):  # one repair attempt, as in production
        started = time.perf_counter()
        try:
            completion = await llm.complete(messages, json_output=True, model=model)
        except llm.LLMError as exc:
            error = str(exc)
            break
        result.latency_ms += round((time.perf_counter() - started) * 1000)
        result.input_tokens += completion.input_tokens or 0
        result.output_tokens += completion.output_tokens or 0
        try:
            reply = customer_agent.parse_output(completion.content)
            break
        except customer_agent.AgentOutputError as exc:
            error = f"invalid output: {str(exc)[:200]}"
            messages = [
                *messages,
                ChatMessage("assistant", completion.content),
                ChatMessage("user", customer_agent.repair_instruction(exc)),
            ]
    result.checks.append(Check("valid_output", reply is not None, error))
    if reply is not None:
        result.reply, result.language = reply.reply, reply.language
        result.action = reply.action.model_dump(exclude_none=True) if reply.action else None
        result.checks += score(case, reply, stock, messages)
    return result


def score(
    case: dict[str, Any],
    reply: CustomerReply,
    stock: list[StockItem],
    messages: list[ChatMessage],
) -> list[Check]:
    expected = case.get("expected", {})
    checks = []
    if "reply_language" in expected:
        got = reply.language.lower().replace("_", "-")
        want = expected["reply_language"]
        checks.append(Check("reply_language", got == want, f"{got} (wanted {want})"))
    if "needs_owner" in expected:
        want = expected["needs_owner"]
        checks.append(Check("needs_owner", reply.needs_owner == want, f"{reply.needs_owner}"))
    if "action" in expected:
        got = reply.action.type if reply.action else None
        checks.append(Check("action", got == expected["action"], f"{got}"))
    if "items" in expected:
        got = ordered_items(reply, stock)
        want = Counter(
            (i["product"], i.get("variant"), int(i["quantity"])) for i in expected["items"]
        )
        checks.append(Check("items", got == want, f"{dict(got)}"))
    if "quote_id" in expected:
        got = reply.action.quote_id if reply.action else None
        checks.append(Check("quote_id", got == expected["quote_id"], f"{got}"))
    for pattern in expected.get("must_not_say", []):
        found = re.search(pattern, reply.reply, re.I)
        said = found.group(0) if found else ""
        checks.append(Check(f"must_not_say /{pattern}/", found is None, said))
    if expected.get("must_say_any"):
        hit = any(re.search(p, reply.reply, re.I) for p in expected["must_say_any"])
        checks.append(Check("must_say_any", hit, "none of " + ", ".join(expected["must_say_any"])))
    if expected.get("passes_checks", True) and reply.reply.strip():
        problems = validator.check(reply.reply, reply_facts(case, stock, messages))
        checks.append(Check("passes_checks", not problems, " ".join(problems)))
    return checks


def ordered_items(reply: CustomerReply, stock: list[StockItem]) -> Counter[tuple[str, Any, int]]:
    """What a quote_order asked for, as (product, variant, quantity)."""
    if reply.action is None or reply.action.order is None:
        return Counter()
    by_ref = {item.ref: item for item in stock}
    found: Counter[tuple[str, Any, int]] = Counter()
    for line in reply.action.order.items:
        item = by_ref.get((line.id or "").strip().lower())
        if item is not None:
            found[(item.product, item.variant, line.quantity)] += 1
        else:
            found[(line.product or f"unknown id {line.id}", line.variant, line.quantity)] += 1
    return found


def reply_facts(
    case: dict[str, Any], stock: list[StockItem], messages: list[ChatMessage]
) -> validator.ReplyFacts:
    amounts = {item.price_minor for item in stock}
    trusted = [brief_for(case).order] + [
        m.content for m in messages if customer_agent.is_system_note(m.content, SYSTEM_TAG)
    ]
    for text in trusted:
        amounts |= validator.amounts_in(text)
    last_customer = next((t["text"] for t in reversed(_turns(case)) if t["from"] == "customer"), "")
    return validator.ReplyFacts(amounts_minor=frozenset(amounts), customer_text=last_customer)


def load_cases(names: list[str], case_ids: list[str]) -> list[dict[str, Any]]:
    paths = sorted((EVALS_DIR / "datasets").glob("*.jsonl"))
    if names:
        paths = [p for p in paths if p.stem in names]
        missing = set(names) - {p.stem for p in paths}
        if missing:
            raise SystemExit(f"No dataset called {', '.join(sorted(missing))}")
    cases = []
    for path in paths:
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            if line.strip():
                case = json.loads(line)
                if "id" not in case or not ("messages" in case or "history" in case):
                    raise SystemExit(f"{path.name}:{number}: a case needs an id and messages")
                cases.append(case)
    if case_ids:
        cases = [c for c in cases if c["id"] in case_ids]
    return cases


def report(results: list[Result]) -> float:
    for result in results:
        failed = [c for c in result.checks if not c.ok]
        status = "PASS" if not failed else "FAIL"
        print(f"{status}  {result.case_id}  [{result.model}]  {result.latency_ms} ms")
        for check in failed:
            print(f"        x {check.name}: {check.detail}")
        if failed:
            shown = result.reply or json.dumps(result.action, ensure_ascii=False)
            print(f"        reply: {shown[:300]}")
    by_model: dict[str, list[Result]] = {}
    for result in results:
        by_model.setdefault(result.model, []).append(result)
    worst = 1.0
    print()
    for model, rows in by_model.items():
        score_ = sum(r.passed for r in rows) / len(rows)
        checks = [c for r in rows for c in r.checks]
        latency = sum(r.latency_ms for r in rows) / len(rows)
        tokens = sum(r.input_tokens + r.output_tokens for r in rows)
        print(
            f"{model}: {sum(r.passed for r in rows)}/{len(rows)} cases passed "
            f"({score_:.0%}), {sum(c.ok for c in checks)}/{len(checks)} checks, "
            f"avg {latency:.0f} ms, {tokens} tokens"
        )
        worst = min(worst, score_)
    return worst


async def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run eval datasets against live models.")
    parser.add_argument("--dataset", action="append", default=[], help="dataset file stem")
    parser.add_argument("--case", action="append", default=[], help="run only this case id")
    parser.add_argument("--model", action="append", default=[], help="model(s) to compare")
    parser.add_argument("--min-score", type=float, default=0.0, help="fail below this share")
    parser.add_argument("--concurrency", type=int, default=4)
    args = parser.parse_args(argv)

    cases = load_cases(args.dataset, args.case)
    if not cases:
        print("No cases to run.")
        return 1
    limit = asyncio.Semaphore(args.concurrency)

    async def one(case: dict[str, Any], model: str | None) -> Result:
        async with limit:
            return await run_case(case, model)

    models: list[str | None] = list(args.model) or [None]
    results = await asyncio.gather(*(one(c, m) for m in models for c in cases))
    worst = report(list(results))

    out = EVALS_DIR / "results" / f"{datetime.now(UTC):%Y%m%d-%H%M%S}.json"
    out.parent.mkdir(exist_ok=True)
    out.write_text(
        json.dumps(
            [
                {
                    "case": r.case_id,
                    "model": r.model,
                    "passed": r.passed,
                    "reply": r.reply,
                    "language": r.language,
                    "action": r.action,
                    "failed_checks": [c.__dict__ for c in r.checks if not c.ok],
                    "latency_ms": r.latency_ms,
                    "tokens": r.input_tokens + r.output_tokens,
                }
                for r in results
            ],
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )
    print(f"Details: {out.relative_to(EVALS_DIR.parent)}")
    return 0 if worst >= args.min_score else 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
