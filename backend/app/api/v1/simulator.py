"""The simulator: chat with your own shop's assistant through the real pipeline.

Messages go through the same webhook handling, turn engine, guardrails and outbox as
Instagram, on a web chat channel that never leaves sellix. Used by developers, end-to-end
tests, the evals runner and the hackathon judges (agent-phase-2.md section 17).
"""

import uuid
from typing import Any

from fastapi import APIRouter, Query
from pydantic import BaseModel, Field

from app.api.v1.deps import Shop
from app.core.db import session_scope
from app.modules.agent import service as agent
from app.modules.channels import service as channels
from app.modules.channels.schemas import IncomingMessage
from app.modules.conversations import service as conversations

router = APIRouter(prefix="/simulator", tags=["simulator"])


class SimulatedMessage(BaseModel):
    text: str = Field(default="", max_length=20000)
    quick_reply: str | None = Field(default=None, max_length=200)  # a tapped button's payload
    customer: str = Field(default="tester", min_length=1, max_length=60)


class SimulatorChat(BaseModel):
    messages: list[dict[str, Any]]
    turn: dict[str, Any] | None


@router.post("/messages")
async def send(shop: Shop, body: SimulatedMessage) -> SimulatorChat:
    """Write to the shop as a customer; the assistant answers before this returns."""
    async with session_scope() as session:
        account = await channels.simulator_account(session, shop.merchant_id)
        turn = await conversations.handle_incoming(
            session,
            IncomingMessage(
                channel=channels.WEBCHAT,
                shop_account_id=account,
                customer_id=_customer(body.customer),
                message_id=f"sim-{uuid.uuid4().hex}",
                text=body.text,
                quick_reply_payload=body.quick_reply,
            ),
        )
        engine = await conversations.engine_for(session, turn.conversation_id) if turn else None
    if turn is not None:
        if engine in ("v1", "shadow"):
            await conversations.run_turn(turn.conversation_id)
        else:
            await agent.run_turn(turn.conversation_id)
    return await _chat(shop, body.customer)


@router.get("/messages")
async def read(shop: Shop, customer: str = Query(default="tester", max_length=60)) -> SimulatorChat:
    return await _chat(shop, customer)


async def _chat(shop: Shop, customer: str) -> SimulatorChat:
    async with session_scope() as session:
        conversation_id = await conversations.find_conversation(
            session, shop.merchant_id, channels.WEBCHAT, _customer(customer)
        )
        if conversation_id is None:
            return SimulatorChat(messages=[], turn=None)
        messages = await conversations.transcript(session, shop.merchant_id, conversation_id)
    return SimulatorChat(messages=messages, turn=await agent.last_turn(conversation_id))


def _customer(name: str) -> str:
    return f"sim-{name}"
