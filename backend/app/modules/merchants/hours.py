"""Opening hours: the shop's weekly schedule and closures, and what they mean right now.

Times are in the merchant's time zone. A day missing from the week is a closed day. A range
that closes at or before it opens runs past midnight (e.g. 18:00-02:00).
"""

import re
from datetime import date, datetime, time, timedelta
from typing import Literal
from zoneinfo import ZoneInfo

from pydantic import BaseModel, Field, model_validator

Day = Literal["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
DAYS: tuple[Day, ...] = ("mon", "tue", "wed", "thu", "fri", "sat", "sun")
_DAY_NAMES = ("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")


class TimeRange(BaseModel):
    opens: time
    closes: time

    @model_validator(mode="after")
    def _not_empty(self) -> "TimeRange":
        if self.opens == self.closes:
            raise ValueError("Opening and closing times can't be the same")
        return self


class OpeningHours(BaseModel):
    week: dict[Day, list[TimeRange]] = Field(default_factory=dict)
    # One-off closures (holidays, leave): no ranges start on these dates.
    closed_dates: list[date] = Field(default_factory=list, max_length=366)


def is_open(hours: OpeningHours, at: datetime) -> bool:
    return _open_range(hours, at) is not None


def describe_now(hours: OpeningHours | None, timezone: str, now: datetime) -> str:
    """The "Now" line for the agent: local date and time, and whether the shop is open."""
    local = now.astimezone(ZoneInfo(timezone))
    line = f"Now: {_day_and_date(local)}, {_clock(local.time())} ({timezone})."
    if hours is None:
        return (
            f"{line} The shop hasn't set its opening hours, so you can't tell whether it's open: "
            "if a customer asks when it's open or when they can come, check with the shop."
        )
    current = _open_range(hours, local)
    if current is not None:
        closes = current[1]
        when = "today" if closes.date() == local.date() else _relative_day(closes, local)
        return f"{line} The shop is open now and closes at {_clock(closes.time())} {when}."
    upcoming = _next_opening(hours, local)
    if upcoming is None:
        return f"{line} The shop is closed now and has no opening hours in the next week."
    return (
        f"{line} The shop is closed now. It next opens {_relative_day(upcoming, local)} at "
        f"{_clock(upcoming.time())}."
    )


def describe_week(hours: OpeningHours | None, today: date) -> str:
    """The weekly hours and upcoming closures, one line per day, for the agent's prompt."""
    if hours is None:
        return "Not set."
    lines = []
    for index, day in enumerate(DAYS):
        ranges = hours.week.get(day) or []
        spans = ", ".join(f"{_clock(r.opens)} to {_clock(r.closes)}" for r in ranges)
        lines.append(f"- {_DAY_NAMES[index]}: {spans or 'closed'}")
    soon = sorted(d for d in hours.closed_dates if today <= d <= today + timedelta(days=60))
    if soon:
        lines.append("- Also closed on: " + ", ".join(_day_and_date(d) for d in soon))
    return "\n".join(lines)


_SPEC_PART = re.compile(r"^(?P<days>[a-z]{3}(?:-[a-z]{3})?)=(?P<times>.+)$")
_SPEC_RANGE = re.compile(r"^(\d{1,2}:\d{2})-(\d{1,2}:\d{2})$")


def parse_spec(spec: str, closed_dates: list[date] | None = None) -> OpeningHours:
    """Hours from a short text form, e.g. "mon=closed tue-sat=09:00-20:00 sun=10:00-14:00".

    Several ranges for a day are joined with "+": "fri=09:00-13:00+16:00-21:00".
    """
    week: dict[Day, list[TimeRange]] = {}
    for part in spec.lower().replace(",", " ").split():
        match = _SPEC_PART.match(part)
        if match is None:
            raise ValueError(f"Can't read {part!r}: use day=HH:MM-HH:MM or day=closed")
        days = _day_span(match["days"])
        ranges: list[TimeRange] = []
        if match["times"] != "closed":
            for span in match["times"].split("+"):
                times = _SPEC_RANGE.match(span)
                if times is None:
                    raise ValueError(f"Can't read the times {span!r}: use HH:MM-HH:MM")
                opens, closes = (time.fromisoformat(value.zfill(5)) for value in times.groups())
                ranges.append(TimeRange(opens=opens, closes=closes))
        for day in days:
            week[day] = ranges
    return OpeningHours(
        week={day: ranges for day, ranges in week.items() if ranges},
        closed_dates=closed_dates or [],
    )


def _day_span(text: str) -> list[Day]:
    first, _, last = text.partition("-")
    indexes = []
    for name in (first, last or first):
        if name not in DAYS:
            raise ValueError(f"Unknown day {name!r}: use mon, tue, wed, thu, fri, sat or sun")
        indexes.append(DAYS.index(name))
    start, end = indexes
    return [DAYS[(start + offset) % 7] for offset in range((end - start) % 7 + 1)]


def _ranges(hours: OpeningHours, around: datetime) -> list[tuple[datetime, datetime]]:
    """Open periods starting from the day before `around` to a week after, merged."""
    zone = around.tzinfo
    periods: list[tuple[datetime, datetime]] = []
    for offset in range(-1, 8):
        day = around.date() + timedelta(days=offset)
        if day in hours.closed_dates:
            continue
        for span in hours.week.get(DAYS[day.weekday()]) or []:
            opens = datetime.combine(day, span.opens, tzinfo=zone)
            close_day = day if span.closes > span.opens else day + timedelta(days=1)
            periods.append((opens, datetime.combine(close_day, span.closes, tzinfo=zone)))
    merged: list[tuple[datetime, datetime]] = []
    for opens, closes in sorted(periods):
        if merged and opens <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(merged[-1][1], closes))
        else:
            merged.append((opens, closes))
    return merged


def _open_range(hours: OpeningHours, at: datetime) -> tuple[datetime, datetime] | None:
    return next((r for r in _ranges(hours, at) if r[0] <= at < r[1]), None)


def _next_opening(hours: OpeningHours, at: datetime) -> datetime | None:
    return next((opens for opens, _ in _ranges(hours, at) if opens > at), None)


def _relative_day(moment: datetime, now: datetime) -> str:
    days = (moment.date() - now.date()).days
    if days == 0:
        return "today"
    if days == 1:
        return f"tomorrow ({_day_and_date(moment)})"
    return f"on {_day_and_date(moment)}"


def _day_and_date(moment: date) -> str:
    return f"{_DAY_NAMES[moment.weekday()]} {moment.day} {moment:%B %Y}"


def _clock(moment: time) -> str:
    hour = moment.hour % 12 or 12
    suffix = "am" if moment.hour < 12 else "pm"
    if moment == time(0, 0):
        return "midnight"
    if moment == time(12, 0):
        return "noon"
    return f"{hour}:{moment.minute:02d} {suffix}"
