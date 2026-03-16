"""
Nexus Bot — GEX (Gamma Exposure) Engine
Computes: Net GEX, Flip Point, Regime, Wall levels, Range Estimate, Breadth.
"""
import math
import logging
from typing import List, Dict, Optional, Tuple
from .models import OptionContract, GEXResult, Regime, BreadthLabel

logger = logging.getLogger(__name__)

# ─── Constants ───────────────────────────────────────────────────────────────
CONTRACT_MULTIPLIER = 100          # 1 option contract = 100 shares
REGIME_AMPLIFIED_THRESHOLD = 2e9  # ±$2B in GEX → "Amplified"


def compute_gex(
    contracts: List[OptionContract],
    spot_price: float,
) -> GEXResult:
    """
    Full GEX calculation from an options chain.

    GEX per contract = Gamma × Open_Interest × Contract_Multiplier × Spot²
    (Dollar GEX — measures $ move in dealer hedging per 1% move in spot)

    Call GEX is positive (dealers are long gamma → stabilizing).
    Put GEX is negative (dealers are short gamma → amplifying).

    Net GEX = Sum(call_gex) + Sum(put_gex)
    """
    if not contracts:
        logger.warning("compute_gex: empty options chain — returning zeroed result")
        return GEXResult(
            net_gex_billions=0.0, flip_point=spot_price, regime=Regime.SHORT_GAMMA_STANDARD,
            wall_vs_rally=None, wall_vs_rally_gex=None,
            wall_vs_drop=None, wall_vs_drop_gex=None,
            range_estimate_pts=0.0,
        )

    # ── Per-strike GEX accumulator ───────────────────────────────────────────
    strike_gex: Dict[float, float] = {}

    for c in contracts:
        if c.gamma <= 0 or c.open_interest <= 0:
            continue

        dollar_gex = c.gamma * c.open_interest * CONTRACT_MULTIPLIER * (spot_price ** 2) / 100
        # Put GEX flips sign (dealers are short puts → short gamma)
        signed_gex = dollar_gex if c.option_type == "call" else -dollar_gex

        strike_gex[c.strike] = strike_gex.get(c.strike, 0.0) + signed_gex

    net_gex_raw = sum(strike_gex.values())
    net_gex_bil = net_gex_raw / 1e9

    # ── Regime ───────────────────────────────────────────────────────────────
    regime = _classify_regime(net_gex_raw)

    # ── Flip Point ───────────────────────────────────────────────────────────
    flip_point = _find_flip_point(strike_gex, spot_price)

    # ── Wall Levels ──────────────────────────────────────────────────────────
    wall_rally, wall_rally_gex = _find_call_wall(strike_gex, spot_price)
    wall_drop,  wall_drop_gex  = _find_put_wall(strike_gex, spot_price)

    # ── 1-Day Range Estimate (from ATM IV) ───────────────────────────────────
    range_pts = _estimate_daily_range(contracts, spot_price)

    return GEXResult(
        net_gex_billions   = round(net_gex_bil, 3),
        flip_point         = flip_point,
        regime             = regime,
        wall_vs_rally      = wall_rally,
        wall_vs_rally_gex  = round(wall_rally_gex / 1e6, 1) if wall_rally_gex else None,  # in $M
        wall_vs_drop       = wall_drop,
        wall_vs_drop_gex   = round(abs(wall_drop_gex) / 1e6, 1) if wall_drop_gex else None,
        range_estimate_pts = range_pts,
        strike_gex_map     = {k: round(v / 1e6, 2) for k, v in strike_gex.items()},
    )


# ─── Helpers ─────────────────────────────────────────────────────────────────

def _classify_regime(net_gex_raw: float) -> Regime:
    if net_gex_raw > REGIME_AMPLIFIED_THRESHOLD:
        return Regime.LONG_GAMMA_AMPLIFIED
    elif net_gex_raw > 0:
        return Regime.LONG_GAMMA_STANDARD
    elif net_gex_raw > -REGIME_AMPLIFIED_THRESHOLD:
        return Regime.SHORT_GAMMA_STANDARD
    else:
        return Regime.SHORT_GAMMA_AMPLIFIED


