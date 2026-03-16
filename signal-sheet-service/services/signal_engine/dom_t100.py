"""
Nexus Bot — DOM 7.5 & T+100 Inflection
Two signals referenced directly on the signal sheet but not yet implemented.

──────────────────────────────────────────────────────────────────────────────
DOM 7.5  (Order-Flow Dominance at 7.5 threshold)
──────────────────────────────────────────────────────────────────────────────
Visible in the Significant Gap Panel: "DOM 7.5" is a dominance ratio threshold
that mirrors AD 6.5 but operates on order-flow (bid/ask volume) rather than
market breadth. A DOM ratio of 7.5:1 on the buy or sell side signals extreme
one-sided pressure — similar to AD 6.5 but on a shorter time window.

Implementation:
  DOM ratio = aggressive_buy_volume / aggressive_sell_volume
              (where aggressive = trades executed at the ask vs at the bid)

  Since Tradier doesn't provide Level 2 DOM data directly, we approximate using:
    1. Close-to-VWAP signed volume from candles (primary)
    2. Ask-vs-bid delta from the most recent quote spread activity

Thresholds:
  > 7.5   → Extreme Buy Domination (matches the "7.5" label)
  2.0–7.5 → Buy Domination
  0.5–2.0 → Balanced
  0.13–0.5 → Sell Domination   (1/7.5 ≈ 0.13)
  < 0.13  → Extreme Sell Domination

──────────────────────────────────────────────────────────────────────────────
T+100 Inflection
──────────────────────────────────────────────────────────────────────────────
Visible in the Discordant Signal Panel: "T+100 inflection — SPY direction?"
T+100 = 100 minutes after market open = 11:10 AM ET.

This is a known SPY behavioral inflection point where:
  1. Morning institutional flows have largely completed
  2. Options dealers have re-hedged from the open
  3. 0DTE gamma is beginning to dominate

At T+100 the signal checks:
  - Is SPY above or below VWAP?
  - Is the 5-min trend (last 4 candles) bullish or bearish?
  - Has the opening gap been filled or rejected?
  - What is 0DTE GEX net (positive = stabilizing, negative = amplifying)?

If T+100 SPY direction matches DPL color → confirmation
If it contradicts → discordant, wait for S35 resolution

Also computes T+200 (1:10 PM) as an afternoon inflection reference.
"""
import logging
from dataclasses import dataclass
from datetime import datetime, time, timedelta
from typing import List, Optional
from .models import Candle, SignalDirection, DPLResult, GapInfo

logger = logging.getLogger(__name__)

T100_MINUTES = 100   # 09:30 + 100min = 11:10 AM
T200_MINUTES = 200   # 09:30 + 200min = 13:10 PM (1:10 PM)

DOM_EXTREME_THRESHOLD = 7.5
DOM_BULLISH_THRESHOLD = 2.0
DOM_BEARISH_THRESHOLD = 0.5


# ─── DOM 7.5 ─────────────────────────────────────────────────────────────────

@dataclass
class DOM75Result:
    ratio:            float
    direction:        SignalDirection
    label:            str         # "Extreme Buy" | "Buy Dom" | "Balanced" | "Sell Dom" | "Extreme Sell"
    is_extreme:       bool        # True if > 7.5 or < 1/7.5
    buy_volume:       float
    sell_volume:      float
    lookback_bars:    int


