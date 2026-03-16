"""
Nexus Bot — Decision Algorithm v2
Full pipeline: all 7 signals + VIX + 0DTE GEX + Breadth + T+100 + DOM 7.5.

This replaces algorithm.py. Rename to algorithm.py when ready.

New additions vs v1:
  - VIX regime overlay on every signal weight
  - 0DTE GEX for intraday gamma wall awareness
  - TRIN / $TICK composite breadth (replaces sector-ETF proxy)
  - DOM 7.5 threshold in the Significant Gap panel
  - T+100 inflection check in the Discordant panel
  - Position sizing multiplier from VIX (shrinks size in fear regimes)
  - Charm/Vanna direction factored into GO LONG / GO SHORT notes
"""
import logging
from typing import Optional, Tuple
from datetime import datetime, date

from .models import (
    SignalDirection, SignalStrength, DPLColor,
    DPLResult, ADResult, GapInfo, GEXResult,
    TradeAction, SignalSheet, BreadthLabel, Regime,
)
from .signals import (
    compute_spy_component, detect_gap,
    compute_itod, compute_optimized_tod,
    compute_tod_gap, compute_dpl,
    compute_ad_65, compute_dom_gap,
    compute_min14_reference,
)
from .gex import compute_gex
from .gex_0dte import compute_0dte_gex, ZeroDTEResult
from .vix import compute_vix, VIXResult, VIXRegime
from .breadth import compute_breadth, fetch_breadth_basket, BreadthResult
from .dom_t100 import compute_dom75, compute_t100_inflection, DOM75Result, T100Result
from .tradier_client import TradierClient

logger = logging.getLogger(__name__)


