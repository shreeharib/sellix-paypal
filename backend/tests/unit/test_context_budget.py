"""The context the model sees stays within its token budgets (agent-phase-2.md section 8.1)."""

import uuid
from datetime import UTC, date, datetime, timedelta

import pytest

from app.core.config import get_settings
from app.modules.agent import context
from app.modules.agent.tools.registry import TurnContext
from app.modules.conversations.schemas import ChatLine
from app.modules.inventory.schemas import StockItem
from app.modules.merchants.schemas import MerchantInfo

NOW = datetime(2026, 10, 30, 12, 0, tzinfo=UTC)


def turn(stock: list[StockItem] | None = None) -> TurnContext:
    return TurnContext(
        turn_id=uuid.uuid4(),
        merchant=MerchantInfo(uuid.uuid4(), "Sweet Crumbs", "Asia/Kolkata", True, NOW, NOW),
        conversation_id=uuid.uuid4(),
        customer_id=uuid.uuid4(),
        trigger_message_id=uuid.uuid4(),
        trigger_created_at=NOW,
        customer_text="hi",
        business_date=date(2026, 10, 30),
        now=NOW,
        stock=stock or [StockItem("Scoop cookie", "Chocolate", 6000, "INR", 10, uuid.uuid4())],
        stage="browsing",
        language="en",
    )


def chat(n: int, text: str) -> list[ChatLine]:
    lines = []
    for i in range(n):
        sender = "customer" if i % 2 == 0 else "agent"
        lines.append(ChatLine(uuid.uuid4(), sender, f"{i}: {text}", NOW - timedelta(minutes=n - i)))
    return lines


def build(ctx: TurnContext, history: list[ChatLine], **extra: object) -> context.Context:
    return context.build(
        ctx,
        history=history,
        profile="Home bakery.",
        draft={},
        quote=None,
        open_questions=[],
        window_closing=False,
        trigger=history[-1],
        **extra,  # pyright: ignore[reportArgumentType]
    )


def total_tokens(built: context.Context) -> int:
    return sum(context.estimate_tokens(m.content) for m in built.messages)


def test_tokens_are_estimated_from_bytes_so_tamil_counts_more() -> None:
    assert context.estimate_tokens("a" * 400) == 100
    assert context.estimate_tokens("ஆ" * 400) == 300  # 3 bytes a character


def test_the_customer_section_keeps_the_most_useful_facts_within_its_budget() -> None:
    facts = [
        ("name", "Priya"),
        ("preferred_language", "ta-en"),
        ("address", "12 Lake Road, " + "near the big temple, " * 20),
        ("occasion", "daughter's birthday on 4 Nov"),
    ]
    history = chat(1, "same as last time")

    built = build(turn(), history, facts=facts)

    system = built.messages[0].content
    assert "- name: Priya" in system and "- preferred_language: ta-en" in system
    section = system.split("# About this customer")[1].split("#")[0]
    assert context.estimate_tokens(section) <= get_settings().agent_customer_facts_tokens


def test_a_large_menu_is_summarised_and_search_is_suggested() -> None:
    stock = [
        StockItem(f"Item {n}", None, 1000, "INR", 5, uuid.uuid4())
        for n in range(get_settings().agent_menu_items + 10)
    ]

    built = build(turn(stock), chat(1, "hi"))

    system = built.messages[0].content
    assert "Item 0 |" not in system
    assert f"{len(stock)} items" in system and "search_catalog" in system


def test_long_history_is_trimmed_to_the_budget_keeping_the_newest_messages() -> None:
    history = chat(20, "x" * 1500)  # about 6,500 tokens in all

    built = build(turn(), history)

    assert total_tokens(built) <= get_settings().agent_context_tokens
    contents = [m.content for m in built.messages[1:]]
    assert contents[-1].startswith("19: ")  # the message this turn answers
    assert len(contents) < 20  # older ones were dropped
    numbers = [int(c.split(":")[0]) for c in contents]
    assert numbers == sorted(numbers) and numbers[-1] == 19


def test_the_summary_goes_before_older_messages_but_is_dropped_if_the_system_part_is_too_big(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(get_settings(), "agent_context_tokens", 1500)  # the system part is ~1,950
    rules = [(f"Question {n}?", "y" * 200) for n in range(20)]

    built = build(
        turn(),
        chat(3, "hello"),
        rules=rules,
        summary="Likes chocolate. " * 50,
        glossary=[("seri", "ok")],
    )

    system = built.messages[0].content
    assert "# Earlier in this conversation" not in system
    assert built.messages[-1].content.startswith("2: ")  # the latest message is always kept
    assert total_tokens(built) <= 1500 + context.estimate_tokens(built.messages[-1].content)
