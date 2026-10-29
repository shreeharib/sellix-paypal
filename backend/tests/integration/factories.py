"""Shared IDs, builders and fakes for the database tests."""

from collections.abc import Sequence
from typing import Any

from app.core.db import session_scope
from app.modules.agent import llm
from app.modules.channels import service as channels
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


Step = list[tuple[str, dict[str, Any]]] | Exception


class ScriptedModel:
    """Answers each model call with the next scripted list of tool calls."""

    def __init__(self, *steps: Step) -> None:
        self.steps = list(steps)
        self.calls: list[tuple[list[llm.Message], list[str]]] = []

    def then(self, *steps: Step) -> None:
        self.steps.extend(steps)

    async def __call__(
        self, messages: list[llm.Message], *, tools: Sequence[llm.ToolSpec] = ()
    ) -> llm.Completion:
        self.calls.append((list(messages), [tool.name for tool in tools]))
        step = self.steps.pop(0)
        if isinstance(step, Exception):
            raise step
        return llm.Completion(
            content="",
            model="test-model",
            input_tokens=100,
            output_tokens=10,
            latency_ms=5,
            tool_calls=tuple(
                llm.ToolCall(f"call_{n}", name, args) for n, (name, args) in enumerate(step)
            ),
        )


class Instagram:
    def __init__(self, fail_with: channels.SendFailed | None = None) -> None:
        self.fail_with = fail_with
        self.sent: list[dict[str, Any]] = []

    async def __call__(
        self, credentials: channels.SendCredentials, recipient_id: str, text: str, **extra: Any
    ) -> str:
        if self.fail_with:
            raise self.fail_with
        self.sent.append({"text": text, **extra})
        return f"ig-{len(self.sent)}"

    async def attachment(
        self, credentials: channels.SendCredentials, recipient_id: str, attachment: dict[str, Any]
    ) -> str:
        if self.fail_with:
            raise self.fail_with
        self.sent.append({"text": "", "attachment": attachment})
        return f"ig-{len(self.sent)}"

    def texts(self) -> list[str]:
        return [message["text"] for message in self.sent]
