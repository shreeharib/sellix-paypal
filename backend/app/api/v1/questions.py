"""The "Ask me" inbox: the agent's questions to the merchant, and the merchant's answers."""

import uuid
from collections.abc import Mapping
from dataclasses import replace
from typing import Annotated, Any, Literal

from fastapi import APIRouter, HTTPException, Query

from app.api.v1 import schemas
from app.api.v1.deps import Shop
from app.core.db import session_scope
from app.modules.agent import service as agent
from app.modules.conversations import service as conversations
from app.modules.escalations import service as escalations
from app.modules.escalations.schemas import EscalationItem

router = APIRouter(prefix="/questions", tags=["questions"])


@router.get("")
async def list_questions(
    shop: Shop,
    status: Annotated[Literal["open", "answered", "closed"] | None, Query()] = "open",
) -> list[schemas.Question]:
    async with session_scope() as session:
        found = await escalations.list_escalations(session, shop.merchant_id, status=status)
        windows = await conversations.windows_for(session, {e.conversation_id for e in found})
    return [_question(escalation, windows) for escalation in found]


@router.post("/{question_id}/answer")
async def answer_question(
    shop: Shop, question_id: uuid.UUID, body: schemas.Answer
) -> schemas.Question:
    """Record the answer and pass it on, as Instagram's 24-hour window allows."""
    try:
        async with session_scope() as session:
            answered = await escalations.answer(session, shop.merchant_id, question_id, body.answer)
    except escalations.EscalationNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    if body.always:
        await agent.save_rule(
            merchant_id=shop.merchant_id,
            question=answered.question,
            answer=answered.answer or body.answer,
            source_escalation_id=answered.id,
        )
    delivery = await conversations.relay_owner_answer(answered)
    async with session_scope() as session:
        windows = await conversations.windows_for(session, {answered.conversation_id})
    return _question(replace(answered, answer_delivery=delivery), windows)


@router.post("/{question_id}/close")
async def close_question(shop: Shop, question_id: uuid.UUID) -> schemas.Question:
    try:
        async with session_scope() as session:
            closed = await escalations.close(session, shop.merchant_id, question_id)
            windows = await conversations.windows_for(session, {closed.conversation_id})
    except escalations.EscalationNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return _question(closed, windows)


def _question(escalation: EscalationItem, windows: Mapping[uuid.UUID, Any]) -> schemas.Question:
    current = windows.get(escalation.conversation_id)
    return schemas.Question(
        id=escalation.id,
        conversation_id=escalation.conversation_id,
        question=escalation.question,
        status=escalation.status,
        answer=escalation.answer,
        created_at=escalation.created_at,
        answered_at=escalation.answered_at,
        window_closes_at=current.closes_at if current else None,
        window_state=current.state if current else None,
        answer_delivery=escalation.answer_delivery,
    )
