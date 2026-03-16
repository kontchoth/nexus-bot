"""
NexusBot — Market Session Utility
Centralised Eastern-timezone market calendar logic.
All handlers must use this module. Do not scatter datetime/timezone logic.

Provides:
  - market_date()         → current ET market date string (YYYY-MM-DD)
  - is_trading_day()      → False on weekends and US market holidays
  - current_phase()       → which phase window is active right now
  - phase_window_active() → guard for endpoint handlers
  - session_bars_ready()  → enough 1-min bars for a requested bar count
"""
from __future__ import annotations

import logging
from datetime import date, datetime, time, timedelta
from enum import Enum
import os
from typing import Optional
from zoneinfo import ZoneInfo

logger = logging.getLogger(__name__)

ET = ZoneInfo("America/New_York")

# ─── US market holidays (add each year) ──────────────────────────────────────
# Source: NYSE holiday schedule
_HOLIDAYS: set[date] = {
    # 2025
    date(2025, 1, 1),   # New Year's Day
    date(2025, 1, 20),  # MLK Day
    date(2025, 2, 17),  # Presidents Day
    date(2025, 4, 18),  # Good Friday
    date(2025, 5, 26),  # Memorial Day
    date(2025, 6, 19),  # Juneteenth
    date(2025, 7, 4),   # Independence Day
    date(2025, 9, 1),   # Labor Day
    date(2025, 11, 27), # Thanksgiving
    date(2025, 12, 25), # Christmas
    # 2026
    date(2026, 1, 1),   # New Year's Day
    date(2026, 1, 19),  # MLK Day
    date(2026, 2, 16),  # Presidents Day
    date(2026, 4, 3),   # Good Friday
    date(2026, 5, 25),  # Memorial Day
    date(2026, 6, 19),  # Juneteenth
    date(2026, 7, 3),   # Independence Day (observed)
    date(2026, 9, 7),   # Labor Day
    date(2026, 11, 26), # Thanksgiving
    date(2026, 12, 25), # Christmas
}

MARKET_OPEN  = time(9, 30, tzinfo=ET)
MARKET_CLOSE = time(16, 0, tzinfo=ET)


class Phase(str, Enum):
    PREMARKET      = "premarket"
    OPEN           = "open"
    LOCKED         = "locked"
    EARLY_SESSION  = "early_session"
    MID_SESSION    = "mid_session"
    CLOSED         = "closed"


# ─────────────────────────────────────────────────────────────────────────────
# Core helpers
# ─────────────────────────────────────────────────────────────────────────────

def now_et() -> datetime:
    """Current wall-clock time in US Eastern."""
    return datetime.now(tz=ET)


def market_date(dt: Optional[datetime] = None) -> str:
    """
    ET market date string for today (or a given datetime).
    Always derived from Eastern Time — never from UTC or device local time.
    """
    et_now = (dt or now_et()).astimezone(ET)
    return et_now.strftime("%Y-%m-%d")


def market_date_obj(dt: Optional[datetime] = None) -> date:
    et_now = (dt or now_et()).astimezone(ET)
    return et_now.date()


def is_trading_day(d: Optional[date] = None) -> bool:
    """True if the given date (default: today ET) is a US equity trading day."""
    d = d or market_date_obj()
    if d.weekday() >= 5:       # Saturday=5, Sunday=6
        return False
    if d in _HOLIDAYS:
        return False
    return True


def is_market_open(dt: Optional[datetime] = None) -> bool:
    et = (dt or now_et()).astimezone(ET)
    t  = et.time().replace(tzinfo=ET)
    return MARKET_OPEN <= t < MARKET_CLOSE and is_trading_day(et.date())


# ─────────────────────────────────────────────────────────────────────────────
# Phase detection
# ─────────────────────────────────────────────────────────────────────────────

# Each phase: (start_time_ET, end_time_ET_exclusive)
_PHASE_WINDOWS: dict[str, tuple[time, time]] = {
    "generate":     (time(9, 15), time(9, 30)),
    "resolve":      (time(9, 30), time(9, 44)),
    "lock_minute14":(time(9, 44), time(10, 0)),
    "refresh":      (time(9, 35), time(10, 6)),
    "render":       (time(9, 21), time(10, 10)),
}


def current_phase(dt: Optional[datetime] = None) -> Phase:
    et = (dt or now_et()).astimezone(ET)
    t  = et.time()

    if not is_trading_day(et.date()):
        return Phase.CLOSED

    if t < time(9, 30):
        return Phase.PREMARKET
    if time(9, 30) <= t < time(9, 44):
        return Phase.OPEN
    if time(9, 44) <= t < time(10, 6):
        return Phase.LOCKED
    if time(10, 6) <= t < time(16, 0):
        return Phase.EARLY_SESSION if t < time(11, 0) else Phase.MID_SESSION
    return Phase.CLOSED


def phase_window_active(endpoint: str, dt: Optional[datetime] = None) -> bool:
    """
    Returns True if the current time falls within the intended window for an
    endpoint. Handlers should call this and return noop when False.
    """
    if os.environ.get("SKIP_PHASE_WINDOW") == "true":   # ← add this
        return True
    et = (dt or now_et()).astimezone(ET)
    t  = et.time()
    window = _PHASE_WINDOWS.get(endpoint)
    if not window:
        return True   # unknown endpoint, don't gate it
    start, end = window
    return start <= t < end


# ─────────────────────────────────────────────────────────────────────────────
# Bar readiness
# ─────────────────────────────────────────────────────────────────────────────

def session_bars_ready(required_bars: int, dt: Optional[datetime] = None) -> bool:
    """
    True if enough 1-minute bars have closed since 09:30 ET.
    E.g. required_bars=14 → True only after 09:43 bar has closed (at 09:44).
    """
    et     = (dt or now_et()).astimezone(ET)
    open_  = datetime.combine(et.date(), time(9, 30), tzinfo=ET)
    elapsed_minutes = (et - open_).total_seconds() / 60
    return elapsed_minutes >= required_bars


# ─────────────────────────────────────────────────────────────────────────────
# Opening bar timestamp
# ─────────────────────────────────────────────────────────────────────────────

def opening_bar_start(d: Optional[date] = None) -> datetime:
    d = d or market_date_obj()
    return datetime.combine(d, time(9, 30), tzinfo=ET)


def minute14_cutoff(d: Optional[date] = None) -> datetime:
    """The 09:43 bar closes at 09:44 — that's when min14 lock should run."""
    d = d or market_date_obj()
    return datetime.combine(d, time(9, 44), tzinfo=ET)
