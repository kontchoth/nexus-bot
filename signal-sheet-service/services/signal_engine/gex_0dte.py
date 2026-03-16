"""
Nexus Bot — 0DTE GEX Engine
Specialized gamma-exposure analysis for same-day-expiry SPX/SPXW options.

Why 0DTE needs its own engine:
  - 0DTE options represent ~50% of daily SPX options volume
  - At-the-money gamma is MUCH higher for 0DTE than longer-dated (very short time)
  - As expiration approaches, Charm (dDelta/dTime) accelerates → intraday flows shift
  - Vanna (dDelta/dIV) means a VIX move intraday can instantly flip dealer hedging
  - 0DTE flip points are tighter (within ±10 points of spot) vs all-expiry flip points
  - This is why the signal sheet tracks DPL "breakup/breakdown" — 0DTE gamma walls
    can pin or repel price intraday at specific strikes

Key outputs:
  - 0DTE Net GEX (separate from all-expiry GEX)
  - 0DTE Flip Point (tighter, intraday relevant)
  - 0DTE Gamma Wall (nearest high-gamma strike)
  - Charm pressure estimate (direction of delta decay forcing at current time)
  - Vanna estimate (sensitivity of dealer delta to a 1-point VIX move)
  - "Pinning" probability (price likely to stay near current strike)

Tradier: SPXW options have expirations every Mon/Wed/Fri (+ daily options)
         Use the chain with today's date as expiration.
"""
import math
import logging
from dataclasses import dataclass
from datetime import datetime, date, time
from typing import List, Dict, Optional, Tuple
from .models import OptionContract

logger = logging.getLogger(__name__)

CONTRACT_MULTIPLIER = 100
TRADING_DAYS_PER_YEAR = 252
MINUTES_PER_TRADING_DAY = 390   # 09:30 – 16:00


# ─── Result ──────────────────────────────────────────────────────────────────

@dataclass
class ZeroDTEResult:
    net_gex_millions:     float            # Total 0DTE net GEX in $M
    flip_point:           Optional[float]  # Nearest 0DTE gamma zero-cross
    gamma_wall_above:     Optional[float]  # Nearest call gamma wall above spot
    gamma_wall_below:     Optional[float]  # Nearest put gamma wall below spot
    charm_direction:      str              # 'bullish' | 'bearish' | 'neutral'
    charm_magnitude:      float            # Estimated $ delta change per hour
    vanna_direction:      str              # 'bullish' if VIX rise helps longs
    vanna_sensitivity:    float            # $ delta change per 1-pt VIX move
    pin_strike:           Optional[float]  # Strike with max open interest (magnet)
    pin_probability:      float            # 0–1: likelihood of closing near pin
    time_decay_stage:     str              # 'morning' | 'midday' | 'afternoon' | 'final_hour'
    total_0dte_oi:        int
    call_put_ratio_0dte:  float            # 0DTE call OI / put OI
    strike_gex_map:       Dict[float, float]


# ─── Main function ────────────────────────────────────────────────────────────

