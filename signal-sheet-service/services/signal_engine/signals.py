"""
Nexus Bot — 7-Signal Engine
Computes all six model signals + the premarket SPY component.

Signal roster (matches the UI sheet):
  P  SPY Component  — Premarket directional bias
  1  iToD           — Intraday Time-of-Day pattern
  2  Optimized ToD  — ToD adjusted for current day conditions
  3  ToD / Gap      — ToD cross-referenced with gap status
  4  DPL            — Dynamic Price Level (VWAP-based, color + separation)
  5  AD 6.5         — Advance/Decline Dominance Engine
  6  DOM / Gap      — Order-flow dominance fused with gap context
"""
import math
import logging
from datetime import datetime, time, timedelta
from typing import List, Optional, Tuple
from .models import (
    Candle, Quote, GapInfo,
    SignalDirection, SignalStrength, DPLColor,
    DPLResult, ADResult,
)

logger = logging.getLogger(__name__)


# ═══════════════════════════════════════════════════════════════════════════════
# P — SPY Premarket Component
# ═══════════════════════════════════════════════════════════════════════════════

def compute_spy_component(spy_quote: Quote) -> SignalStrength:
    """
    Grades the premarket (or intraday) SPY stance against previous close.

    Thresholds (configurable via env if needed):
      > +0.50%  → Extremely Bullish
      > +0.20%  → Bullish
      > -0.20%  → Neutral
      > -0.50%  → Bearish
      else      → Extremely Bearish
    """
    if spy_quote.prev_close == 0:
        return SignalStrength.NEUTRAL

    change_pct = (spy_quote.last - spy_quote.prev_close) / spy_quote.prev_close * 100

    if change_pct > 0.50:
        return SignalStrength.EXTREMELY_BULLISH
    elif change_pct > 0.20:
        return SignalStrength.BULLISH
    elif change_pct > -0.20:
        return SignalStrength.NEUTRAL
    elif change_pct > -0.50:
        return SignalStrength.BEARISH
    else:
        return SignalStrength.EXTREMELY_BEARISH


# ═══════════════════════════════════════════════════════════════════════════════
# Gap Detection  (used by multiple signals)
# ═══════════════════════════════════════════════════════════════════════════════

def detect_gap(open_price: float, prev_close: float, threshold_pct: float = 0.30) -> GapInfo:
    """
    A 'significant' gap is any open > threshold_pct away from prior close.
    Default 0.30% matches typical SPY gap-significance level.
    """
    if prev_close == 0:
        return GapInfo(is_significant=False, direction="flat", gap_pct=0.0, gap_points=0.0)

    gap_pct    = (open_price - prev_close) / prev_close * 100
    gap_points = open_price - prev_close

    return GapInfo(
        is_significant = abs(gap_pct) >= threshold_pct,
        direction      = "up" if gap_pct > 0.05 else ("down" if gap_pct < -0.05 else "flat"),
        gap_pct        = round(gap_pct, 3),
        gap_points     = round(gap_points, 2),
    )


# ═══════════════════════════════════════════════════════════════════════════════
# Min-14 Reference  (used by algorithm & trade sizing)
# ═══════════════════════════════════════════════════════════════════════════════

def compute_min14_reference(
    candles_1min: List[Candle],
    market_open: time = time(9, 30),
) -> Tuple[Optional[float], Optional[float]]:
    """
    Lock the high and low of the first 14 minutes after market open.
    Returns (min14_high, min14_low).
    """
    cutoff = datetime.combine(datetime.today(), market_open) + timedelta(minutes=14)
    first14 = [c for c in candles_1min if c.timestamp.time() <= cutoff.time()]

    if not first14:
        return None, None

    return (
        max(c.high for c in first14),
        min(c.low  for c in first14),
    )


