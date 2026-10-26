import pytest
from sqlalchemy import select

from app.core.db import session_scope
from app.modules.agent import llm
from app.modules.agent import service as agent
from app.modules.agent.models import AiUsage
from app.modules.agent.schemas import ChatMessage
from app.modules.channels.models import ChannelConnection
from app.modules.inventory import service as inventory
from app.modules.inventory.schemas import OpeningStockLine
from app.modules.merchants import hours
from app.modules.merchants import service as merchants
from app.modules.shop_profile import service as shop_profile
from tests.integration.factories import start_conversation

pytestmark = pytest.mark.anyio

VALID = '{"reply": "Chocolate or red velvet?", "language": "en", "needs_owner": false}'


class FakeModel:
    def __init__(self, *outputs: str | Exception) -> None:
        self.outputs = list(outputs)
        self.calls: list[list[ChatMessage]] = []

    async def __call__(
        self, messages: list[ChatMessage], *, json_output: bool = False
    ) -> llm.Completion:
        self.calls.append(messages)
        output = self.outputs.pop(0)
        if isinstance(output, Exception):
            raise output
        return llm.Completion(
            content=output, model="test-model", input_tokens=120, output_tokens=20, latency_ms=900
        )


async def test_reply_uses_the_shop_profile_and_todays_stock(
    shop: ChannelConnection, monkeypatch: pytest.MonkeyPatch
) -> None:
    async with session_scope() as session:
        merchant = await merchants.get_merchant(session, shop.merchant_id)
        await shop_profile.save_profile(session, merchant.id, "# Sweet Crumbs\nHome bakery.")
        await merchants.set_opening_hours(
            session, merchant.id, hours.parse_spec("mon=closed tue-sun=09:00-20:00")
        )
        await inventory.set_opening_stock(
            session,
            merchant_id=merchant.id,
            business_date=merchants.business_date(merchant),
            lines=[OpeningStockLine("Scoop cookie", "Chocolate", 6000, 10)],
        )
    turn = await start_conversation("2 scoop cookies please")
    model = FakeModel(VALID)
    monkeypatch.setattr(llm, "complete", model)

    reply = await agent.reply_to_customer(
        merchant_id=shop.merchant_id,
        conversation_id=turn.conversation_id,
        history=[ChatMessage("user", "2 scoop cookies please")],
        brief=agent.new_turn_brief(order="No order in progress."),
    )

    system_prompt = model.calls[0][0].content
    assert reply.reply == "Chocolate or red velvet?"
    assert "# Sweet Crumbs" in system_prompt
    assert "Scoop cookie (Chocolate): ₹60, 10 left" in system_prompt
    assert "(Asia/Kolkata). The shop is " in system_prompt
    assert "- Monday: closed\n- Tuesday: 9:00 am to 8:00 pm" in system_prompt
    async with session_scope() as session:
        usage = await session.scalar(select(AiUsage))
    assert usage is not None
    assert (usage.succeeded, usage.input_tokens, usage.conversation_id) == (
        True,
        120,
        turn.conversation_id,
    )


async def test_invalid_output_gets_one_repair_attempt(
    shop: ChannelConnection, monkeypatch: pytest.MonkeyPatch
) -> None:
    turn = await start_conversation()
    model = FakeModel("Sure! Which flavour?", VALID)
    monkeypatch.setattr(llm, "complete", model)

    reply = await agent.reply_to_customer(
        merchant_id=shop.merchant_id,
        conversation_id=turn.conversation_id,
        history=[],
        brief=agent.new_turn_brief(order="No order in progress."),
    )

    assert reply.reply == "Chocolate or red velvet?"
    assert "couldn't be used" in model.calls[1][-1].content
    async with session_scope() as session:
        outcomes = list(await session.scalars(select(AiUsage.succeeded)))
    assert sorted(outcomes) == [False, True]


async def test_model_failure_raises_agent_unavailable(
    shop: ChannelConnection, monkeypatch: pytest.MonkeyPatch
) -> None:
    turn = await start_conversation()
    monkeypatch.setattr(llm, "complete", FakeModel(llm.LLMError("503")))

    with pytest.raises(agent.AgentUnavailable):
        await agent.reply_to_customer(
            merchant_id=shop.merchant_id,
            conversation_id=turn.conversation_id,
            history=[],
            brief=agent.new_turn_brief(order="No order in progress."),
        )
