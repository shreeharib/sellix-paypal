"""Inbound protection (agent-phase-2.md section 12): the model never gets a huge passage, and one
customer can't run up the shop's bill.

- Text is normalised and capped before the model sees it; the full text stays in `messages`.
- A message far too long gets a fixed template, without a model call.
- Turns per customer are limited per hour and per day: one polite template, then silence.
- Each shop has a daily AI budget: at 80% it's flagged, at 100% only templates and Ask me.

Counts live in Postgres (agent_turns, messages), so they survive restarts and work with
several workers.
"""

import re
import unicodedata
import uuid
from dataclasses import dataclass
from datetime import datetime, time, timedelta
from decimal import Decimal
from zoneinfo import ZoneInfo

import structlog
from sqlalchemy import func, select

from app.core.config import get_settings
from app.core.db import session_scope
from app.modules.agent.models import AgentTurn
from app.modules.merchants.schemas import MerchantInfo

log = structlog.get_logger()

# Zero-width and formatting characters (ZWJ and ZWNJ stay: Indic scripts need them).
_INVISIBLE = re.compile(r"[​⁠﻿­᠎⁡-⁤‪-‮]")
_KEEP = {"\n", "\t", "‌", "‍"}


@dataclass(frozen=True)
class Gate:
    stop: bool
    reason: str | None = None  # too_long | rate_limited | silenced | over_budget
    template: str | None = None  # the fixed message to send instead, if any
    question: str | None = None  # for the shop owner's Ask me


OPEN = Gate(False)


def normalise(text: str) -> str:
    text = unicodedata.normalize("NFKC", text)
    text = _INVISIBLE.sub("", text)
    text = "".join(ch for ch in text if ch in _KEEP or unicodedata.category(ch) not in ("Cc", "Cf"))
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def shorten(text: str, limit: int, marker: str) -> str:
    """At most `limit` characters of the customer's own words, then the marker."""
    if len(text) <= limit:
        return text
    return text[: limit - 1].rstrip() + " " + marker


async def check(
    *,
    turn_id: uuid.UUID,
    merchant: MerchantInfo,
    conversation_id: uuid.UUID,
    customer_handle: str,
    trigger_text: str,
    now: datetime,
) -> Gate:
    settings = get_settings()
    if len(trigger_text) > settings.inbound_too_long_chars:
        log.warning("agent.message_too_long", conversation_id=str(conversation_id))
        return Gate(True, "too_long", "too_long")

    async with session_scope() as session:
        turns = (
            select(func.count())
            .select_from(AgentTurn)
            .where(AgentTurn.conversation_id == conversation_id, AgentTurn.id != turn_id)
        )
        last_hour = await session.scalar(
            turns.where(AgentTurn.started_at > now - timedelta(hours=1))
        )
        last_day = await session.scalar(turns.where(AgentTurn.started_at > now - timedelta(days=1)))
        if (last_hour or 0) >= settings.agent_turns_per_hour or (
            last_day or 0
        ) >= settings.agent_turns_per_day:
            told = await session.scalar(
                turns.where(
                    AgentTurn.started_at > now - timedelta(hours=1),
                    AgentTurn.status == "gated",
                    AgentTurn.error == "rate_limited",
                )
            )
            if told:
                return Gate(True, "silenced")
            return Gate(
                True,
                "rate_limited",
                "rate_limited",
                f"Unusual activity from {customer_handle}: more messages than a customer usually "
                "sends. The assistant has paused replies to them for now; please take a look.",
            )

        day_start = datetime.combine(
            now.astimezone(ZoneInfo(merchant.timezone)).date(), time(0), ZoneInfo(merchant.timezone)
        )
        spent = await session.scalar(
            select(func.coalesce(func.sum(AgentTurn.cost_usd), 0)).where(
                AgentTurn.merchant_id == merchant.id, AgentTurn.started_at >= day_start
            )
        )
    budget = merchant.ai_daily_budget_usd or Decimal(str(settings.agent_daily_budget_usd))
    spent = Decimal(str(spent or 0))
    if budget > 0 and spent >= budget:
        log.error("agent.over_budget", merchant_id=str(merchant.id), spent=str(spent))
        return Gate(
            True,
            "over_budget",
            "holding",
            "Today's AI budget is used up, so the assistant is only sending holding messages "
            "until tomorrow. Please answer this customer.",
        )
    if budget > 0 and spent >= budget * Decimal("0.8"):
        log.warning("agent.budget_soft_limit", merchant_id=str(merchant.id), spent=str(spent))
    return OPEN