# ═══════════════════════════════════════════════════════════════════════════════
# Signal 1 — iToD  (Intraday Time-of-Day)
# ═══════════════════════════════════════════════════════════════════════════════
#
# Segments the trading day into behavioural windows based on historical SPY
# intraday seasonality. This is the "raw" ToD signal before optimization.
#
# Sessions (Eastern time, minutes since 09:30):
#  0–14   Morning Momentum   — follow premarket bias
#  15–30  Opening Reversion  — watch for fade / continuation decision
#  31–60  Mid-Morning        — typically directional push
#  61–120 Late Morning       — consolidation, reduced edge
#  121–210 Lunch Drift       — low-conviction; often flat to slight drift
#  211–270 Afternoon Setup   — institutional accumulation window
#  271–360 Power Hour        — directional with strong momentum
#  360–390 Close             — MOC flows dominate

_ITOD_SESSIONS = [
    (0,   14,  "Morning Momentum"),
    (15,  30,  "Opening Reversion"),
    (31,  60,  "Mid-Morning Push"),
    (61,  120, "Late Morning Consolidation"),
    (121, 210, "Lunch Drift"),
    (211, 270, "Afternoon Setup"),
    (271, 360, "Power Hour"),
    (361, 390, "Market Close"),
]

# Directional bias of each session relative to day's opening direction.
# +1 = follow opening direction, -1 = fade opening direction, 0 = neutral.
_ITOD_BIAS = {
    "Morning Momentum":         +1,
    "Opening Reversion":        -1,
    "Mid-Morning Push":         +1,
    "Late Morning Consolidation": 0,
    "Lunch Drift":               0,
    "Afternoon Setup":          +1,
    "Power Hour":               +1,
    "Market Close":              0,
}


def compute_itod(
    now: datetime,
    premarket_signal: SignalStrength,
    market_open: time = time(9, 30),
) -> SignalDirection:
    """
    Returns iToD signal direction based on current session and premarket bias.
    """
    open_dt        = datetime.combine(now.date(), market_open)
    mins_since_open = (now - open_dt).total_seconds() / 60

    session_name = "Market Close"  # default
    for start, end, name in _ITOD_SESSIONS:
        if start <= mins_since_open <= end:
            session_name = name
            break

    bias       = _ITOD_BIAS[session_name]
    is_bullish = premarket_signal in (
        SignalStrength.EXTREMELY_BULLISH, SignalStrength.BULLISH
    )

    if bias == 0:
        return SignalDirection.NEUTRAL
    if bias == +1:
        return SignalDirection.LONG if is_bullish else SignalDirection.SHORT
    # bias == -1 → fade
    return SignalDirection.SHORT if is_bullish else SignalDirection.LONG


# ═══════════════════════════════════════════════════════════════════════════════
# Signal 2 — Optimized ToD
# ═══════════════════════════════════════════════════════════════════════════════
#
# Enhances iToD by overlaying:
#   - Intraday momentum (recent candle trend)
#   - Gap regime adjustment (gap-day patterns differ)
#   - Volume profile (above/below average volume for session)
#
# Typically overrides iToD when current conditions contradict the seasonal bias.

def compute_optimized_tod(
    itod:           SignalDirection,
    candles_5min:   List[Candle],
    gap:            GapInfo,
    avg_volume:     Optional[float] = None,
) -> SignalDirection:
    """
    Optimized ToD = iToD adjusted for live momentum + gap day patterns.
    """
    if not candles_5min or len(candles_5min) < 3:
        return itod

    # ── Short-term momentum: slope of last 3 closes ──────────────────────────
    recent = candles_5min[-3:]
    momentum = recent[-1].close - recent[0].close

    # ── Volume confirmation ───────────────────────────────────────────────────
    current_vol = sum(c.volume for c in recent)
    if avg_volume and avg_volume > 0:
        vol_ratio = current_vol / (avg_volume * len(recent) / 78)  # 78 × 5-min bars/day
    else:
        vol_ratio = 1.0  # no data, neutral

    # ── Gap day override ──────────────────────────────────────────────────────
    # On gap-up days the Opening Reversion bias is amplified (gap fills)
    # On gap-down days same but inverted
    if gap.is_significant and gap.direction == "up" and momentum < 0:
        return SignalDirection.SHORT   # early gap fill short
    if gap.is_significant and gap.direction == "down" and momentum > 0:
        return SignalDirection.LONG    # early gap fill long

    # ── Momentum contradiction filter ─────────────────────────────────────────
    # If price action strongly contradicts itod, defer to price action
    if itod == SignalDirection.LONG and momentum < 0 and vol_ratio > 1.3:
        return SignalDirection.WAIT
    if itod == SignalDirection.SHORT and momentum > 0 and vol_ratio > 1.3:
        return SignalDirection.WAIT

    return itod


