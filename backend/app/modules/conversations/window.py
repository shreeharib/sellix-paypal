"""Instagram's messaging window (agent-phase-2.md section 10).

A shop may message a customer only within 24 hours of the customer's last message; each new
customer message restarts it. After that, only a reply written by a person, sent with the
HUMAN_AGENT tag, may go out, up to 7 days after the customer's last message. The tag needs
Meta's approval for the app, so it's behind the `instagram_human_agent_enabled` setting.
"""

from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Literal

STANDARD_WINDOW = timedelta(hours=24)
HUMAN_AGENT_WINDOW = timedelta(days=7)
CLOSING_WARNING = timedelta(hours=2)

WindowState = Literal["open", "closing", "human_agent_only", "closed"]
# standard: only inside the 24 hours (agent replies, templates)
# human_agent: a person's words; may use the HUMAN_AGENT tag after 24 hours
# when_open: deliver when the customer next writes
WindowPolicy = Literal["standard", "human_agent", "when_open"]
Decision = Literal["send", "send_tagged", "wait", "expire"]


@dataclass(frozen=True)
class Window:
    state: WindowState
    closes_at: datetime | None  # end of the 24 hours
    human_agent_until: datetime | None  # end of the 7 days


def window_at(last_customer_message_at: datetime | None, now: datetime) -> Window:
    if last_customer_message_at is None:
        return Window("closed", None, None)  # a shop can't message a customer first
    closes_at = last_customer_message_at + STANDARD_WINDOW
    human_agent_until = last_customer_message_at + HUMAN_AGENT_WINDOW
    if now >= human_agent_until:
        state: WindowState = "closed"
    elif now >= closes_at:
        state = "human_agent_only"
    elif now >= closes_at - CLOSING_WARNING:
        state = "closing"
    else:
        state = "open"
    return Window(state, closes_at, human_agent_until)


def decide(current: Window, policy: WindowPolicy, *, human_agent_enabled: bool) -> Decision:
    """What the outbox may do with a message right now."""
    if current.state in ("open", "closing"):
        return "send"
    if current.state == "closed":
        return "expire"
    if policy == "human_agent" and human_agent_enabled:
        return "send_tagged"
    return "wait"  # until the customer writes again