def compute_dom75(
    candles: List[Candle],
    vwap:    float,
    lookback: int = 5,
) -> DOM75Result:
    """
    Approximate DOM 7.5 from signed candle volume vs VWAP.

    Logic:
      - Candles with close > VWAP = aggressive buying (add to buy vol)
      - Candles with close < VWAP = aggressive selling (add to sell vol)
      - Candle body size as a confidence weight
    """
    if not candles:
        return DOM75Result(
            ratio=1.0, direction=SignalDirection.NEUTRAL,
            label="Balanced", is_extreme=False,
            buy_volume=0.0, sell_volume=0.0, lookback_bars=0,
        )

    recent = candles[-lookback:] if len(candles) >= lookback else candles

    buy_vol  = 0.0
    sell_vol = 0.0

    for c in recent:
        body_strength = abs(c.close - c.open) / max(c.high - c.low, 0.001)
        weighted_vol  = c.volume * max(body_strength, 0.3)  # floor at 30% body

        if c.close > vwap and c.close >= c.open:
            buy_vol  += weighted_vol
        elif c.close < vwap and c.close <= c.open:
            sell_vol += weighted_vol
        else:
            # Mixed: split proportionally by position relative to VWAP
            buy_fraction  = max(0, c.close - vwap) / max(c.high - c.low, 0.001)
            sell_fraction = max(0, vwap - c.close) / max(c.high - c.low, 0.001)
            buy_vol  += weighted_vol * buy_fraction
            sell_vol += weighted_vol * sell_fraction

    if sell_vol == 0:
        ratio = DOM_EXTREME_THRESHOLD + 1
    elif buy_vol == 0:
        ratio = 0.0
    else:
        ratio = buy_vol / sell_vol

    # Classify
    if ratio > DOM_EXTREME_THRESHOLD:
        label     = "Extreme Buy"
        direction = SignalDirection.LONG
        is_extreme = True
    elif ratio > DOM_BULLISH_THRESHOLD:
        label     = "Buy Dom"
        direction = SignalDirection.LONG
        is_extreme = False
    elif ratio > DOM_BEARISH_THRESHOLD:
        label     = "Balanced"
        direction = SignalDirection.NEUTRAL
        is_extreme = False
    elif ratio > 1 / DOM_EXTREME_THRESHOLD:
        label     = "Sell Dom"
        direction = SignalDirection.SHORT
        is_extreme = False
    else:
        label     = "Extreme Sell"
        direction = SignalDirection.SHORT
        is_extreme = True

    return DOM75Result(
        ratio         = round(ratio, 2),
        direction     = direction,
        label         = label,
        is_extreme    = is_extreme,
        buy_volume    = round(buy_vol),
        sell_volume   = round(sell_vol),
        lookback_bars = len(recent),
    )


# ─── T+100 Inflection ────────────────────────────────────────────────────────

@dataclass
class T100Result:
    is_reached:        bool          # True if now >= T+100
    minutes_to_t100:   float         # < 0 if already past
    spy_direction:     SignalDirection
    is_above_vwap:     bool
    trend_5min:        str           # 'up' | 'down' | 'flat'
    gap_filled:        bool          # Has the opening gap been filled by T+100?
    confirms_dpl:      bool          # T+100 direction matches DPL color
    inflection_label:  str           # Human-readable conclusion
    t200_direction:    Optional[SignalDirection]   # If past T+200


