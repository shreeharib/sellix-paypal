"""The Chats screen: conversations, their messages, and the per-chat agent switch."""

import uuid
from typing import Annotated

from fastapi import APIRouter, HTTPException, Query

from app.api.v1 import schemas
from app.api.v1.deps import Shop
from app.core.db import session_scope
from app.modules.agent import service as agent
from app.modules.conversations import service as conversations

router = APIRouter(prefix="/conversations", tags=["chats"])


@router.get("")
async def list_conversations(shop: Shop) -> list[schemas.Conversation]:
    async with session_scope() as session:
        found = await conversations.list_conversations(session, shop.merchant_id)
    return [
        schemas.Conversation(
            id=chat.id,
            channel=chat.channel,
            customer_handle=chat.customer_handle,
            agent_active=chat.agent_active,
            agent_paused_reason=chat.agent_paused_reason,
            last_message_sender=chat.last_message_sender,
            last_message_body=chat.last_message_body,
            last_message_at=chat.last_message_at,
        )
        for chat in found
    ]


@router.get("/{conversation_id}/messages")
async def list_messages(
    shop: Shop,
    conversation_id: uuid.UUID,
    limit: Annotated[int, Query(ge=1, le=500)] = 100,
) -> list[schemas.ChatMessage]:
    async with session_scope() as session:
        try:
            await conversations.get_conversation(session, shop.merchant_id, conversation_id)
        except LookupError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        found = await conversations.list_messages(
            session, shop.merchant_id, conversation_id, limit=limit
        )
    return [schemas.ChatMessage(**vars(message)) for message in found]


@router.put("/{conversation_id}/agent")
async def switch_agent(
    shop: Shop, conversation_id: uuid.UUID, body: schemas.AgentSwitch
) -> schemas.AgentSwitch:
    """The per-chat agent switch ("I'll reply myself" turns it off)."""
    async with session_scope() as session:
        try:
            await conversations.get_conversation(session, shop.merchant_id, conversation_id)
        except LookupError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        await conversations.set_agent_active(session, conversation_id, body.active)
    return body


@router.get("/{conversation_id}/memory")
async def customer_memory(shop: Shop, conversation_id: uuid.UUID) -> list[schemas.MemoryFact]:
    """What the assistant remembers about this chat's customer (agent-phase-2.md 8.2)."""
    customer_id = await _customer_of(shop, conversation_id)
    facts = await agent.customer_memory(shop.merchant_id, customer_id)
    return [schemas.MemoryFact(key=f.key, value=f.value, updated_at=f.updated_at) for f in facts]


@router.delete("/{conversation_id}/memory/{key}", status_code=204)
async def forget_customer_fact(shop: Shop, conversation_id: uuid.UUID, key: str) -> None:
    customer_id = await _customer_of(shop, conversation_id)
    if not await agent.forget_customer_fact(shop.merchant_id, customer_id, key):
        raise HTTPException(status_code=404, detail="Nothing remembered under that key")


async def _customer_of(shop: Shop, conversation_id: uuid.UUID) -> uuid.UUID:
    try:
        async with session_scope() as session:
            conversation = await conversations.get_conversation(
                session, shop.merchant_id, conversation_id
            )
    except LookupError as exc:
        raise HTTPException(status_code=404, detail="Conversation not found") from exc
    return conversation.customer_id


class DraftApproval(schemas.BaseModel):
    text: str | None = schemas.Field(default=None, max_length=2000)  # the merchant's edit


@router.get("/{conversation_id}/drafts")
async def list_drafts(shop: Shop, conversation_id: uuid.UUID) -> list[schemas.ChatMessage]:
    """Draft mode: the assistant's replies waiting for the merchant's approval."""
    try:
        async with session_scope() as session:
            found = await conversations.drafts(session, shop.merchant_id, conversation_id)
    except LookupError as exc:
        raise HTTPException(status_code=404, detail="Conversation not found") from exc
    return [schemas.ChatMessage(**vars(message)) for message in found]


@router.post("/{conversation_id}/drafts/{message_id}/approve")
async def approve_draft(
    shop: Shop, conversation_id: uuid.UUID, message_id: uuid.UUID, body: DraftApproval | None = None
) -> dict[str, bool]:
    try:
        async with session_scope() as session:
            done = await conversations.approve_draft(
                session, shop.merchant_id, conversation_id, message_id, body.text if body else None
            )
    except LookupError as exc:
        raise HTTPException(status_code=404, detail="Conversation not found") from exc
    if not done:
        raise HTTPException(status_code=404, detail="No such draft")
    await conversations.deliver_outbox(conversation_id)
    return {"sent": True}


@router.post("/{conversation_id}/drafts/{message_id}/discard")
async def discard_draft(
    shop: Shop, conversation_id: uuid.UUID, message_id: uuid.UUID
) -> dict[str, bool]:
    try:
        async with session_scope() as session:
            done = await conversations.discard_draft(
                session, shop.merchant_id, conversation_id, message_id
            )
    except LookupError as exc:
        raise HTTPException(status_code=404, detail="Conversation not found") from exc
    if not done:
        raise HTTPException(status_code=404, detail="No such draft")
    return {"discarded": True}