def build_signal_sheet_v2(client: TradierClient, now: Optional[datetime] = None) -> dict:
    """
    Full pipeline returning an enriched signal dict for DynamoDB + WebSocket.
    """
    now = now or datetime.now()

    # ─────────────────────────────────────────────────────────────────────────
    # 1. Raw market data
    # ─────────────────────────────────────────────────────────────────────────
    spy_quote     = client.get_quote("SPY")
    candles_5min  = client.get_intraday_candles("SPY", interval="5min")
    candles_1min  = client.get_intraday_candles("SPY", interval="1min")
    options_chain = client.get_options_chain("SPY")   # all-expiry for main GEX
    spx_chain     = client.get_options_chain("SPXW")  # 0DTE for 0DTE GEX

    # VIX quotes
    vix_quotes = client.get_quotes(["VIX", "VIX3M", "VVIX"])
    vix_last   = vix_quotes.get("VIX",  type("", (), {"last": 20.0, "prev_close": 20.0})()).last
    vix_prev   = vix_quotes.get("VIX",  type("", (), {"last": 20.0, "prev_close": 20.0})()).prev_close
    vix3m_last = vix_quotes.get("VIX3M", None)
    vvix_last  = vix_quotes.get("VVIX",  None)

    spot = spy_quote.last

    # ─────────────────────────────────────────────────────────────────────────
    # 2. Context: GEX, VIX, 0DTE, Breadth
    # ─────────────────────────────────────────────────────────────────────────
    gex_result   = compute_gex(options_chain, spot)
    dte0_result  = compute_0dte_gex(spx_chain, spot * 10, now)  # SPX ≈ 10× SPY
    vix_result   = compute_vix(
        vix_last   = vix_last,
        vix_prev   = vix_prev,
        spx_spot   = spot * 10,
        spx_prev   = spy_quote.prev_close * 10,
        vix3m_last = vix3m_last.last if vix3m_last else None,
        vvix_last  = vvix_last.last  if vvix_last  else None,
    )
    breadth_data    = fetch_breadth_basket(client)
    spx_change_pct  = (spot - spy_quote.prev_close) / spy_quote.prev_close * 100
    breadth_result  = compute_breadth(breadth_data, spot_change=spx_change_pct)

    gap            = detect_gap(spy_quote.open or spot, spy_quote.prev_close)
    spy_component  = compute_spy_component(spy_quote)
    min14_h, min14_l = compute_min14_reference(candles_1min)

    # ─────────────────────────────────────────────────────────────────────────
    # 3. 7 Signals
    # ─────────────────────────────────────────────────────────────────────────
    itod      = compute_itod(now, spy_component)
    opt_tod   = compute_optimized_tod(itod, candles_5min, gap)
    tod_gap   = compute_tod_gap(opt_tod, gap, now)
    dpl       = compute_dpl(candles_5min, spot)
    ad_65     = compute_ad_65(breadth_result.advances, breadth_result.declines)
    dom_gap   = compute_dom_gap(candles_5min, gap)

    # ─────────────────────────────────────────────────────────────────────────
    # 4. DOM 7.5 + T+100
    # ─────────────────────────────────────────────────────────────────────────
    dom75  = compute_dom75(candles_5min, vwap=dpl.vwap)
    t100   = compute_t100_inflection(
        candles_5min=candles_5min, now=now, vwap=dpl.vwap,
        dpl=dpl, gap=gap, spot=spot,
    )

    # ─────────────────────────────────────────────────────────────────────────
    # 5. Decision algorithm (VIX-aware)
    # ─────────────────────────────────────────────────────────────────────────
    action, reason, unified, unified_dir = _run_algorithm_v2(
        gap=gap, itod=itod, opt_tod=opt_tod,
        tod_gap=tod_gap, dpl=dpl, ad_65=ad_65, dom_gap=dom_gap,
        dom75=dom75, t100=t100, vix=vix_result,
        dte0=dte0_result, breadth=breadth_result,
    )

    # ─────────────────────────────────────────────────────────────────────────
    # 6. Position sizing (VIX-adjusted)
    # ─────────────────────────────────────────────────────────────────────────
    base_itm = 2000.0
    base_otm = 1000.0
    adj_itm  = round(base_itm * vix_result.position_size_mult)
    adj_otm  = round(base_otm * vix_result.position_size_mult)

    otm_long  = round(min14_l  - 50, 0) if min14_l  else None
    otm_short = round(min14_h  + 50, 0) if min14_h  else None

    # ─────────────────────────────────────────────────────────────────────────
    # 7. Build enriched payload
    # ─────────────────────────────────────────────────────────────────────────
    from dataclasses import asdict
    from enum import Enum

    def _safe(v):
        if isinstance(v, Enum): return v.value
        return v

    return {
        # ── header
        "date":             date.today().isoformat(),
        "computed_at":      now.isoformat(),
        "spy_spot":         round(spot, 2),
        "yesterday_close":  spy_quote.prev_close,

        # ── GEX
        "net_gex":          gex_result.net_gex_billions,
        "flip_point":       gex_result.flip_point,
        "regime":           gex_result.regime.value,
        "wall_vs_rally":    gex_result.wall_vs_rally,
        "wall_vs_drop":     gex_result.wall_vs_drop,
        "range_estimate_pts": gex_result.range_estimate_pts,

        # ── 0DTE
        "dte0_net_gex_m":   dte0_result.net_gex_millions,
        "dte0_flip":        dte0_result.flip_point,
        "dte0_wall_above":  dte0_result.gamma_wall_above,
        "dte0_wall_below":  dte0_result.gamma_wall_below,
        "dte0_charm_dir":   dte0_result.charm_direction,
        "dte0_vanna_dir":   dte0_result.vanna_direction,
        "dte0_pin_strike":  dte0_result.pin_strike,
        "dte0_pin_prob":    dte0_result.pin_probability,
        "dte0_stage":       dte0_result.time_decay_stage,
        "dte0_cp_ratio":    dte0_result.call_put_ratio_0dte,

        # ── VIX
        "vix":              vix_result.vix,
        "vix3m":            vix_result.vix3m,
        "vvix":             vix_result.vvix,
        "vix_regime":       vix_result.regime.value,
        "vix_term_struct":  vix_result.term_structure.value,
        "vix_spx_relation": vix_result.spx_relation.value,
        "vix_range_1sd":    vix_result.daily_range_1sd,
        "vix_size_mult":    vix_result.position_size_mult,
        "vix_spike":        vix_result.is_vix_spike,
        "vix_notes":        vix_result.notes,

        # ── Breadth
        "advances":         breadth_result.advances,
        "declines":         breadth_result.declines,
        "ad_ratio":         breadth_result.ad_ratio,
        "tick_proxy":       breadth_result.tick_proxy,
        "trin":             breadth_result.trin,
        "breadth_score":    breadth_result.composite_score,
        "breadth_label":    breadth_result.breadth_label.value,
        "tick_label":       breadth_result.tick_label,
        "trin_label":       breadth_result.trin_label,
        "breadth_div_up":   breadth_result.breadth_diverging_up,
        "breadth_div_down": breadth_result.breadth_diverging_down,
        "breadth_notes":    breadth_result.notes,

        # ── Gap
        "gap": {
            "is_significant": gap.is_significant,
            "direction":      gap.direction,
            "gap_pct":        gap.gap_pct,
            "gap_points":     gap.gap_points,
        },

        # ── 7 Signals
        "spy_component":    spy_component.value,
        "itod":             itod.value,
        "optimized_tod":    opt_tod.value,
        "tod_gap":          tod_gap.value,
        "dpl": {
            "color":          dpl.color.value,
            "separation":     dpl.separation,
            "separation_pct": dpl.separation_pct,
            "vwap":           dpl.vwap,
            "is_above":       dpl.is_above,
            "breakup":        dpl.breakup,
            "breakdown":      dpl.breakdown,
        },
        "ad_65": {
            "signal":    ad_65.signal.value,
            "direction": ad_65.direction.value,
            "ratio":     ad_65.ratio,
            "advances":  ad_65.advances,
            "declines":  ad_65.declines,
        },
        "dom_gap":  dom_gap.value,

        # ── DOM 7.5
        "dom75": {
            "ratio":      dom75.ratio,
            "direction":  dom75.direction.value,
            "label":      dom75.label,
            "is_extreme": dom75.is_extreme,
        },

        # ── T+100
        "t100": {
            "is_reached":       t100.is_reached,
            "mins_to_t100":     t100.minutes_to_t100,
            "spy_direction":    t100.spy_direction.value,
            "is_above_vwap":    t100.is_above_vwap,
            "trend_5min":       t100.trend_5min,
            "gap_filled":       t100.gap_filled,
            "confirms_dpl":     t100.confirms_dpl,
            "label":            t100.inflection_label,
            "t200_direction":   t100.t200_direction.value if t100.t200_direction else None,
        },

        # ── Min-14 Reference
        "min14_high": min14_h,
        "min14_low":  min14_l,

        # ── Decision
        "action":           action.value,
        "action_reason":    reason,
        "signals_unified":  unified,
        "unified_direction": unified_dir.value if unified_dir else None,

        # ── Trade parameters (VIX-adjusted)
        "itm_size":         adj_itm,
        "otm_size":         adj_otm,
        "itm_entry":        min14_l  if action == TradeAction.GO_LONG  else (
                            min14_h  if action == TradeAction.GO_SHORT else None),
        "otm_strike_long":  otm_long,
        "otm_strike_short": otm_short,
        "itm_exit_low":     round(adj_itm * 1.5)  if adj_itm else None,
        "itm_exit_high":    round(adj_itm * 2.25) if adj_itm else None,
    }


