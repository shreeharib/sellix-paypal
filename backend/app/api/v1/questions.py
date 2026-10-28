"""The "Ask me" inbox: the agent's questions to the merchant, and the merchant's answers."""

import uuid
from typing import Annotated, Literal

from fastapi import APIRouter, HTTPException, Query

from app.api.v1 import schemas
from app.api.v1.deps import Shop
from app.core.db import session_scope
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
    return [_question(escalation) for escalation in found]


@router.post("/{question_id}/answer")
async def answer_question(
    shop: Shop, question_id: uuid.UUID, body: schemas.Answer
) -> schemas.Question:
    """Record the answer; the agent then passes it on to the customer in their language."""
    try:
        async with session_scope() as session:
            escalation = await escalations.answer(
                session, shop.merchant_id, question_id, body.answer
            )
            result = _question(escalation)
    except escalations.EscalationNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    await conversations.inform_customer(
        result.conversation_id,
        f'The shop owner answered your question "{result.question}": "{result.answer}". '
        "Pass this on to the customer and continue helping them.",
    )
    return result


@router.post("/{question_id}/close")
async def close_question(shop: Shop, question_id: uuid.UUID) -> schemas.Question:
    try:
        async with session_scope() as session:
            return _question(await escalations.close(session, shop.merchant_id, question_id))
    except escalations.EscalationNotFound as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


def _question(escalation: EscalationItem) -> schemas.Question:
    return schemas.Question(
        id=escalation.id,
        conversation_id=escalation.conversation_id,
        question=escalation.question,
        status=escalation.status,
        answer=escalation.answer,
        created_at=escalation.created_at,
        answered_at=escalation.answered_at,
    )
