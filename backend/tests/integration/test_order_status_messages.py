"""The merchant moves an order on in the app; the customer hears about it in their chat.

9 Nov: "Mark as ready for pickup" changed the order but the customer was never told.
"""

import pytest
from procrastinate.testing import InMemoryConnector
from sqlalchemy import select

from app.core.db import session_scope
from app.modules.channels.models import ChannelConnection
from app.modules.conversations import service as conversations
from app.modules.conversations.models import Message
from app.modules.orders.models import Order
from tests.integration.factories import Instagram, ScriptedModel
from tests.integration.test_api import api, bearer, sign_in_as  # noqa: F401 (fixture)
from tests.integration.test_payment_retry_chat import (  # noqa: F401 (fixture)
    simulator_on,
    unpaid_order,
)

pytestmark = pytest.mark.anyio


async def status_messages() -> list[Message]:
    async with session_scope() as session:
        return list(
            await session.scalars(
                select(Message)
                .where(Message.details["kind"].as_string().like("order_%"))
                .order_by(Message.created_at)
            )
        )


async def test_marking_a_pickup_order_ready_tells_the_customer_once(
    api,  # noqa: ANN001, F811
    v2_shop: ChannelConnection,
    model: ScriptedModel,
    instagram: Instagram,
    deferred_jobs: InMemoryConnector,
    simulator_on: None,  # noqa: F811
) -> None:
    order = await unpaid_order(v2_shop, model)
    headers = bearer(await sign_in_as(v2_shop.merchant_id))

    async def move(status: str) -> None:
        response = await api.patch(
            f"/v1/orders/{order.id}/status", headers=headers, json={"status": status}
        )
        assert response.status_code == 200, response.text

    await move("confirmed")  # "Accept order": nothing for the customer
    assert await status_messages() == []

    await move("ready")
    await move("confirmed")  # the app's undo
    await move("ready")  # and ready again: still one message

    [ready] = await status_messages()
    assert ready.details["kind"] == "order_ready_pickup"
    assert f"#{order.number}" in ready.body and "ready for pickup" in ready.body

    async with session_scope() as session:
        conversation_id = await session.scalar(select(Order.conversation_id))
    assert conversation_id is not None
    await conversations.deliver_outbox(conversation_id)
    assert any("ready for pickup" in text for text in instagram.texts())

    await move("completed")  # picked up: nothing more to say
    assert len(await status_messages()) == 1