def compute_0dte_gex(
    contracts: List[OptionContract],
    spot:      float,
    now:       Optional[datetime] = None,
) -> ZeroDTEResult:
    """
    Filters to 0DTE contracts only, then runs the full 0DTE analysis.
    """
    now       = now or datetime.now()
    today_str = date.today().isoformat()

    # ── Filter to 0DTE contracts ──────────────────────────────────────────────
    zero_dte = [c for c in contracts if c.expiration == today_str and c.gamma > 0]

    if not zero_dte:
        logger.warning("0DTE: no contracts found for %s", today_str)
        return _empty_result()

    # ── Per-strike GEX ────────────────────────────────────────────────────────
    strike_gex: Dict[float, float] = {}
    strike_oi:  Dict[float, int]   = {}
    call_oi = put_oi = 0

    for c in zero_dte:
        dollar_gex = c.gamma * c.open_interest * CONTRACT_MULTIPLIER * (spot ** 2) / 100
        signed     = dollar_gex if c.option_type == "call" else -dollar_gex
        strike_gex[c.strike] = strike_gex.get(c.strike, 0.0) + signed
        strike_oi[c.strike]  = strike_oi.get(c.strike, 0) + c.open_interest

        if c.option_type == "call":
            call_oi += c.open_interest
        else:
            put_oi += c.open_interest

    net_gex_raw = sum(strike_gex.values())
    net_gex_mil = net_gex_raw / 1e6

    # ── Flip point ────────────────────────────────────────────────────────────
    flip_point = _find_0dte_flip(strike_gex, spot)

    # ── Gamma walls ───────────────────────────────────────────────────────────
    wall_above = _find_gamma_wall(strike_gex, spot, direction="above")
    wall_below = _find_gamma_wall(strike_gex, spot, direction="below")

    # ── Max OI pin ────────────────────────────────────────────────────────────
    pin_strike = max(strike_oi, key=lambda s: strike_oi[s]) if strike_oi else None
    pin_prob   = _estimate_pin_probability(spot, pin_strike, zero_dte, now)

    # ── Charm analysis ────────────────────────────────────────────────────────
    charm_dir, charm_mag = _compute_charm(zero_dte, spot, now)

    # ── Vanna analysis ────────────────────────────────────────────────────────
    vanna_dir, vanna_sens = _compute_vanna(zero_dte, spot)

    # ── Time decay stage ──────────────────────────────────────────────────────
    stage = _time_decay_stage(now)

    total_oi = sum(strike_oi.values())
    cp_ratio = call_oi / put_oi if put_oi > 0 else float("inf")

    return ZeroDTEResult(
        net_gex_millions    = round(net_gex_mil, 2),
        flip_point          = flip_point,
        gamma_wall_above    = wall_above,
        gamma_wall_below    = wall_below,
        charm_direction     = charm_dir,
        charm_magnitude     = round(charm_mag, 2),
        vanna_direction     = vanna_dir,
        vanna_sensitivity   = round(vanna_sens, 2),
        pin_strike          = pin_strike,
        pin_probability     = round(pin_prob, 3),
        time_decay_stage    = stage,
        total_0dte_oi       = total_oi,
        call_put_ratio_0dte = round(cp_ratio, 2),
        strike_gex_map      = {k: round(v / 1e6, 3) for k, v in strike_gex.items()},
    )


# ─── Charm ───────────────────────────────────────────────────────────────────

def _compute_charm(
    contracts: List[OptionContract],
    spot:      float,
    now:       datetime,
) -> Tuple[str, float]:
    """
    Charm = dDelta/dTime.  As time passes, delta drifts:
     - OTM calls lose delta → dealers SELL underlying to hedge (bearish charm pressure)
     - OTM puts gain delta  → dealers BUY underlying (bullish charm pressure)

    We estimate net charm flow direction from net delta of near-ATM positions.
    """
    open_dt = datetime.combine(now.date(), time(9, 30))
    mins_elapsed = max(1, (now - open_dt).total_seconds() / 60)
    remaining_mins = max(1, MINUTES_PER_TRADING_DAY - mins_elapsed)

    # Charm approximation: charm ≈ -gamma × (S × sigma) / (2 × T)
    # For 0DTE T is in trading-day fractions
    T = remaining_mins / MINUTES_PER_TRADING_DAY   # fraction of day remaining

    net_charm_delta = 0.0
    for c in contracts:
        if c.iv <= 0 or c.gamma <= 0:
            continue
        # dDelta/dT per contract (in shares)
        charm_per_contract = -c.gamma * spot * c.iv / (2 * max(T, 0.01))
        signed = charm_per_contract if c.option_type == "call" else -charm_per_contract
        net_charm_delta += signed * c.open_interest * CONTRACT_MULTIPLIER

    if abs(net_charm_delta) < 1e5:
        return "neutral", 0.0
    direction = "bullish" if net_charm_delta > 0 else "bearish"
    return direction, abs(net_charm_delta / 1e6)   # in $M of delta