# ═══════════════════════════════════════════════════════════════════════════════
# Signal 3 — ToD / Gap
# ═══════════════════════════════════════════════════════════════════════════════
#
# Fuses the Optimized ToD signal with gap fill probability.
# A large gap creates a competing force — the gap fill pull — that can
# override the standard ToD direction in the first 60 minutes.

_GAP_FILL_WINDOW_MINS = 60  # first 60 min is the primary gap-fill window


def compute_tod_gap(
    optimized_tod:  SignalDirection,
    gap:            GapInfo,
    now:            datetime,
    market_open:    time = time(9, 30),
) -> SignalDirection:
    open_dt        = datetime.combine(now.date(), market_open)
    mins_since_open = (now - open_dt).total_seconds() / 60

    # Outside gap-fill window → ToD rules
    if not gap.is_significant or mins_since_open > _GAP_FILL_WINDOW_MINS:
        return optimized_tod

    # Inside gap-fill window: gap fill direction competes with ToD
    gap_fill_dir = SignalDirection.SHORT if gap.direction == "up" else SignalDirection.LONG

    if optimized_tod == gap_fill_dir:
        return optimized_tod  # both agree → high confidence
    else:
        # Conflict → wait for resolution (DPL will break the tie)
        return SignalDirection.WAIT


# ═══════════════════════════════════════════════════════════════════════════════
# Signal 4 — DPL  (Dynamic Price Level)
# ═══════════════════════════════════════════════════════════════════════════════
#
# DPL is the VWAP-anchored directional bias + separation color.
# • Above VWAP → Green (bullish)
# • Below VWAP → Red (bearish)
# • Wide separation = strong conviction; tight separation = potential flip
# • A fresh cross (breakup / breakdown) is flagged for the algorithm.

_DPL_STRONG_THRESHOLD_PCT = 0.15   # > 0.15% from VWAP = "strong" color
_DPL_WEAK_THRESHOLD_PCT   = 0.05   # < 0.05% = near-zero, treat as grey


def compute_dpl(
    candles_5min:   List[Candle],
    current_price:  float,
) -> DPLResult:
    """
    VWAP = sum(typical_price × volume) / sum(volume).
    DPL tracks price vs VWAP and detects fresh crosses.
    """
    if not candles_5min:
        return DPLResult(
            color=DPLColor.GREY, separation=0.0, separation_pct=0.0,
            vwap=current_price, is_above=True, breakup=False, breakdown=False,
        )

    # ── VWAP ─────────────────────────────────────────────────────────────────
    tp_vol_sum = 0.0
    vol_sum    = 0.0
    for c in candles_5min:
        typical = (c.high + c.low + c.close) / 3
        tp_vol_sum += typical * c.volume
        vol_sum    += c.volume

    vwap = tp_vol_sum / vol_sum if vol_sum > 0 else current_price

    separation     = current_price - vwap
    separation_pct = separation / vwap * 100 if vwap > 0 else 0.0
    is_above       = current_price > vwap

    # ── Color ─────────────────────────────────────────────────────────────────
    if abs(separation_pct) < _DPL_WEAK_THRESHOLD_PCT:
        color = DPLColor.GREY
    elif is_above:
        color = DPLColor.GREEN
    else:
        color = DPLColor.RED

    # ── Cross detection (compare last two candle closes vs VWAP) ─────────────
    breakup = breakdown = False
    if len(candles_5min) >= 2:
        prev_above = candles_5min[-2].close > vwap
        curr_above = is_above
        if not prev_above and curr_above:
            breakup = True
        elif prev_above and not curr_above:
            breakdown = True

    return DPLResult(
        color          = color,
        separation     = round(separation, 3),
        separation_pct = round(separation_pct, 3),
        vwap           = round(vwap, 2),
        is_above       = is_above,
        breakup        = breakup,
        breakdown      = breakdown,
    )


