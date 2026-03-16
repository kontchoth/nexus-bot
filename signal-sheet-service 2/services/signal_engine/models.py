"""
Nexus Bot — Data Models
All dataclasses used across the signal engine.
"""
from dataclasses import dataclass, field, asdict
from typing import Optional, List, Dict, Any
from enum import Enum
from datetime import datetime


# ─────────────────────────────────────────────
# Enums
# ─────────────────────────────────────────────

class SignalDirection(str, Enum):
    LONG    = "long"
    SHORT   = "short"
    NEUTRAL = "neutral"
    WAIT    = "wait"

class SignalStrength(str, Enum):
    EXTREMELY_BULLISH = "Extremely Bullish"
    BULLISH           = "Bullish"
    NEUTRAL           = "Neutral"
    BEARISH           = "Bearish"
    EXTREMELY_BEARISH = "Extremely Bearish"

class Regime(str, Enum):
    SHORT_GAMMA_AMPLIFIED = "Short Gamma — Amplified"
    SHORT_GAMMA_STANDARD  = "Short Gamma — Standard"
    LONG_GAMMA_STANDARD   = "Long Gamma — Standard"
    LONG_GAMMA_AMPLIFIED  = "Long Gamma — Amplified"

class DPLColor(str, Enum):
    GREEN = "green"
    RED   = "red"
    GREY  = "grey"

class BreadthLabel(str, Enum):
    SIGNIFICANT_BROAD_PARTICIPATION = "Significant Broad Participation"
    MODERATE_PARTICIPATION          = "Moderate Participation"
    NEUTRAL                         = "Neutral"
    MODERATE_DECLINE                = "Moderate Decline Participation"
    SIGNIFICANT_BROAD_DECLINE       = "Significant Broad Decline"

class TradeAction(str, Enum):
    GO_LONG      = "GO_LONG"
    GO_SHORT     = "GO_SHORT"
    WAIT_REASSESS = "WAIT_REASSESS"
    SIGNIFICANT_GAP = "SIGNIFICANT_GAP"


# ─────────────────────────────────────────────
# Market Data
# ─────────────────────────────────────────────

@dataclass
class Candle:
    timestamp: datetime
    open:   float
    high:   float
    low:    float
    close:  float
    volume: int

@dataclass
class Quote:
    symbol:       str
    bid:          float
    ask:          float
    last:         float
    volume:       int
    open:         Optional[float]
    prev_close:   float
    timestamp:    datetime

@dataclass
class OptionContract:
    symbol:        str
    underlying:    str
    strike:        float
    expiration:    str
    option_type:   str        # 'call' | 'put'
    bid:           float
    ask:           float
    last:          float
    volume:        int
    open_interest: int
    iv:            float      # implied volatility (decimal)
    delta:         float
    gamma:         float
    theta:         float
    vega:          float


# ─────────────────────────────────────────────
# Computed Signals
# ─────────────────────────────────────────────

@dataclass
class GEXResult:
    net_gex_billions:  float
    flip_point:        float
    regime:            Regime
    wall_vs_rally:     Optional[float]   # nearest call wall above spot
    wall_vs_rally_gex: Optional[float]
    wall_vs_drop:      Optional[float]   # nearest put wall below spot
    wall_vs_drop_gex:  Optional[float]
    range_estimate_pts: float            # 1-day expected move in points
    strike_gex_map:    Dict[float, float] = field(default_factory=dict)

@dataclass
class GapInfo:
    is_significant:  bool
    direction:       str    # 'up' | 'down' | 'flat'
    gap_pct:         float
    gap_points:      float

@dataclass
class DPLResult:
    color:           DPLColor
    separation:      float   # price - VWAP
    separation_pct:  float
    vwap:            float
    is_above:        bool
    breakup:         bool    # price crossed above DPL
    breakdown:       bool    # price crossed below DPL

@dataclass
class ADResult:
    signal:    SignalStrength
    direction: SignalDirection
    ratio:     float
    advances:  int
    declines:  int

@dataclass
class SignalSheet:
    """The full SPY Daily Signal Sheet — mirrors the UI card."""
    # ── Header
    date:              str
    yesterday_close:   float
    vol_at_open:       Optional[int]
    intraday_news:     Optional[str]

    # ── Market context
    net_gex:           float
    flip_point:        float
    regime:            Regime
    wall_vs_rally:     Optional[float]
    wall_vs_rally_gex: Optional[float]
    wall_vs_drop:      Optional[float]
    wall_vs_drop_gex:  Optional[float]
    range_estimate_pts: float
    breadth:           BreadthLabel
    spy_premarket:     SignalStrength

    # ── Gap
    gap:               GapInfo

    # ── 7 Signals
    spy_component:     SignalStrength      # 1
    itod:              SignalDirection     # 2
    optimized_tod:     SignalDirection     # 3
    tod_gap:           SignalDirection     # 4
    dpl:               DPLResult          # 5
    ad_65:             ADResult           # 6
    dom_gap:           SignalDirection     # 7

    # ── Min-14 Reference
    min14_high:        Optional[float]
    min14_low:         Optional[float]

    # ── Decision
    action:            TradeAction
    action_reason:     str
    signals_unified:   bool
    unified_direction: Optional[SignalDirection]

    # ── Trade parameters
    itm_entry:         Optional[float]   # ITM entry price
    otm_strike_long:   Optional[float]   # OTM strike if going long
    otm_strike_short:  Optional[float]   # OTM strike if going short

    # ── Meta
    computed_at:       str               # ISO timestamp
    spy_spot:          float

    def to_dict(self) -> Dict[str, Any]:
        """Serialize to JSON-safe dict for WebSocket broadcast."""
        d = asdict(self)
        # Convert enums to their .value
        for k, v in d.items():
            if isinstance(v, Enum):
                d[k] = v.value
        return d