def _find_flip_point(
    strike_gex: Dict[float, float],
    spot_price: float,
) -> float:
    """
    Walk strikes from spot outward in both directions.
    Flip = the strike where cumulative GEX crosses zero.
    """
    sorted_strikes = sorted(strike_gex.keys())
    if not sorted_strikes:
        return spot_price

    # Walk upward from spot
    cumulative = 0.0
    prev_strike = spot_price
    for strike in sorted_strikes:
        prev_cumulative = cumulative
        cumulative += strike_gex[strike]
        if prev_cumulative != 0 and prev_cumulative * cumulative < 0:
            # Linear interpolation between the two strikes
            ratio = abs(prev_cumulative) / (abs(prev_cumulative) + abs(cumulative))
            return round(prev_strike + ratio * (strike - prev_strike), 2)
        prev_strike = strike

    # Fallback: return the strike with GEX closest to zero
    return min(strike_gex.keys(), key=lambda s: abs(strike_gex[s]))


def _find_call_wall(
    strike_gex: Dict[float, float],
    spot_price: float,
) -> Tuple[Optional[float], Optional[float]]:
    """
    Largest positive-GEX strike ABOVE spot → resistance / rally wall.
    Returns (strike, gex_value).
    """
    above = {s: g for s, g in strike_gex.items() if s > spot_price and g > 0}
    if not above:
        return None, None
    best = max(above, key=lambda s: above[s])
    return best, above[best]


def _find_put_wall(
    strike_gex: Dict[float, float],
    spot_price: float,
) -> Tuple[Optional[float], Optional[float]]:
    """
    Largest negative-GEX strike BELOW spot → support / drop wall.
    Returns (strike, gex_value).
    """
    below = {s: g for s, g in strike_gex.items() if s < spot_price and g < 0}
    if not below:
        return None, None
    best = min(below, key=lambda s: below[s])  # most negative = largest put wall
    return best, below[best]


def _estimate_daily_range(
    contracts: List[OptionContract],
    spot_price: float,
) -> float:
    """
    1-SD expected daily move = spot × (ATM_IV / sqrt(252)).
    ATM IV is the average IV of the two nearest-to-spot strikes (call+put).
    """
    atm_iv = _get_atm_iv(contracts, spot_price)
    if atm_iv <= 0:
        return 0.0
    daily_move = spot_price * (atm_iv / math.sqrt(252))
    return round(daily_move, 1)


def _get_atm_iv(
    contracts: List[OptionContract],
    spot_price: float,
) -> float:
    """Average IV of ATM call + ATM put for nearest expiry."""
    if not contracts:
        return 0.0

    nearest_exp = min(c.expiration for c in contracts)
    same_exp = [c for c in contracts if c.expiration == nearest_exp and c.iv > 0]

    # Find ATM strike
    strikes = sorted(set(c.strike for c in same_exp))
    if not strikes:
        return 0.0
    atm_strike = min(strikes, key=lambda s: abs(s - spot_price))

    atm_ivs = [c.iv for c in same_exp if c.strike == atm_strike]
    return sum(atm_ivs) / len(atm_ivs) if atm_ivs else 0.0


# ─── Breadth ─────────────────────────────────────────────────────────────────

def compute_breadth(advances: int, declines: int) -> BreadthLabel:
    """
    Converts A/D counts to a breadth label matching the signal sheet.
    """
    total = advances + declines
    if total == 0:
        return BreadthLabel.NEUTRAL

    pct = advances / total * 100

    if pct >= 70:
        return BreadthLabel.SIGNIFICANT_BROAD_PARTICIPATION
    elif pct >= 55:
        return BreadthLabel.MODERATE_PARTICIPATION
    elif pct >= 45:
        return BreadthLabel.NEUTRAL
    elif pct >= 30:
        return BreadthLabel.MODERATE_DECLINE
    else:
        return BreadthLabel.SIGNIFICANT_BROAD_DECLINE
