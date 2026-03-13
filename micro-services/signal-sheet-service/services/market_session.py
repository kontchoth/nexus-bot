"""Market session utilities for the US equities/options trading day."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo

MARKET_TZ = ZoneInfo("America/New_York")
UTC = timezone.utc


@dataclass(frozen=True)
class SessionContext:
    now_et: datetime
    now_utc: datetime
    market_day: date
    market_date: str
    is_trading_day: bool


def get_session_context(now: datetime | None = None) -> SessionContext:
    now_utc = _to_utc(now)
    now_et = now_utc.astimezone(MARKET_TZ)
    market_day = now_et.date()
    return SessionContext(
        now_et=now_et,
        now_utc=now_utc,
        market_day=market_day,
        market_date=market_day.isoformat(),
        is_trading_day=is_trading_day(market_day),
    )


def utcnow_iso() -> str:
    return datetime.now(UTC).isoformat()


def market_datetime(market_day: date, hour: int, minute: int = 0) -> datetime:
    return datetime.combine(market_day, time(hour, minute), tzinfo=MARKET_TZ)


def is_after(context: SessionContext, hour: int, minute: int = 0) -> bool:
    return context.now_et >= market_datetime(context.market_day, hour, minute)


def is_trading_day(day: date) -> bool:
    if day.weekday() >= 5:
        return False
    return day not in us_market_holidays(day.year)


def us_market_holidays(year: int) -> set[date]:
    new_year = _observed_holiday(date(year, 1, 1))
    mlk = _nth_weekday_of_month(year, 1, 0, 3)
    presidents = _nth_weekday_of_month(year, 2, 0, 3)
    good_friday = _easter_sunday(year) - timedelta(days=2)
    memorial = _last_weekday_of_month(year, 5, 0)
    juneteenth = _observed_holiday(date(year, 6, 19))
    independence = _observed_holiday(date(year, 7, 4))
    labor = _nth_weekday_of_month(year, 9, 0, 1)
    thanksgiving = _nth_weekday_of_month(year, 11, 3, 4)
    christmas = _observed_holiday(date(year, 12, 25))
    return {
        new_year,
        mlk,
        presidents,
        good_friday,
        memorial,
        juneteenth,
        independence,
        labor,
        thanksgiving,
        christmas,
    }


def _to_utc(now: datetime | None) -> datetime:
    if now is None:
        return datetime.now(UTC)
    if now.tzinfo is None:
        return now.replace(tzinfo=UTC)
    return now.astimezone(UTC)


def _observed_holiday(day: date) -> date:
    if day.weekday() == 5:
        return day - timedelta(days=1)
    if day.weekday() == 6:
        return day + timedelta(days=1)
    return day


def _nth_weekday_of_month(year: int, month: int, weekday: int, nth: int) -> date:
    day = date(year, month, 1)
    while day.weekday() != weekday:
        day += timedelta(days=1)
    return day + timedelta(days=(nth - 1) * 7)


def _last_weekday_of_month(year: int, month: int, weekday: int) -> date:
    if month == 12:
        day = date(year + 1, 1, 1) - timedelta(days=1)
    else:
        day = date(year, month + 1, 1) - timedelta(days=1)
    while day.weekday() != weekday:
        day -= timedelta(days=1)
    return day


def _easter_sunday(year: int) -> date:
    a = year % 19
    b = year // 100
    c = year % 100
    d = b // 4
    e = b % 4
    f = (b + 8) // 25
    g = (b - f + 1) // 3
    h = (19 * a + b - d - g + 15) % 30
    i = c // 4
    k = c % 4
    l = (32 + 2 * e + 2 * i - h - k) % 7
    m = (a + 11 * h + 22 * l) // 451
    month = (h + l - 7 * m + 114) // 31
    day = ((h + l - 7 * m + 114) % 31) + 1
    return date(year, month, day)
