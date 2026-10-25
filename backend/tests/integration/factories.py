"""Shared IDs and builders for the database tests."""

from app.core.db import session_scope
from app.modules.channels.schemas import IncomingMessage
from app.modules.conversations import service as conversations

SHOP_ACCOUNT_ID = "17841400000000001"
CUSTOMER_ID = "7000000000000002"


async def start_conversation(
    text: str = "rendu chocolate cookie venum", message_id: str = "m-1"
) -> conversations.TurnRequest:
    """A customer DM to the `shop` fixture's account; returns the turn it asks for."""
    async with session_scope() as session:
        turn = await conversations.handle_incoming(
            session,
            IncomingMessage(
                channel="instagram",
                shop_account_id=SHOP_ACCOUNT_ID,
                customer_id=CUSTOMER_ID,
                message_id=message_id,
                text=text,
            ),
        )
    assert turn is not None
    return turn
