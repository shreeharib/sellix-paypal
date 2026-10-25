"""The Chats screen: conversations, their messages, and the per-chat agent switch."""

import uuid
from typing import Annotated

from fastapi import APIRouter, HTTPException, Query

from app.api.v1 import schemas
from app.api.v1.deps import Shop
from app.core.db import session_scope
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
