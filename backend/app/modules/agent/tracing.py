"""Turn traces: a row per turn, a row per model or tool call (agent-phase-2.md 13.3 and 16).

They are also how a crashed turn resumes: a retried turn for the same customer message finds
its row, replays the stored steps, and continues where it stopped.
"""

import uuid
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from decimal import Decimal
from typing import Any

from sqlalchemy import func, select, update
from sqlalchemy.dialects.postgresql import insert as pg_insert

from app.core.db import session_scope
from app.modules.agent.models import AgentTurn, TurnStep


@dataclass
class Trace:
    turn_id: uuid.UUID
    steps: dict[str, dict[str, Any]] = field(default_factory=dict)  # idempotency key -> result

    @property
    def resumed(self) -> bool:
        return bool(self.steps)


async def start(
    *,
    merchant_id: uuid.UUID,
    conversation_id: uuid.UUID,
    trigger_message_id: uuid.UUID,
    stage: str,
    mode: str = "live",
) -> Trace | None:
    """The turn for this customer message: new, or resumed. None if it already finished."""
    async with session_scope() as session:
        await session.execute(
            pg_insert(AgentTurn)
            .values(
                merchant_id=merchant_id,
                conversation_id=conversation_id,
                trigger_message_id=trigger_message_id,
                stage_before=stage,
                mode=mode,
            )
            .on_conflict_do_nothing(index_elements=["conversation_id", "trigger_message_id"])
        )
        turn = await session.scalar(
            select(AgentTurn).where(
                AgentTurn.conversation_id == conversation_id,
                AgentTurn.trigger_message_id == trigger_message_id,
            )
        )
        if turn is None or turn.status != "running":
            return None
        steps = await session.scalars(select(TurnStep).where(TurnStep.turn_id == turn.id))
        return Trace(turn.id, {step.idempotency_key: step.result for step in steps})


async def record(
    trace: Trace,
    *,
    step: int,
    kind: str,
    name: str,
    key: str,
    request: dict[str, Any],
    result: dict[str, Any],
    input_tokens: int | None = None,
    output_tokens: int | None = None,
    latency_ms: int | None = None,
) -> None:
    trace.steps[key] = result
    async with session_scope() as session:
        await session.execute(
            pg_insert(TurnStep)
            .values(
                turn_id=trace.turn_id,
                step=step,
                kind=kind,
                name=name,
                idempotency_key=key,
                request=request,
                result=result,
                input_tokens=input_tokens,
                output_tokens=output_tokens,
                latency_ms=latency_ms,
            )
            .on_conflict_do_nothing(index_elements=["idempotency_key"])
        )


async def finish(
    trace: Trace,
    status: str,
    *,
    stage_after: str,
    playbook: str,
    prompt_refs: set[str],
    latency_ms: int,
    error: str | None = None,
    would_send: str | None = None,
) -> None:
    async with session_scope() as session:
        steps = list(
            await session.scalars(select(TurnStep).where(TurnStep.turn_id == trace.turn_id))
        )
        models = [step for step in steps if step.kind == "model"]
        cost = sum(
            (
                Decimal(str(step.result.get("cost_usd")))
                for step in models
                if step.result.get("cost_usd") is not None
            ),
            Decimal(0),
        )
        await session.execute(
            update(AgentTurn)
            .where(AgentTurn.id == trace.turn_id)
            .values(
                status=status,
                stage_after=stage_after,
                playbook=playbook,
                prompt_refs=sorted(prompt_refs),
                models=sorted({str(step.result.get("model")) for step in models}),
                model_calls=len(models),
                tool_calls=len(steps) - len(models),
                input_tokens=sum(step.input_tokens or 0 for step in models),
                output_tokens=sum(step.output_tokens or 0 for step in models),
                cost_usd=cost
                if any(s.result.get("cost_usd") is not None for s in models)
                else None,
                latency_ms=latency_ms,
                error=error,
                would_send=would_send,
                finished_at=func.now(),
            )
        )


async def last_turn(conversation_id: uuid.UUID) -> dict[str, Any] | None:
    """The latest turn of a chat and the tools it used (simulator and evals)."""
    async with session_scope() as session:
        turn = await session.scalar(
            select(AgentTurn)
            .where(AgentTurn.conversation_id == conversation_id)
            .order_by(AgentTurn.started_at.desc())
            .limit(1)
        )
        if turn is None:
            return None
        steps = await session.scalars(
            select(TurnStep)
            .where(TurnStep.turn_id == turn.id, TurnStep.kind == "tool")
            .order_by(TurnStep.created_at)
        )
        tools = [step.name for step in steps]
    return {
        "id": str(turn.id),
        "status": turn.status,
        "stage_before": turn.stage_before,
        "stage_after": turn.stage_after,
        "playbook": turn.playbook,
        "tools": tools,
        "model_calls": turn.model_calls,
        "cost_usd": float(turn.cost_usd) if turn.cost_usd is not None else None,
        "latency_ms": turn.latency_ms,
    }


async def first_step(
    turn_id: uuid.UUID,
) -> tuple[uuid.UUID, uuid.UUID, dict[str, Any] | None] | None:
    """(conversation, trigger message, first model step's result) of a turn, for replay."""
    async with session_scope() as session:
        turn = await session.get(AgentTurn, turn_id)
        if turn is None:
            return None
        step = await session.scalar(
            select(TurnStep.result)
            .where(TurnStep.turn_id == turn_id, TurnStep.kind == "model")
            .order_by(TurnStep.step)
            .limit(1)
        )
        return turn.conversation_id, turn.trigger_message_id, step


async def shadow_turns(merchant_id: uuid.UUID, since: datetime) -> list[AgentTurn]:
    async with session_scope() as session:
        return list(
            await session.scalars(
                select(AgentTurn)
                .where(
                    AgentTurn.merchant_id == merchant_id,
                    AgentTurn.mode == "shadow",
                    AgentTurn.started_at >= since,
                )
                .order_by(AgentTurn.started_at)
            )
        )


async def stalled_conversations(older_than: timedelta) -> list[uuid.UUID]:
    """Conversations whose turn is still `running` long after it started (a crashed worker)."""
    async with session_scope() as session:
        rows = await session.scalars(
            select(AgentTurn.conversation_id)
            .where(
                AgentTurn.status == "running",
                AgentTurn.started_at < datetime.now(UTC) - older_than,
                AgentTurn.started_at > datetime.now(UTC) - timedelta(hours=24),
            )
            .distinct()
        )
        return list(rows)
