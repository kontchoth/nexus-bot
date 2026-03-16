"""
Nexus Bot — VIX Integration
Covers: VIX regime, VIX term structure (contango/backwardation),
        VIX/SPX divergence, and position-sizing multiplier.

Why VIX matters for every signal:
  - VIX directly measures the expected 1-SD 30-day SPX range (IV)
  - Short Gamma + High VIX = explosive moves; position sizing must shrink
  - VIX backwardation (VIX > VIX3M) = fear premium, not sustained trend
  - VIX/SPX divergence = internal market weakness (bullish trap or oversold)

Tradier symbols:
  VIX     → CBOE VIX (30-day implied vol)   use symbol: "VIX"
  VIX3M   → 3-month VIX                     use symbol: "VIX3M"  (CBOE)
  VVIX    → VIX of VIX (tail-risk gauge)    use symbol: "VVIX"
"""
import logging
from dataclasses import dataclass
from enum import Enum
from typing import Optional, List
from .models import Candle

logger = logging.getLogger(__name__)


# ─── Enums ───────────────────────────────────────────────────────────────────

class VIXRegime(str, Enum):
    CALM          = "Calm"              # VIX < 15
    NORMAL        = "Normal"            # 15 ≤ VIX < 20
    ELEVATED      = "Elevated"          # 20 ≤ VIX < 25
    HIGH          = "High"              # 25 ≤ VIX < 30
    FEAR          = "Fear"              # 30 ≤ VIX < 40
    EXTREME_FEAR  = "Extreme Fear"      # VIX ≥ 40

class VIXTermStructure(str, Enum):
    CONTANGO      = "Contango"          # VIX < VIX3M (normal, forward IV > spot IV)
    FLAT          = "Flat"              # VIX ≈ VIX3M
    BACKWARDATION = "Backwardation"     # VIX > VIX3M (fear premium, unstable)

class VIXSPXRelation(str, Enum):
    CONFIRMING    = "Confirming"        # VIX falling while SPX rising (healthy)
    DIVERGING_UP  = "Diverging Up"      # VIX rising while SPX rising (hidden weakness)
    DIVERGING_DOWN= "Diverging Down"    # VIX falling while SPX falling (dead-cat)
    ALIGNED_DOWN  = "Aligned Down"      # Both falling (vol crush / low conviction)


# ─── Result ──────────────────────────────────────────────────────────────────

@dataclass
class VIXResult:
    vix:               float
    vix3m:             Optional[float]
    vvix:              Optional[float]
    regime:            VIXRegime
    term_structure:    VIXTermStructure
    spx_relation:      VIXSPXRelation
    daily_range_1sd:   float    # Expected 1-SD SPX daily move in points
    position_size_mult: float   # Multiply base sizing by this (0.25 – 1.0)
    vix_change_pct:    float    # VIX % change from prev close
    is_vix_spike:      bool     # VIX jumped > 15% intraday (de-risk signal)
    notes:             str


# ─── Main function ────────────────────────────────────────────────────────────

def compute_vix(
    vix_last:       float,
    vix_prev:       float,
    spx_spot:       float,
    spx_prev:       float,
    vix3m_last:     Optional[float] = None,
    vvix_last:      Optional[float] = None,
) -> VIXResult:
    """
    Full VIX analysis used to overlay and adjust all 7 signals.
    """
    # ── 1. Regime ─────────────────────────────────────────────────────────────
    regime = _classify_vix_regime(vix_last)

    # ── 2. Term structure ─────────────────────────────────────────────────────
    term_structure = _classify_term_structure(vix_last, vix3m_last)

    # ── 3. SPX / VIX relation ─────────────────────────────────────────────────
    spx_change  = spx_spot  - spx_prev
    vix_change  = vix_last  - vix_prev
    spx_relation = _classify_vix_spx_relation(spx_change, vix_change)

    # ── 4. 1-SD daily range estimate from VIX ─────────────────────────────────
    # VIX is 30-day annualized IV → daily = VIX / sqrt(252) → points = spot × daily%
    import math
    daily_iv    = vix_last / 100 / math.sqrt(252)
    range_1sd   = round(spx_spot * daily_iv, 1)

    # ── 5. Intraday VIX spike ─────────────────────────────────────────────────
    vix_change_pct = (vix_last - vix_prev) / vix_prev * 100 if vix_prev > 0 else 0.0
    is_spike       = vix_change_pct > 15.0

    # ── 6. Position-sizing multiplier ─────────────────────────────────────────
    # Shrink position size as VIX rises — preserves capital in high-vol regimes
    size_mult = _position_size_multiplier(vix_last, is_spike, term_structure)

    # ── 7. Human-readable notes ───────────────────────────────────────────────
    notes = _build_notes(regime, term_structure, spx_relation, is_spike, vvix_last)

    return VIXResult(
        vix               = round(vix_last,  2),
        vix3m             = round(vix3m_last, 2) if vix3m_last else None,
        vvix              = round(vvix_last,  2) if vvix_last  else None,
        regime            = regime,
        term_structure    = term_structure,
        spx_relation      = spx_relation,
        daily_range_1sd   = range_1sd,
        position_size_mult= round(size_mult, 2),
        vix_change_pct    = round(vix_change_pct, 2),
        is_vix_spike      = is_spike,
        notes             = notes,
    )


