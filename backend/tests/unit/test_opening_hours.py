from datetime import date, datetime
from zoneinfo import ZoneInfo

import pytest

from app.modules.merchants import hours

KOLKATA = ZoneInfo("Asia/Kolkata")
# Closed Mondays, 9 am to 8 pm the rest of the week, a lunch break on Fridays.
SHOP = hours.parse_spec(
    "mon=closed tue-thu=09:00-20:00 fri=09:00-13:00+16:00-21:00 sat-sun=09:00-20:00"
)


def at(day: int, hour: int, minute: int = 0) -> datetime:
    """A moment in the week of Mon 26 Oct 2026, Kolkata time."""
    return datetime(2026, 10, day, hour, minute, tzinfo=KOLKATA)


def now_line(moment: datetime, opening: hours.OpeningHours | None = SHOP) -> str:
    return hours.describe_now(opening, "Asia/Kolkata", moment)


def test_open_during_hours_with_closing_time() -> None:
    assert now_line(at(27, 19, 40)) == (
        "Now: Tuesday 27 October 2026, 7:40 pm (Asia/Kolkata). "
        "The shop is open now and closes at 8:00 pm today."
    )


def test_closed_before_opening_says_when_it_opens() -> None:
    assert now_line(at(27, 7, 5)).endswith(
        "The shop is closed now. It next opens today at 9:00 am."
    )


def test_closed_after_hours_opens_tomorrow() -> None:
    assert now_line(at(27, 20, 0)).endswith(
        "The shop is closed now. It next opens tomorrow (Wednesday 28 October 2026) at 9:00 am."
    )


def test_closed_day_skips_to_the_next_open_day() -> None:
    assert now_line(at(26, 12, 0)).endswith(
        "The shop is closed now. It next opens tomorrow (Tuesday 27 October 2026) at 9:00 am."
    )


def test_lunch_break_and_second_range() -> None:
    assert now_line(at(30, 14, 0)).endswith("It next opens today at 4:00 pm.")
    assert now_line(at(30, 17, 0)).endswith("closes at 9:00 pm today.")


def test_one_off_closure() -> None:
    holiday = hours.parse_spec("mon-sun=09:00-20:00", [date(2026, 10, 27)])

    assert not hours.is_open(holiday, at(27, 12, 0))
    assert now_line(at(27, 12, 0), holiday).endswith(
        "It next opens tomorrow (Wednesday 28 October 2026) at 9:00 am."
    )


def test_hours_past_midnight() -> None:
    late = hours.parse_spec("fri-sat=18:00-02:00")

    assert hours.is_open(late, at(31, 1, 30))  # Saturday 1:30 am, Friday night's hours
    assert now_line(at(30, 23, 0), late).endswith(
        "closes at 2:00 am tomorrow (Saturday 31 October 2026)."
    )
    assert not hours.is_open(late, at(31, 2, 0))


def test_utc_moment_is_shown_in_the_shops_time_zone() -> None:
    moment = datetime(2026, 10, 27, 14, 10, tzinfo=ZoneInfo("UTC"))  # 7:40 pm in Kolkata

    assert now_line(moment).startswith("Now: Tuesday 27 October 2026, 7:40 pm (Asia/Kolkata).")


def test_without_hours_the_agent_is_told_to_check() -> None:
    line = now_line(at(27, 19, 40), None)

    assert "hasn't set its opening hours" in line and "check with the shop" in line


def test_week_lists_every_day_and_upcoming_closures() -> None:
    holiday = hours.parse_spec("tue-sun=09:00-20:00", [date(2026, 11, 1), date(2027, 6, 1)])

    assert hours.describe_week(holiday, date(2026, 10, 27)).splitlines() == [
        "- Monday: closed",
        *(f"- {day}: 9:00 am to 8:00 pm" for day in ("Tuesday", "Wednesday", "Thursday")),
        *(f"- {day}: 9:00 am to 8:00 pm" for day in ("Friday", "Saturday", "Sunday")),
        "- Also closed on: Sunday 1 November 2026",
    ]


def test_spec_wraps_round_the_week() -> None:
    opening = hours.parse_spec("sat-mon=10:00-14:00")

    assert sorted(opening.week) == ["mon", "sat", "sun"]


@pytest.mark.parametrize(
    "spec", ["funday=09:00-20:00", "mon=9-8", "mon=09:00-09:00", "mon=25:00-26:00", "monday"]
)
def test_bad_spec_is_rejected(spec: str) -> None:
    with pytest.raises(ValueError):  # noqa: PT011 (each case fails for its own reason)
        hours.parse_spec(spec)
