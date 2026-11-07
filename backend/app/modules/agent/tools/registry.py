"""Tools: typed arguments, the stages each is allowed in, and how they run (section 5.1).

- The model sees only the tools allowed in the conversation's current stage. A call to any
  other tool returns an error result; it isn't run.
- Results are JSON: {"ok": true, "data": {...}} or {"ok": false, "error": {"code", "message",
  "hint"}}. Errors are results the model can react to, never exceptions that end the turn.
- `private` holds values the model must never see (a payment link, say); the engine keeps them
  in the trace so a resumed turn has them too.
"""

import uuid
from dataclasses import dataclass, field
from datetime import date, datetime
from typing import Any, ClassVar

import structlog
from pydantic import BaseModel, ValidationError

from app.modules.agent import llm, prompt_store
from app.modules.inventory.schemas import StockItem
from app.modules.merchants.schemas import MerchantInfo

log = structlog.get_logger()

ACTIVE_STAGES = frozenset(
    {"browsing", "collecting_details", "awaiting_confirmation", "payment_pending"}
)


@dataclass
class TurnContext:
    """What tools may use during one turn; tools update the parts that change."""

    turn_id: uuid.UUID
    merchant: MerchantInfo
    conversation_id: uuid.UUID
    customer_id: uuid.UUID
    trigger_message_id: uuid.UUID
    trigger_created_at: datetime
    customer_text: str  # the customer's latest message (script and yes/no checks)
    business_date: date
    now: datetime
    stock: list[StockItem]
    stage: str
    language: str
    health_fields_seen: bool = False
    replied: bool = False
    handed_off: bool = False
    reply_rejections: int = 0
    payment_link: str | None = None
    tap: str | None = None  # a quick-reply payload the customer tapped, e.g. CONFIRM:<id>
    playbook_loaded: bool = False
    upcoming: dict[date, list[StockItem]] = field(default_factory=dict)  # pre-order days
    owner_asked: bool = False  # an Ask me question is open for this chat, or asked this turn
    mode: str = "live"  # live | shadow (nothing written or sent) | draft (replies wait)
    would_send: str | None = None  # shadow mode: the reply that would have gone out
    trigger_details: dict[str, Any] = field(default_factory=dict)
    vision_calls: int = 0
    trigger_text: str = ""  # the customer message this turn answers, as received
    customer_handle: str = "the customer"
    prompt_refs: set[str] = field(default_factory=set)

    def stock_on(self, day: date | None) -> list[StockItem]:
        """The stock for a day: today's, or one of the coming days' (empty if none was set)."""
        if day is None or day == self.business_date:
            return self.stock
        return self.upcoming.get(day, [])

    def all_items(self) -> list[StockItem]:
        """Every item on sale today or on a coming day (once each), for looking items up."""
        seen: dict[object, StockItem] = {item.variant_id: item for item in self.stock}
        for day_stock in self.upcoming.values():
            for item in day_stock:
                seen.setdefault(item.variant_id, item)
        return list(seen.values())


@dataclass(frozen=True)
class ToolResult:
    ok: bool
    data: dict[str, Any] = field(default_factory=dict)
    code: str | None = None
    message: str | None = None
    hint: str | None = None
    private: dict[str, Any] = field(default_factory=dict)

    @classmethod
    def fail(cls, code: str, message: str, hint: str | None = None) -> "ToolResult":
        return cls(False, code=code, message=message, hint=hint)

    def for_model(self) -> dict[str, Any]:
        if self.ok:
            return {"ok": True, "data": self.data}
        error = {"code": self.code, "message": self.message}
        if self.hint:
            error["hint"] = self.hint
        return {"ok": False, "error": error}

    def stored(self) -> dict[str, Any]:
        return {**self.for_model(), "private": self.private}

    @classmethod
    def from_stored(cls, stored: dict[str, Any]) -> "ToolResult":
        error = stored.get("error") or {}
        return cls(
            ok=bool(stored.get("ok")),
            data=stored.get("data") or {},
            code=error.get("code"),
            message=error.get("message"),
            hint=error.get("hint"),
            private=stored.get("private") or {},
        )


class Tool:
    name: ClassVar[str]
    Args: ClassVar[type[BaseModel]]
    stages: ClassVar[frozenset[str]] = ACTIVE_STAGES
    writes: ClassVar[bool] = False

    async def run(self, ctx: TurnContext, args: Any) -> ToolResult:
        raise NotImplementedError

    def replay(self, ctx: TurnContext, result: ToolResult) -> None:
        """Re-apply this result's effect on the turn when a resumed turn reuses it."""

    def spec(self, ctx: TurnContext) -> llm.ToolSpec:
        prompt_id = f"tool.{self.name}"
        ctx.prompt_refs.add(prompt_store.ref(prompt_id))
        return llm.ToolSpec(
            name=self.name,
            description=prompt_store.render(prompt_id),
            parameters=_schema(self.Args),
        )


TOOLS: dict[str, Tool] = {}


def register(tool: Tool) -> None:
    TOOLS[tool.name] = tool


def offered(ctx: TurnContext) -> list[llm.ToolSpec]:
    """The tools the model may call in the conversation's current stage."""
    return [tool.spec(ctx) for tool in TOOLS.values() if ctx.stage in tool.stages]


async def execute(ctx: TurnContext, call: llm.ToolCall) -> ToolResult:
    tool = TOOLS.get(call.name)
    if tool is None:
        return ToolResult.fail("unknown_tool", f"There is no tool called {call.name!r}")
    if ctx.stage not in tool.stages:
        allowed = sorted(name for name, t in TOOLS.items() if ctx.stage in t.stages)
        return ToolResult.fail(
            "not_allowed",
            f"{call.name} can't be used while the conversation is {ctx.stage}",
            f"Tools you can use now: {', '.join(allowed)}",
        )
    if call.arguments_error:
        return ToolResult.fail("invalid_arguments", call.arguments_error)
    try:
        args = tool.Args.model_validate(call.arguments)
    except ValidationError as exc:
        problems = "; ".join(
            f"{'.'.join(str(p) for p in error['loc']) or 'arguments'}: {error['msg']}"
            for error in exc.errors()
        )
        return ToolResult.fail("invalid_arguments", problems)
    if ctx.mode == "shadow" and tool.writes and tool.name != "send_reply":
        return ToolResult(True, {"shadow": True}, hint="Shadow mode: nothing was written")
    try:
        return await tool.run(ctx, args)
    except Exception:
        log.exception("agent.tool_failed", tool=call.name, turn_id=str(ctx.turn_id))
        return ToolResult.fail(
            "internal_error",
            "That didn't work because of a problem on the shop's side",
            "Don't retry it now: ask the shop owner, or tell the customer you'll get back to them",
        )


def replay(ctx: TurnContext, name: str, result: ToolResult) -> None:
    tool = TOOLS.get(name)
    if tool is not None:
        tool.replay(ctx, result)


def _schema(model: type[BaseModel]) -> dict[str, Any]:
    schema = model.model_json_schema()
    schema.pop("title", None)
    for prop in schema.get("properties", {}).values():
        prop.pop("title", None)
    return schema