# ─── Algorithm core ───────────────────────────────────────────────────────────

def _run_algorithm_v2(
    *,
    gap:     GapInfo,
    itod:    SignalDirection,
    opt_tod: SignalDirection,
    tod_gap: SignalDirection,
    dpl:     DPLResult,
    ad_65:   ADResult,
    dom_gap: SignalDirection,
    dom75:   DOM75Result,
    t100:    T100Result,
    vix:     VIXResult,
    dte0:    ZeroDTEResult,
    breadth: BreadthResult,
):
    # ── Immediate de-risk conditions ──────────────────────────────────────────
    if vix.is_vix_spike:
        return (
            TradeAction.WAIT_REASSESS,
            f"⚠️ VIX spike +{vix.vix_change_pct:.1f}% — de-risk mode. "
            "No new entries until VIX stabilizes.",
            False, None,
        )

    # ── Step 1: Significant gap ───────────────────────────────────────────────
    if gap.is_significant:
        dom_note = f"DOM 7.5: {dom75.label} ({dom75.ratio:.1f}:1)."
        dte_note = (
            f"0DTE: charm={dte0.charm_direction}, vanna={dte0.vanna_direction}."
            if dte0.net_gex_millions != 0 else ""
        )
        return (
            TradeAction.SIGNIFICANT_GAP,
            f"Gap {gap.direction} {gap.gap_pct:+.2f}%. "
            f"Wait for DPL separation + {dom_note} {dte_note} "
            "Track DOM 7.5, DPL color lock, and S15–S35 all 3 machines.",
            False, None,
        )

    # ── Collect 6 model directions ────────────────────────────────────────────
    dpl_dir     = SignalDirection.LONG if dpl.color == DPLColor.GREEN else (
                  SignalDirection.SHORT if dpl.color == DPLColor.RED else SignalDirection.NEUTRAL)
    model_sigs  = [itod, opt_tod, tod_gap, dpl_dir, ad_65.direction, dom_gap]
    definitive  = [s for s in model_sigs if s in (SignalDirection.LONG, SignalDirection.SHORT)]
    all_same    = len(definitive) == len(model_sigs) and len(set(definitive)) == 1

    # ── Step 2: All unified ───────────────────────────────────────────────────
    if all_same:
        direction = definitive[0]
        action    = TradeAction.GO_LONG if direction == SignalDirection.LONG else TradeAction.GO_SHORT
        vix_note  = f" | VIX {vix.vix:.1f} ({vix.regime.value}), size ×{vix.position_size_mult}." \
                    if vix.position_size_mult < 1.0 else ""
        dte_note  = f" | 0DTE pin {dte0.pin_strike} ({dte0.pin_probability:.0%})." \
                    if dte0.pin_strike else ""
        return (
            action,
            f"All 6 models unified {direction.value.upper()}.{vix_note}{dte_note}",
            True, direction,
        )

    # ── Step 3: Discordant — DPL tiebreaker with T+100 and DOM 7.5 ───────────
    long_count  = sum(1 for s in definitive if s == SignalDirection.LONG)
    short_count = sum(1 for s in definitive if s == SignalDirection.SHORT)
    wait_count  = len(model_sigs) - len(definitive)

    # T+100 confirmation boost
    t100_confirms_long  = t100.is_reached and t100.spy_direction == SignalDirection.LONG
    t100_confirms_short = t100.is_reached and t100.spy_direction == SignalDirection.SHORT

    # DOM 7.5 confirmation
    dom_confirms_long  = dom75.direction in (SignalDirection.LONG,  SignalDirection.NEUTRAL)
    dom_confirms_short = dom75.direction in (SignalDirection.SHORT, SignalDirection.NEUTRAL)

    if dpl_dir == SignalDirection.LONG:
        if (ad_65.direction in (SignalDirection.LONG, SignalDirection.NEUTRAL)
                and dom_confirms_long):
            t100_note = " T+100 confirms." if t100_confirms_long else (
                        " ⚠️ T+100 not confirmed yet." if not t100.is_reached else " T+100 neutral.")
            return (
                TradeAction.GO_LONG,
                f"Discordant ({long_count}L/{short_count}S/{wait_count}W) — "
                f"DPL GREEN + AD {ad_65.ratio:.1f} + DOM {dom75.label}.{t100_note} "
                f"Enter near min-14 low. Breadth: {breadth.tick_label} / TRIN {breadth.trin:.2f}.",
                False, SignalDirection.LONG,
            )

    if dpl_dir == SignalDirection.SHORT:
        if (ad_65.direction in (SignalDirection.SHORT, SignalDirection.NEUTRAL)
                and dom_confirms_short):
            t100_note = " T+100 confirms." if t100_confirms_short else (
                        " ⚠️ T+100 not confirmed yet." if not t100.is_reached else " T+100 neutral.")
            return (
                TradeAction.GO_SHORT,
                f"Discordant ({long_count}L/{short_count}S/{wait_count}W) — "
                f"DPL RED + AD {ad_65.ratio:.1f} + DOM {dom75.label}.{t100_note} "
                f"Enter near min-14 high. Breadth: {breadth.tick_label} / TRIN {breadth.trin:.2f}.",
                False, SignalDirection.SHORT,
            )

    # ── WAIT / REASSESS ───────────────────────────────────────────────────────
    t100_label = t100.inflection_label if t100.is_reached else f"T+100 in {t100.minutes_to_t100:.0f}m"
    return (
        TradeAction.WAIT_REASSESS,
        f"Mixed ({long_count}L/{short_count}S/{wait_count}W). "
        f"DPL={dpl.color.value.upper()} not confirmed by DOM ({dom75.label}). "
        f"{t100_label} | "
        f"TRIN {breadth.trin:.2f} | "
        f"VIX {vix.vix:.1f}. Monitor through S35 window.",
        False, None,
    )