# ─── Vanna ───────────────────────────────────────────────────────────────────

def _compute_vanna(
    contracts: List[OptionContract],
    spot:      float,
) -> Tuple[str, float]:
    """
    Vanna = dDelta/dIV.
    A VIX rise increases IV → changes delta of all positions → dealers re-hedge.

    Net vanna determines whether a VIX spike is bullish or bearish for SPX:
    - Positive net vanna + VIX rise → dealers buy (bullish)
    - Negative net vanna + VIX rise → dealers sell (bearish)
    """
    net_vanna = 0.0
    for c in contracts:
        if c.gamma <= 0 or c.iv <= 0:
            continue
        # vanna ≈ (delta × (1 - delta)) / (spot × iv)  [simplified]
        d = abs(c.delta)
        vanna_approx = d * (1 - d) / max(spot * c.iv, 0.01)
        signed = vanna_approx if c.option_type == "call" else -vanna_approx
        net_vanna += signed * c.open_interest * CONTRACT_MULTIPLIER

    if abs(net_vanna) < 1:
        return "neutral", 0.0

    direction = "bullish" if net_vanna > 0 else "bearish"
    return direction, abs(net_vanna)


# ─── Helpers ─────────────────────────────────────────────────────────────────

def _find_0dte_flip(
    strike_gex: Dict[float, float],
    spot:       float,
) -> Optional[float]:
    """Find nearest 0DTE gamma flip to spot price."""
    sorted_strikes = sorted(strike_gex.keys())
    cumulative = 0.0
    prev_strike = spot
    for s in sorted_strikes:
        prev = cumulative
        cumulative += strike_gex[s]
        if prev != 0 and prev * cumulative < 0:
            ratio = abs(prev) / (abs(prev) + abs(cumulative))
            return round(prev_strike + ratio * (s - prev_strike), 2)
        prev_strike = s
    return None


def _find_gamma_wall(
    strike_gex: Dict[float, float],
    spot:       float,
    direction:  str,
) -> Optional[float]:
    if direction == "above":
        candidates = {s: g for s, g in strike_gex.items() if s > spot and g > 0}
    else:
        candidates = {s: g for s, g in strike_gex.items() if s < spot and g < 0}

    if not candidates:
        return None
    if direction == "above":
        return max(candidates, key=lambda s: candidates[s])
    else:
        return min(candidates, key=lambda s: candidates[s])


def _estimate_pin_probability(
    spot:       float,
    pin_strike: Optional[float],
    contracts:  List[OptionContract],
    now:        datetime,
) -> float:
    """
    Very simplified pin probability:
    High when: price is within 2 points of a high-OI strike AND < 1 hour to close.
    """
    if pin_strike is None:
        return 0.0

    close_time = datetime.combine(now.date(), time(16, 0))
    mins_to_close = max(0, (close_time - now).total_seconds() / 60)
    distance = abs(spot - pin_strike)

    if distance > 10:
        return 0.05
    if distance <= 2 and mins_to_close < 60:
        return 0.70
    if distance <= 5 and mins_to_close < 90:
        return 0.40

    return max(0.0, 0.30 - distance * 0.03)


def _time_decay_stage(now: datetime) -> str:
    open_dt = datetime.combine(now.date(), time(9, 30))
    mins    = (now - open_dt).total_seconds() / 60

    if mins < 60:   return "morning"
    if mins < 150:  return "midday"
    if mins < 300:  return "afternoon"
    return "final_hour"


def _empty_result() -> ZeroDTEResult:
    return ZeroDTEResult(
        net_gex_millions=0.0, flip_point=None,
        gamma_wall_above=None, gamma_wall_below=None,
        charm_direction="neutral", charm_magnitude=0.0,
        vanna_direction="neutral", vanna_sensitivity=0.0,
        pin_strike=None, pin_probability=0.0,
        time_decay_stage="morning", total_0dte_oi=0,
        call_put_ratio_0dte=1.0, strike_gex_map={},
    )
