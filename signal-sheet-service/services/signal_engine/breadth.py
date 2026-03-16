"""
Nexus Bot — NYSE Breadth Engine
Covers: $TICK proxy, TRIN (Arms Index), enhanced A/D, and composite breadth score.

IMPORTANT — Tradier limitation:
  Tradier production API does NOT provide real-time $TICK or TRIN directly.
  This module implements a best-effort proxy using Tradier data + a pluggable
  interface so you can swap in a real data source later (e.g. Polygon.io,
  Interactive Brokers, or a custom feed).

  Proxy approach:
    - $TICK proxy: Advance/Decline RATE across a large basket of liquid equities
    - TRIN proxy:  (Advances/Declines) / (Advancing Volume / Declining Volume)
                   computed from the same basket

  For production accuracy:
    Set REAL_TICK_SOURCE = True and provide a tick_provider callback.

Breadth signals used in the algorithm:
  - $TICK reading       → real-time market sentiment (±800 = extreme)
  - TRIN               → volume-weighted AD (< 0.7 bullish, > 1.3 bearish)
  - AD ratio           → classic advance/decline for AD 6.5 signal
  - Composite score    → 0–100 (replaces simple AD breadth label)
  - Breadth divergence → breadth rising but price falling = bullish divergence
"""
import logging
from dataclasses import dataclass, field
from typing import List, Dict, Optional, Callable
from .models import BreadthLabel

logger = logging.getLogger(__name__)

# ─── $TICK basket (most liquid NYSE equities, good breadth proxy) ─────────────
# Replace / extend with full S&P 500 list for best accuracy
BREADTH_BASKET = [
    # Mega-cap tech / growth
    "AAPL", "MSFT", "NVDA", "AMZN", "GOOGL", "META", "TSLA",
    # Finance
    "JPM", "BAC", "GS", "WFC", "BLK",
    # Healthcare
    "UNH", "JNJ", "LLY", "ABBV",
    # Industrials
    "CAT", "HON", "GE", "BA", "UPS",
    # Energy
    "XOM", "CVX", "COP",
    # Consumer
    "WMT", "HD", "COST", "MCD", "PG",
    # Materials + Utilities
    "LIN", "SHW", "NEE", "DUK",
    # Sector ETFs (broad coverage)
    "XLK", "XLF", "XLV", "XLC", "XLY", "XLP", "XLE", "XLI", "XLB", "XLRE", "XLU",
]


# ─── Result dataclass ─────────────────────────────────────────────────────────

@dataclass
class BreadthResult:
    # Raw counts
    advances:        int
    declines:        int
    unchanged:       int
    adv_volume:      float   # total volume of advancing issues
    dec_volume:      float   # total volume of declining issues

    # Derived metrics
    ad_ratio:        float   # advances / declines
    tick_proxy:      float   # synthetic $TICK (-1000 to +1000 equivalent)
    trin:            float   # Arms Index: (adv/dec) / (adv_vol/dec_vol)
    composite_score: float   # 0–100 (50 = neutral)

    # Labels
    breadth_label:   BreadthLabel
    tick_label:      str     # "Extreme Buy" | "Bullish" | "Neutral" | "Bearish" | "Extreme Sell"
    trin_label:      str     # "Bullish" | "Neutral" | "Bearish"

    # Divergence flags
    breadth_diverging_up:   bool   # breadth improving while price is falling
    breadth_diverging_down: bool   # breadth deteriorating while price is rising

    notes: str = ""


# ─── Main function ────────────────────────────────────────────────────────────