# ─── Helpers ─────────────────────────────────────────────────────────────────

def _classify_vix_regime(vix: float) -> VIXRegime:
    if vix >= 40:  return VIXRegime.EXTREME_FEAR
    if vix >= 30:  return VIXRegime.FEAR
    if vix >= 25:  return VIXRegime.HIGH
    if vix >= 20:  return VIXRegime.ELEVATED
    if vix >= 15:  return VIXRegime.NORMAL
    return VIXRegime.CALM


def _classify_term_structure(
    vix: float,
    vix3m: Optional[float],
) -> VIXTermStructure:
    if vix3m is None:
        return VIXTermStructure.FLAT  # unknown

    spread = vix - vix3m
    if spread > 1.5:
        return VIXTermStructure.BACKWARDATION
    elif spread < -1.5:
        return VIXTermStructure.CONTANGO
    else:
        return VIXTermStructure.FLAT


def _classify_vix_spx_relation(
    spx_change: float,
    vix_change:  float,
    threshold:   float = 0.5,
) -> VIXSPXRelation:
    spx_up = spx_change > threshold
    spx_dn = spx_change < -threshold
    vix_up = vix_change > 0.3
    vix_dn = vix_change < -0.3

    if spx_up and vix_dn:
        return VIXSPXRelation.CONFIRMING
    elif spx_up and vix_up:
        return VIXSPXRelation.DIVERGING_UP    # SPX rising + VIX rising = unstable
    elif spx_dn and vix_dn:
        return VIXSPXRelation.DIVERGING_DOWN  # SPX falling + VIX falling = apathy
    else:
        return VIXSPXRelation.ALIGNED_DOWN


def _position_size_multiplier(
    vix:            float,
    is_spike:       bool,
    term_structure: VIXTermStructure,
) -> float:
    """
    Scale position size inversely with VIX.
    Base: $2k ITM + $1k OTM (full size = 1.0×)
    VIX ≥ 30 backwardation spike = 0.25× (quarter size, preserve capital)
    """
    if is_spike:
        return 0.25   # De-risk on any intraday VIX spike > 15%

    if term_structure == VIXTermStructure.BACKWARDATION:
        base_mult = 0.5   # Backwardation = fear premium = widen stops + cut size
    else:
        base_mult = 1.0

    # VIX-scaled reduction
    if vix >= 40:
        return base_mult * 0.25
    elif vix >= 30:
        return base_mult * 0.50
    elif vix >= 25:
        return base_mult * 0.65
    elif vix >= 20:
        return base_mult * 0.80
    else:
        return base_mult * 1.00   # Normal, full size


def _build_notes(
    regime:         VIXRegime,
    term_structure: VIXTermStructure,
    spx_relation:   VIXSPXRelation,
    is_spike:       bool,
    vvix:           Optional[float],
) -> str:
    parts = []
    if is_spike:
        parts.append("⚠️ VIX SPIKE — reduce size immediately, widen stops.")
    if term_structure == VIXTermStructure.BACKWARDATION:
        parts.append("VIX in backwardation (fear premium) — moves may reverse quickly.")
    if spx_relation == VIXSPXRelation.DIVERGING_UP:
        parts.append("SPX rising but VIX rising — hidden weakness, trail stops tightly.")
    if regime in (VIXRegime.FEAR, VIXRegime.EXTREME_FEAR):
        parts.append(f"{regime.value} regime — use limit orders only, avoid chasing.")
    if vvix and vvix > 120:
        parts.append(f"VVIX={vvix:.0f} elevated — tail-risk hedging active, expect whipsaws.")
    return " | ".join(parts) if parts else "Normal volatility conditions."
