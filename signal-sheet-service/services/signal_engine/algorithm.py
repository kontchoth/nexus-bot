"""
Nexus Bot — Decision Algorithm
Mirrors the 3-step logic shown on the SPY Daily Signal Sheet:

  Step 1 — Significant gap at open?
            → If yes: go to Significant Gap Panel (wait for DPL separation)
  Step 2 — No significant gap AND all 6 model signals unified?
            → Go Long  (if all agree LONG)
            → Go Short (if all agree SHORT)
  Step 3 — Signals not unified → go to Discordant Signal Panel
            → DPL is ALWAYS the tiebreaker
            → Confirm with AD 6.5, DOM/Gap, T+100 (range/GEX)
            → If DPL = WAIT → WAIT_REASSESS (hold through S35 window)

Trade parameters:
  GO LONG  — Enter near min-14 LOW
             ITM contracts $2k  → exit at $3k–$4.5k
             OTM contracts $1k  → strike = min14_low – 50pts
  GO SHORT — Enter near min-14 HIGH
             ITM contracts $2k  → exit at $3k–$4.5k
             OTM contracts $1k  → strike = min14_high + 50pts
"""
import logging
from typing import List, Optional
from .models import (
    SignalDirection, SignalStrength, DPLColor,
    DPLResult, ADResult, GapInfo,
    TradeAction, SignalSheet, GEXResult, BreadthLabel, Regime,
)
from .signals import (
    compute_spy_component, detect_gap,
    compute_itod, compute_optimized_tod,
    compute_tod_gap, compute_dpl,
    compute_ad_65, compute_dom_gap,
    compute_min14_reference,
)
from .gex import compute_gex, compute_breadth
from .tradier_client import TradierClient

from datetime import datetime, date

logger = logging.getLogger(__name__)

# ─── S15→S35 Confirmation window (minutes since open) ───────────────────────
S15_OPEN_MIN = 15
S35_OPEN_MIN = 35


# ═══════════════════════════════════════════════════════════════════════════════
# Main algorithm entry-point
# ═══════════════════════════════════════════════════════════════════════════════

def build_signal_sheet(client: TradierClient, now: Optional[datetime] = None) -> SignalSheet:
    """
    Full pipeline: fetch market data → compute all signals → run algorithm.
    Called by Lambda every 5 minutes during market hours.
    """
    now = now or datetime.now()

    # ── 1. Raw market data ────────────────────────────────────────────────────
    spy_quote     = client.get_quote("SPY")
    candles_5min  = client.get_intraday_candles("SPY", interval="5min")
    candles_1min  = client.get_intraday_candles("SPY", interval="1min")
    options_chain = client.get_options_chain("SPY")
    ad_data       = client.get_advance_decline()

    spot = spy_quote.last

    # ── 2. Context signals ────────────────────────────────────────────────────
    gex_result    = compute_gex(options_chain, spot)
    gap           = detect_gap(spy_quote.open or spot, spy_quote.prev_close)
    spy_component = compute_spy_component(spy_quote)
    breadth_label = compute_breadth(ad_data["advances"], ad_data["declines"])
    min14_high, min14_low = compute_min14_reference(candles_1min)

    # ── 3. 6 Model signals ────────────────────────────────────────────────────
    itod          = compute_itod(now, spy_component)
    opt_tod       = compute_optimized_tod(itod, candles_5min, gap)
    tod_gap       = compute_tod_gap(opt_tod, gap, now)
    dpl           = compute_dpl(candles_5min, spot)
    ad_65         = compute_ad_65(ad_data["advances"], ad_data["declines"])
    dom_gap       = compute_dom_gap(candles_5min, gap)

    # ── 4. Decision algorithm ─────────────────────────────────────────────────
    action, reason, unified, unified_dir = _run_algorithm(
        gap=gap, itod=itod, opt_tod=opt_tod,
        tod_gap=tod_gap, dpl=dpl, ad_65=ad_65, dom_gap=dom_gap,
    )

    # ── 5. OTM strike calculations ────────────────────────────────────────────
    otm_long  = round(min14_low  - 50, 0) if min14_low  else None
    otm_short = round(min14_high + 50, 0) if min14_high else None

    # ── 6. Assemble sheet ─────────────────────────────────────────────────────
    return SignalSheet(
        date               = date.today().isoformat(),
        yesterday_close    = spy_quote.prev_close,
        vol_at_open        = spy_quote.volume if spy_quote.volume > 0 else None,
        intraday_news      = None,          # populated externally if needed

        net_gex            = gex_result.net_gex_billions,
        flip_point         = gex_result.flip_point,
        regime             = gex_result.regime,
        wall_vs_rally      = gex_result.wall_vs_rally,
        wall_vs_rally_gex  = gex_result.wall_vs_rally_gex,
        wall_vs_drop       = gex_result.wall_vs_drop,
        wall_vs_drop_gex   = gex_result.wall_vs_drop_gex,
        range_estimate_pts = gex_result.range_estimate_pts,
        breadth            = breadth_label,
        spy_premarket      = spy_component,

        gap                = gap,

        spy_component      = spy_component,
        itod               = itod,
        optimized_tod      = opt_tod,
        tod_gap            = tod_gap,
        dpl                = dpl,
        ad_65              = ad_65,
        dom_gap            = dom_gap,

        min14_high         = min14_high,
        min14_low          = min14_low,

        action             = action,
        action_reason      = reason,
        signals_unified    = unified,
        unified_direction  = unified_dir,

        itm_entry          = min14_low  if action == TradeAction.GO_LONG  else (
                             min14_high if action == TradeAction.GO_SHORT else None),
        otm_strike_long    = otm_long,
        otm_strike_short   = otm_short,

        computed_at        = now.isoformat(),
        spy_spot           = round(spot, 2),
    )