# ═══════════════════════════════════════════════════════════════════════════════
# Signal 5 — AD 6.5  (Advance / Decline Dominance Engine)
# ═══════════════════════════════════════════════════════════════════════════════
#
# AD 6.5 uses the advance/decline ratio with 6.5 as the extreme threshold.
# Named "Engine v6.5" to reflect the threshold and version of calibration.
#
# Ratio:
#  > 6.5  → Extremely Bullish
#  2–6.5  → Bullish
#  0.5–2  → Neutral
#  ~0.15–0.5 → Bearish
#  < 0.15 → Extremely Bearish (inverse of 6.5)

_AD_EXTREME_THRESHOLD = 6.5
_AD_BULLISH_THRESHOLD = 2.0
_AD_BEARISH_THRESHOLD = 0.5


def compute_ad_65(advances: int, declines: int) -> ADResult:
    if declines == 0:
        ratio = _AD_EXTREME_THRESHOLD + 1  # treat all-advances as extreme
    elif advances == 0:
        ratio = 0.0
    else:
        ratio = advances / declines

    if ratio >= _AD_EXTREME_THRESHOLD:
        signal    = SignalStrength.EXTREMELY_BULLISH
        direction = SignalDirection.LONG
    elif ratio >= _AD_BULLISH_THRESHOLD:
        signal    = SignalStrength.BULLISH
        direction = SignalDirection.LONG
    elif ratio >= _AD_BEARISH_THRESHOLD:
        signal    = SignalStrength.NEUTRAL
        direction = SignalDirection.NEUTRAL
    elif ratio >= 1 / _AD_EXTREME_THRESHOLD:
        signal    = SignalStrength.BEARISH
        direction = SignalDirection.SHORT
    else:
        signal    = SignalStrength.EXTREMELY_BEARISH
        direction = SignalDirection.SHORT

    return ADResult(
        signal    = signal,
        direction = direction,
        ratio     = round(ratio, 2),
        advances  = advances,
        declines  = declines,
    )


# ═══════════════════════════════════════════════════════════════════════════════
# Signal 6 — DOM / Gap  (Dominance + Gap)
# ═══════════════════════════════════════════════════════════════════════════════
#
# DOM = buy-side vs sell-side dominance, approximated from:
#  - recent candle body direction (close > open = bullish body)
#  - volume-weighted body ratio
#
# Fused with gap: a gap in the same direction as DOM = high confidence.
# A gap opposing DOM = conflict → WAIT.

def compute_dom_gap(
    candles_5min: List[Candle],
    gap:          GapInfo,
    lookback:     int = 5,
) -> SignalDirection:
    """
    DOM signal from recent candle bodies, then fused with gap.
    """
    if not candles_5min:
        return SignalDirection.NEUTRAL

    recent = candles_5min[-lookback:] if len(candles_5min) >= lookback else candles_5min

    # ── Body dominance score ──────────────────────────────────────────────────
    bull_vol = sum(c.volume for c in recent if c.close >= c.open)
    bear_vol = sum(c.volume for c in recent if c.close <  c.open)
    total_vol = bull_vol + bear_vol

    if total_vol == 0:
        dom_direction = SignalDirection.NEUTRAL
    elif bull_vol / total_vol > 0.60:
        dom_direction = SignalDirection.LONG
    elif bear_vol / total_vol > 0.60:
        dom_direction = SignalDirection.SHORT
    else:
        dom_direction = SignalDirection.NEUTRAL

    # ── Fuse with gap ─────────────────────────────────────────────────────────
    if not gap.is_significant:
        return dom_direction

    gap_dir = SignalDirection.LONG if gap.direction == "down" else SignalDirection.SHORT
    # Opposite gap direction is gap-fill direction
    gap_fill = SignalDirection.SHORT if gap.direction == "up" else SignalDirection.LONG

    if dom_direction == gap_fill:
        return dom_direction   # DOM confirming gap fill → confident
    elif dom_direction == SignalDirection.NEUTRAL:
        return SignalDirection.WAIT
    else:
        return SignalDirection.WAIT  # DOM vs gap fill = conflict