def compute_t100_inflection(
    candles_5min: List[Candle],
    now:          datetime,
    vwap:         float,
    dpl:          DPLResult,
    gap:          GapInfo,
    spot:         float,
    market_open:  time = time(9, 30),
) -> T100Result:
    """
    Evaluates market direction at the T+100 inflection point.
    """
    open_dt   = datetime.combine(now.date(), market_open)
    mins_elapsed = (now - open_dt).total_seconds() / 60
    mins_to_t100 = T100_MINUTES - mins_elapsed
    is_reached = mins_elapsed >= T100_MINUTES

    # ── If not reached yet → partial pre-T100 read ───────────────────────────
    if not is_reached:
        return T100Result(
            is_reached=False, minutes_to_t100=round(mins_to_t100, 1),
            spy_direction=SignalDirection.WAIT, is_above_vwap=(spot > vwap),
            trend_5min="flat", gap_filled=False, confirms_dpl=False,
            inflection_label=f"T+100 in {mins_to_t100:.0f} min — watching.",
            t200_direction=None,
        )

    # ── Candles up to T+100 ───────────────────────────────────────────────────
    t100_cutoff = open_dt + timedelta(minutes=T100_MINUTES)
    t100_candles = [c for c in candles_5min if c.timestamp <= t100_cutoff]

    if not t100_candles:
        return _neutral_t100()

    # ── 5-min trend (last 4 candles at T+100) ────────────────────────────────
    trend_candles = t100_candles[-4:] if len(t100_candles) >= 4 else t100_candles
    price_at_t100 = trend_candles[-1].close
    trend_5min    = _classify_trend(trend_candles)

    # ── Above/below VWAP at T+100 ────────────────────────────────────────────
    is_above = price_at_t100 > vwap

    # ── Gap fill check ────────────────────────────────────────────────────────
    gap_filled = _check_gap_filled(t100_candles, gap, spot)

    # ── SPY direction at T+100 ────────────────────────────────────────────────
    if trend_5min == "up" and is_above:
        t100_dir = SignalDirection.LONG
    elif trend_5min == "down" and not is_above:
        t100_dir = SignalDirection.SHORT
    else:
        t100_dir = SignalDirection.NEUTRAL

    # ── DPL confirmation ──────────────────────────────────────────────────────
    from .models import DPLColor
    dpl_long  = dpl.color == DPLColor.GREEN
    dpl_short = dpl.color == DPLColor.RED
    confirms_dpl = (
        (t100_dir == SignalDirection.LONG  and dpl_long) or
        (t100_dir == SignalDirection.SHORT and dpl_short)
    )

    # ── T+200 direction (if already past it) ─────────────────────────────────
    t200_dir = None
    if mins_elapsed >= T200_MINUTES:
        t200_cutoff  = open_dt + timedelta(minutes=T200_MINUTES)
        t200_candles = [c for c in candles_5min if c.timestamp <= t200_cutoff]
        if t200_candles:
            t200_trend   = _classify_trend(t200_candles[-4:])
            t200_above   = t200_candles[-1].close > vwap
            if t200_trend == "up" and t200_above:
                t200_dir = SignalDirection.LONG
            elif t200_trend == "down" and not t200_above:
                t200_dir = SignalDirection.SHORT

    # ── Label ─────────────────────────────────────────────────────────────────
    confirm_str = "✅ Confirms DPL" if confirms_dpl else "⚠️ Contradicts DPL"
    gap_str     = " | Gap filled." if gap_filled else ""
    label = (
        f"T+100: {t100_dir.value.upper()} "
        f"({'above' if is_above else 'below'} VWAP, {trend_5min} trend). "
        f"{confirm_str}.{gap_str}"
    )

    return T100Result(
        is_reached       = True,
        minutes_to_t100  = round(mins_to_t100, 1),
        spy_direction    = t100_dir,
        is_above_vwap    = is_above,
        trend_5min       = trend_5min,
        gap_filled       = gap_filled,
        confirms_dpl     = confirms_dpl,
        inflection_label = label,
        t200_direction   = t200_dir,
    )


# ─── Helpers ─────────────────────────────────────────────────────────────────

def _classify_trend(candles: List[Candle]) -> str:
    if len(candles) < 2:
        return "flat"
    slope = candles[-1].close - candles[0].close
    if slope > 0.20:   return "up"
    if slope < -0.20:  return "down"
    return "flat"


def _check_gap_filled(
    candles:  List[Candle],
    gap:      GapInfo,
    spot:     float,
) -> bool:
    """True if price has crossed back through the prior close (gap fill)."""
    if not gap.is_significant or not candles:
        return False

    gap_fill_price = spot - gap.gap_points  # = prev_close
    if gap.direction == "up":
        # Gap up filled when price drops back to or below prev close
        return any(c.low <= gap_fill_price for c in candles)
    else:
        # Gap down filled when price rises back to or above prev close
        return any(c.high >= gap_fill_price for c in candles)


def _neutral_t100() -> T100Result:
    return T100Result(
        is_reached=True, minutes_to_t100=0,
        spy_direction=SignalDirection.NEUTRAL, is_above_vwap=False,
        trend_5min="flat", gap_filled=False, confirms_dpl=False,
        inflection_label="T+100: Insufficient candle data.",
        t200_direction=None,
    )