# ═══════════════════════════════════════════════════════════════════════════════
# Algorithm core (pure function — no I/O, fully testable)
# ═══════════════════════════════════════════════════════════════════════════════

def _run_algorithm(
    *,
    gap:     GapInfo,
    itod:    SignalDirection,
    opt_tod: SignalDirection,
    tod_gap: SignalDirection,
    dpl:     DPLResult,
    ad_65:   ADResult,
    dom_gap: SignalDirection,
):
    """
    Returns (action, reason, unified, unified_direction).
    """

    # ── Step 1: Significant gap? ──────────────────────────────────────────────
    if gap.is_significant:
        return (
            TradeAction.SIGNIFICANT_GAP,
            f"Gap of {gap.gap_pct:+.2f}% detected. "
            "Track DPL separation + DOM 7.5 before entry. Wait for DPL color lock.",
            False,
            None,
        )

    # ── Collect the 6 model directions ────────────────────────────────────────
    model_signals: List[SignalDirection] = [
        itod, opt_tod, tod_gap,
        _dpl_to_direction(dpl),
        ad_65.direction,
        dom_gap,
    ]

    # ── Step 2: All unified (no WAITs, no NEUTRALs, all same direction) ───────
    definitive = [s for s in model_signals if s in (SignalDirection.LONG, SignalDirection.SHORT)]
    all_unified = (
        len(definitive) == len(model_signals)
        and len(set(definitive)) == 1
    )

    if all_unified:
        direction = definitive[0]
        action    = TradeAction.GO_LONG if direction == SignalDirection.LONG else TradeAction.GO_SHORT
        return (
            action,
            f"All 6 models unified {direction.value.upper()}. High-confidence entry.",
            True,
            direction,
        )

    # ── Step 3: Discordant — DPL is the tiebreaker ────────────────────────────
    dpl_dir = _dpl_to_direction(dpl)

    if dpl_dir == SignalDirection.LONG:
        # Confirm with AD 6.5 and DOM/Gap
        if ad_65.direction in (SignalDirection.LONG, SignalDirection.NEUTRAL) \
                and dom_gap in (SignalDirection.LONG, SignalDirection.NEUTRAL):
            return (
                TradeAction.GO_LONG,
                "Discordant signals — DPL GREEN confirms LONG. "
                "AD 6.5 and DOM/Gap support. Enter near min-14 low.",
                False,
                SignalDirection.LONG,
            )

    if dpl_dir == SignalDirection.SHORT:
        if ad_65.direction in (SignalDirection.SHORT, SignalDirection.NEUTRAL) \
                and dom_gap in (SignalDirection.SHORT, SignalDirection.NEUTRAL):
            return (
                TradeAction.GO_SHORT,
                "Discordant signals — DPL RED confirms SHORT. "
                "AD 6.5 and DOM/Gap support. Enter near min-14 high.",
                False,
                SignalDirection.SHORT,
            )

    # ── WAIT / REASSESS ───────────────────────────────────────────────────────
    long_count  = sum(1 for s in definitive if s == SignalDirection.LONG)
    short_count = sum(1 for s in definitive if s == SignalDirection.SHORT)
    return (
        TradeAction.WAIT_REASSESS,
        f"Mixed signals ({long_count} LONG / {short_count} SHORT / "
        f"{len(model_signals) - len(definitive)} neutral). "
        "DPL not confirming. Monitor through S35 window for resolution.",
        False,
        None,
    )


# ── Helpers ───────────────────────────────────────────────────────────────────

def _dpl_to_direction(dpl: DPLResult) -> SignalDirection:
    if dpl.color == DPLColor.GREEN:
        return SignalDirection.LONG
    elif dpl.color == DPLColor.RED:
        return SignalDirection.SHORT
    else:
        return SignalDirection.NEUTRAL
