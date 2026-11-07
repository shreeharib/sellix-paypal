import uuid
from datetime import UTC, datetime, timedelta

from app.modules.agent.engine import causal_order
from app.modules.conversations.schemas import ChatLine

START = datetime(2026, 11, 7, 15, 0, tzinfo=UTC)


def line(n: int, sender: str, body: str, **details: object) -> ChatLine:
    return ChatLine(uuid.uuid4(), sender, body, START + timedelta(seconds=n), dict(details))


def test_a_reply_moves_up_to_the_message_it_answered() -> None:
    event = line(0, "system", "the owner answered")
    okay = line(7, "customer", "okay")
    reply = line(11, "agent", "Yes, available", trigger_id=str(event.id))

    ordered = causal_order([event, okay, reply])

    assert [x.body for x in ordered] == ["the owner answered", "Yes, available", "okay"]


def test_normal_conversations_and_old_messages_are_untouched() -> None:
    hi = line(0, "customer", "hi")
    hello = line(3, "agent", "Hi! How can I help?", trigger_id=str(hi.id))
    ask = line(9, "customer", "what do you have?")
    old_reply = line(12, "agent", "A reply from before trigger ids existed")

    history = [hi, hello, ask, old_reply]

    assert causal_order(history) == history


def test_several_replies_to_one_message_keep_their_order() -> None:
    ask = line(0, "customer", "2 cookies")
    more = line(4, "customer", "and a brownie")
    first = line(6, "agent", "Pickup or delivery?", trigger_id=str(ask.id))
    second = line(7, "agent", "Which size?", trigger_id=str(ask.id))

    ordered = causal_order([ask, more, first, second])

    assert [x.body for x in ordered] == [
        "2 cookies",
        "Pickup or delivery?",
        "Which size?",
        "and a brownie",
    ]