def compute_breadth(
    quote_data: Dict[str, Dict],          # {symbol: {last, prev_close, volume}}
    spot_change: float = 0.0,             # SPX/SPY % change (for divergence)
    real_tick: Optional[float] = None,    # Inject real $TICK if available
    real_trin: Optional[float] = None,    # Inject real TRIN if available
) -> BreadthResult:
    """
    Compute full breadth reading from Tradier quote data.

    quote_data format:
      {"AAPL": {"last": 185.0, "prev_close": 184.0, "volume": 45000000}, ...}
    """
    advances = declines = unchanged = 0
    adv_vol  = dec_vol  = 0.0

    for sym, q in quote_data.items():
        last  = float(q.get("last") or 0)
        prev  = float(q.get("prev_close") or last)
        vol   = float(q.get("volume") or 0)

        if prev == 0:
            continue

        change_pct = (last - prev) / prev * 100
        if change_pct > 0.10:
            advances += 1
            adv_vol  += vol
        elif change_pct < -0.10:
            declines += 1
            dec_vol  += vol
        else:
            unchanged += 1

    total = advances + declines
    ad_ratio = (advances / declines) if declines > 0 else float("inf")

    # ── $TICK proxy ───────────────────────────────────────────────────────────
    if real_tick is not None:
        tick_proxy = real_tick
    else:
        # Normalize to ±1000 range based on basket
        basket_size = max(total, 1)
        tick_proxy = (advances - declines) / basket_size * 1000

    # ── TRIN ─────────────────────────────────────────────────────────────────
    if real_trin is not None:
        trin = real_trin
    else:
        if declines > 0 and dec_vol > 0 and adv_vol > 0:
            trin = (advances / declines) / (adv_vol / dec_vol)
        else:
            trin = 1.0   # neutral

    # ── Composite score (0–100) ───────────────────────────────────────────────
    composite = _composite_score(ad_ratio, tick_proxy, trin)

    # ── Labels ────────────────────────────────────────────────────────────────
    breadth_label = _breadth_label(advances, total)
    tick_label    = _tick_label(tick_proxy)
    trin_label    = _trin_label(trin)

    # ── Divergence ───────────────────────────────────────────────────────────
    breadth_positive = composite > 55
    breadth_negative = composite < 45
    price_positive   = spot_change > 0.10
    price_negative   = spot_change < -0.10

    diverging_up   = breadth_positive and price_negative  # breadth up, price down
    diverging_down = breadth_negative and price_positive  # breadth down, price up

    notes = _build_notes(tick_proxy, trin, diverging_up, diverging_down, composite)

    return BreadthResult(
        advances        = advances,
        declines        = declines,
        unchanged       = unchanged,
        adv_volume      = adv_vol,
        dec_volume      = dec_vol,
        ad_ratio        = round(ad_ratio, 2) if ad_ratio != float("inf") else 99.0,
        tick_proxy      = round(tick_proxy, 1),
        trin            = round(trin, 3),
        composite_score = round(composite, 1),
        breadth_label   = breadth_label,
        tick_label      = tick_label,
        trin_label      = trin_label,
        breadth_diverging_up   = diverging_up,
        breadth_diverging_down = diverging_down,
        notes           = notes,
    )


# ─── Helpers ─────────────────────────────────────────────────────────────────

def _composite_score(
    ad_ratio:   float,
    tick_proxy: float,
    trin:       float,
) -> float:
    """
    Weighted composite: 40% AD, 35% TICK, 25% TRIN (inverted).
    Returns 0–100. 50 = neutral.
    """
    # Normalize AD ratio to 0–100
    ad_score = min(100, max(0, (ad_ratio / (ad_ratio + 1)) * 100))

    # Normalize TICK proxy to 0–100 (range: -1000 to +1000)
    tick_score = min(100, max(0, (tick_proxy + 1000) / 20))

    # Normalize TRIN (inverted): TRIN < 1 = bullish, > 1 = bearish
    # Map: TRIN 0.5 → 80, TRIN 1.0 → 50, TRIN 2.0 → 20
    trin_score = min(100, max(0, (1 / max(trin, 0.1)) * 50))

    return 0.40 * ad_score + 0.35 * tick_score + 0.25 * trin_score


def _breadth_label(advances: int, total: int) -> BreadthLabel:
    if total == 0:
        return BreadthLabel.NEUTRAL
    pct = advances / total * 100
    if pct >= 70: return BreadthLabel.SIGNIFICANT_BROAD_PARTICIPATION
    if pct >= 55: return BreadthLabel.MODERATE_PARTICIPATION
    if pct >= 45: return BreadthLabel.NEUTRAL
    if pct >= 30: return BreadthLabel.MODERATE_DECLINE
    return BreadthLabel.SIGNIFICANT_BROAD_DECLINE


def _tick_label(tick: float) -> str:
    if tick >  600: return "Extreme Buy"
    if tick >  200: return "Bullish"
    if tick > -200: return "Neutral"
    if tick > -600: return "Bearish"
    return "Extreme Sell"


def _trin_label(trin: float) -> str:
    if trin < 0.70: return "Bullish"
    if trin < 1.30: return "Neutral"
    return "Bearish"


def _build_notes(
    tick:           float,
    trin:           float,
    diverging_up:   bool,
    diverging_down: bool,
    composite:      float,
) -> str:
    parts = []
    if abs(tick) > 800:
        parts.append(f"⚡ Extreme $TICK ({tick:+.0f}) — high conviction move.")
    if trin < 0.50:
        parts.append("TRIN very low (<0.50) — aggressive buying, risk of reversal.")
    if trin > 2.0:
        parts.append("TRIN very high (>2.0) — aggressive selling, watch for bounce.")
    if diverging_up:
        parts.append("📈 Bullish divergence: breadth improving while price dips.")
    if diverging_down:
        parts.append("📉 Bearish divergence: breadth weakening while price rises.")
    return " | ".join(parts) if parts else ""


# ─── Tradier helper: build quote_data dict for breadth basket ────────────────

def fetch_breadth_basket(tradier_client) -> Dict[str, Dict]:
    """
    Fetches quotes for the breadth basket from Tradier.
    Call this from signal_computer.py before compute_breadth().
    """
    try:
        quotes = tradier_client.get_quotes(BREADTH_BASKET)
        return {
            sym: {
                "last":       q.last,
                "prev_close": q.prev_close,
                "volume":     q.volume,
            }
            for sym, q in quotes.items()
        }
    except Exception as e:
        logger.error("fetch_breadth_basket failed: %s", e)
        return {}
