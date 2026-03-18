"""
NexusBot — signal-sheet-service
Cloud Run FastAPI service. All endpoints are invoked by Cloud Scheduler
using OIDC authentication.

Endpoints:
  POST /generate          → premarket snapshot
  POST /resolve           → opening algorithm decision
  POST /lock-minute14     → immutable minute-14 high/low lock
  POST /refresh           → live DPL refresh + optional WAIT upgrade
  POST /render-snapshot   → generate PNG artifact for a phase

Health:
  GET  /health            → unauthenticated liveness probe
"""
from __future__ import annotations

import logging
import os
import time as _time
from contextlib import asynccontextmanager
from datetime import date, datetime
from typing import Any, Dict, List, Optional

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from auth import require_replay_auth, require_scheduler_auth
from services.market_session import (
    market_date, is_trading_day, market_date_obj,
    session_bars_ready, phase_window_active,
)
from services.tradier_client import TradierClient
from services.playbook_writer import PlaybookWriter
from services.screenshot_renderer import ScreenshotRenderer
from services.signal_engine.algorithm_v2 import build_signal_sheet_v2
from services.signal_engine.signals import detect_gap, compute_dpl
from services.signal_engine.gex import compute_gex

logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO"))
logger = logging.getLogger(__name__)

SIGNAL_ENGINE_VERSION = "v2.0.0"
SYMBOL = "SPX"


# ─────────────────────────────────────────────────────────────────────────────
# App lifespan — open/close the shared Tradier connection pool
# ─────────────────────────────────────────────────────────────────────────────

tradier  = TradierClient()
writer   = PlaybookWriter()
renderer = ScreenshotRenderer()


@asynccontextmanager
async def lifespan(app: FastAPI):
    await tradier.start()
    logger.info("signal-sheet-service started (engine=%s)", SIGNAL_ENGINE_VERSION)
    yield
    await tradier.stop()
    logger.info("signal-sheet-service stopped")


app = FastAPI(title="NexusBot Signal Sheet Service", lifespan=lifespan)


# ─────────────────────────────────────────────────────────────────────────────
# Response helpers
# ─────────────────────────────────────────────────────────────────────────────

def ok(phase: str, outcome: str, date_str: str, **extra) -> Dict:
    return {"status": "ok", "date": date_str, "phase": phase, "outcome": outcome, **extra}


def noop(phase: str, date_str: str, reason: str = "") -> Dict:
    logger.info("noop phase=%s date=%s reason=%s", phase, date_str, reason)
    return {"status": "ok", "date": date_str, "phase": phase, "outcome": "noop", "reason": reason}


def _log_request(phase: str, market_dt: str, outcome: str, duration_ms: int,
                 recommendation: str = None, algorithm_step: int = None,
                 tradier_calls: int = 0, error_code: str = None):
    fields = {
        "phase": phase, "market_date": market_dt, "symbol": SYMBOL,
        "status": "ok" if not error_code else "error",
        "outcome": outcome, "duration_ms": duration_ms,
        "tradier_calls": tradier_calls,
        "recommendation": recommendation, "algorithm_step": algorithm_step,
    }
    if error_code:
        fields["error_code"] = error_code
    logger.info("request %s", fields)


# ─────────────────────────────────────────────────────────────────────────────
# GET /health
# ─────────────────────────────────────────────────────────────────────────────

@app.get("/health")
async def health():
    return {"status": "ok", "engine": SIGNAL_ENGINE_VERSION}


# ─────────────────────────────────────────────────────────────────────────────
# POST /generate  — premarket snapshot
# ─────────────────────────────────────────────────────────────────────────────

@app.post("/generate")
async def generate(request: Request):
    require_scheduler_auth(request)
    t0 = _time.monotonic()
    mdate = market_date()

    if not is_trading_day():
        return noop("generate", mdate, "not_a_trading_day")

    if not phase_window_active("generate"):
        return noop("generate", mdate, "outside_generate_window")

    try:
        snapshot = await tradier.fetch_market_snapshot(SYMBOL)
        sheet    = _build_sheet_from_snapshot(snapshot, mdate)

        await writer.write_premarket(
            market_date    = mdate,
            payload        = sheet,
            signal_version = SIGNAL_ENGINE_VERSION,
        )

        duration = int((_time.monotonic() - t0) * 1000)
        _log_request("generate", mdate, "updated", duration, tradier_calls=7)
        return ok("generate", "updated", mdate)

    except Exception as exc:
        logger.exception("generate failed: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc))


# ─────────────────────────────────────────────────────────────────────────────
# POST /resolve  — opening algorithm decision
# ─────────────────────────────────────────────────────────────────────────────

@app.post("/resolve")
async def resolve(request: Request):
    require_scheduler_auth(request)
    t0    = _time.monotonic()
    mdate = market_date()

    if not is_trading_day():
        return noop("resolve", mdate, "not_a_trading_day")

    if not await writer.exists(mdate):
        logger.warning("resolve called but no premarket document for %s", mdate)
        return noop("resolve", mdate, "missing_generate_phase")

    try:
        # Must use official 09:30 opening bar — not latest spot quote
        candles_1min = await tradier.get_intraday_candles("SPY", interval="1min")
        opening_bars = [c for c in candles_1min if c["time"].startswith(f"{mdate} 09:3")]
        if not opening_bars:
            return noop("resolve", mdate, "no_opening_bar_yet")

        official_open = float(opening_bars[0]["open"])

        playbook = await writer.get_playbook(mdate)
        yesterday_close = playbook["yesterday_close"]

        # Run algorithm resolution
        algo_step, recommendation, signal_unity, reason = _resolve_algorithm(
            official_open=official_open,
            yesterday_close=yesterday_close,
            signals=playbook["signals"],
            dpl_live=playbook.get("dpl_live"),
        )

        await writer.write_open_decision(
            market_date    = mdate,
            official_open  = official_open,
            algorithm_step = algo_step,
            recommendation = recommendation,
            signal_unity   = signal_unity,
            reason         = reason,
        )

        duration = int((_time.monotonic() - t0) * 1000)
        _log_request("resolve", mdate, "updated", duration,
                     recommendation=recommendation, algorithm_step=algo_step, tradier_calls=1)
        return ok("resolve", "updated", mdate,
                  recommendation=recommendation, algorithm_step=algo_step)

    except Exception as exc:
        logger.exception("resolve failed: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc))


# ─────────────────────────────────────────────────────────────────────────────
# POST /lock-minute14  — immutable minute-14 high/low
# ─────────────────────────────────────────────────────────────────────────────

@app.post("/lock-minute14")
async def lock_minute14(request: Request):
    require_scheduler_auth(request)
    t0    = _time.monotonic()
    mdate = market_date()

    if not is_trading_day():
        return noop("lock_minute14", mdate, "not_a_trading_day")

    if not session_bars_ready(14):
        return noop("lock_minute14", mdate, "fewer_than_14_bars")

    if not await writer.exists(mdate):
        return noop("lock_minute14", mdate, "missing_generate_phase")

    try:
        candles = await tradier.get_intraday_candles("SPY", interval="1min")

        # Bars 09:30 through 09:43 (first 14 completed bars)
        minute14_bars = [
            c for c in candles
            if _bar_in_window(c["time"], mdate, "09:30", "09:43")
        ]
        if len(minute14_bars) < 14:
            return noop("lock_minute14", mdate,
                        f"only_{len(minute14_bars)}_bars_available")

        min14_high = max(float(c["high"])  for c in minute14_bars)
        min14_low  = min(float(c["low"])   for c in minute14_bars)

        await writer.write_minute14_lock(mdate, min14_high, min14_low)

        duration = int((_time.monotonic() - t0) * 1000)
        _log_request("lock_minute14", mdate, "updated", duration, tradier_calls=1)
        return ok("lock_minute14", "updated", mdate,
                  min14_high=min14_high, min14_low=min14_low)

    except Exception as exc:
        logger.exception("lock_minute14 failed: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc))


# ─────────────────────────────────────────────────────────────────────────────
# POST /refresh  — live DPL refresh + optional WAIT upgrade
# ─────────────────────────────────────────────────────────────────────────────

@app.post("/refresh")
async def refresh(request: Request):
    require_scheduler_auth(request)
    t0    = _time.monotonic()
    mdate = market_date()

    if not is_trading_day():
        return noop("refresh", mdate, "not_a_trading_day")

    if not await writer.exists(mdate):
        return noop("refresh", mdate, "missing_generate_phase")

    try:
        candles_5min = await tradier.get_intraday_candles("SPY", interval="5min")
        spot_raw     = await tradier.get_quote("SPY")
        spot         = float(spot_raw["last"])

        # Recompute live DPL
        dpl_live = _compute_live_dpl(candles_5min, spot)

        # Live session extremes
        session_high = max((float(c["high"]) for c in candles_5min), default=None)
        session_low  = min((float(c["low"])  for c in candles_5min), default=None)

        # Check if a prior WAIT can be upgraded
        playbook    = await writer.get_playbook(mdate)
        upgrade_rec = None
        upgrade_reason = None
        upgrade_step = None

        if playbook.get("recommendation") == "WAIT" and _can_upgrade_wait(
            dpl_live=dpl_live,
            playbook=playbook,
            session_high=session_high,
            session_low=session_low,
        ):
            upgrade_rec, upgrade_reason, upgrade_step = _compute_upgrade(dpl_live, playbook)

        await writer.write_refresh(
            market_date       = mdate,
            dpl_live          = dpl_live,
            live_session_high = session_high,
            live_session_low  = session_low,
            recommendation    = upgrade_rec,
            reason            = upgrade_reason,
            algorithm_step    = upgrade_step,
        )

        duration = int((_time.monotonic() - t0) * 1000)
        _log_request("refresh", mdate, "updated", duration,
                     recommendation=upgrade_rec or playbook.get("recommendation"),
                     tradier_calls=2)
        return ok("refresh", "updated", mdate,
                  dpl_direction=dpl_live.get("direction"),
                  upgraded_to=upgrade_rec)

    except Exception as exc:
        logger.exception("refresh failed: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc))


# ─────────────────────────────────────────────────────────────────────────────
# POST /render-snapshot  — generate PNG artifact
# ─────────────────────────────────────────────────────────────────────────────

class RenderRequest(BaseModel):
    phase: str   # premarket | locked | final


@app.post("/render-snapshot")
async def render_snapshot(body: RenderRequest, request: Request):
    require_scheduler_auth(request)
    t0    = _time.monotonic()
    mdate = market_date()

    allowed_phases = {"premarket", "locked", "final"}
    if body.phase not in allowed_phases:
        raise HTTPException(status_code=400, detail=f"phase must be one of {allowed_phases}")

    if not is_trading_day():
        return noop("render_snapshot", mdate, "not_a_trading_day")

    playbook = await writer.get_playbook(mdate)
    if not playbook:
        return noop("render_snapshot", mdate, "no_playbook_yet")

    # Phase readiness checks
    if body.phase == "locked" and playbook.get("min14_high") is None:
        return noop("render_snapshot", mdate, "min14_not_locked_yet")
    if body.phase == "final" and playbook.get("last_refreshed_at") is None:
        return noop("render_snapshot", mdate, "refresh_not_run_yet")

    try:
        artifact = await renderer.render(
            phase    = body.phase,
            playbook = playbook,
            mdate    = mdate,
        )

        await writer.write_screenshot_metadata(
            market_date      = mdate,
            phase            = body.phase,
            storage_path     = artifact["storage_path"],
            public_url       = artifact.get("public_url"),
            width            = artifact["width"],
            height           = artifact["height"],
            template_version = artifact["template_version"],
        )

        duration = int((_time.monotonic() - t0) * 1000)
        logger.info("render phase=%s date=%s path=%s render_duration_ms=%d",
                    body.phase, mdate, artifact["storage_path"], duration)
        return ok("render_snapshot", "updated", mdate,
                  render_phase=body.phase, storage_path=artifact["storage_path"])

    except Exception as exc:
        logger.exception("render_snapshot failed (non-blocking): %s", exc)
        # Rendering failure must not block market-data endpoints (spec §14)
        return JSONResponse(
            status_code=200,
            content={"status": "error", "code": "render_failed",
                     "message": str(exc), "date": mdate, "phase": body.phase},
        )


# ─────────────────────────────────────────────────────────────────────────────
# POST /replay  — full pipeline replay for a historical trading date
# ─────────────────────────────────────────────────────────────────────────────

class ReplayRequest(BaseModel):
    date:  str            # YYYY-MM-DD target trading date
    force: bool = False   # if True, delete any existing replay doc and re-run


@app.post("/replay")
async def replay(body: ReplayRequest, request: Request):
    require_replay_auth(request)
    t0 = _time.monotonic()

    try:
        target_d = date.fromisoformat(body.date)
    except ValueError:
        raise HTTPException(status_code=400, detail="date must be YYYY-MM-DD")

    if not is_trading_day(target_d):
        raise HTTPException(status_code=400, detail=f"{body.date} is not a trading day")

    target_date = body.date
    doc_id      = target_date
    warnings: List[str] = []

    if body.force:
        await writer.delete_playbook(doc_id)
        logger.info("replay: deleted existing doc %s (force=True)", doc_id)

    # ── Phase 1: generate ────────────────────────────────────────────────────
    snapshot = await tradier.fetch_historical_snapshot(target_date)
    warnings.extend(snapshot.pop("_replay_caveats", []))

    if not snapshot["candles_1min"]:
        raise HTTPException(
            status_code=422,
            detail=f"No intraday 1-min data for {target_date} — date likely exceeds Tradier history depth",
        )

    sheet = _build_sheet_from_snapshot(snapshot, target_date)
    await writer.write_premarket(
        market_date    = doc_id,
        payload        = sheet,
        signal_version = SIGNAL_ENGINE_VERSION,
    )

    # ── Phase 2: resolve ─────────────────────────────────────────────────────
    candles_1min = snapshot["candles_1min"]
    logger.info("replay: candles_1min count=%d first=%s",
                len(candles_1min), candles_1min[0] if candles_1min else None)
    opening_bars = _find_opening_bars(candles_1min, target_date)
    if not opening_bars:
        raise HTTPException(status_code=422, detail=f"No opening bars found for {target_date}")

    official_open   = float(opening_bars[0]["open"])
    yesterday_close = sheet["yesterday_close"]

    algo_step, recommendation, signal_unity, reason = _resolve_algorithm(
        official_open   = official_open,
        yesterday_close = yesterday_close,
        signals         = sheet["signals"],
        dpl_live        = sheet.get("dpl_live"),
    )
    await writer.write_open_decision(
        market_date    = doc_id,
        official_open  = official_open,
        algorithm_step = algo_step,
        recommendation = recommendation,
        signal_unity   = signal_unity,
        reason         = reason,
    )

    # ── Phase 3: lock-minute14 ───────────────────────────────────────────────
    minute14_bars = [
        c for c in candles_1min
        if _bar_in_window(c["time"], target_date, "09:30", "09:43")
    ]
    if len(minute14_bars) < 14:
        warnings.append(f"only_{len(minute14_bars)}_bars_for_min14")
    min14_high = max((float(c["high"]) for c in minute14_bars), default=0.0)
    min14_low  = min((float(c["low"])  for c in minute14_bars), default=0.0)
    await writer.write_minute14_lock(doc_id, min14_high, min14_low)

    # ── Phase 4: refresh ─────────────────────────────────────────────────────
    candles_5min = snapshot["candles_5min"]
    last_bar = candles_5min[-1] if candles_5min else None
    spot     = float(last_bar["close"]) if last_bar else float(snapshot["spy_quote"]["last"])

    dpl_live     = _compute_live_dpl(candles_5min, spot)
    session_high = max((float(c["high"]) for c in candles_5min), default=None)
    session_low  = min((float(c["low"])  for c in candles_5min), default=None)

    playbook_mid    = await writer.get_playbook(doc_id)
    upgrade_rec     = upgrade_reason = upgrade_step = None
    if playbook_mid and playbook_mid.get("recommendation") == "WAIT" and _can_upgrade_wait(
        dpl_live=dpl_live, playbook=playbook_mid,
        session_high=session_high, session_low=session_low,
    ):
        upgrade_rec, upgrade_reason, upgrade_step = _compute_upgrade(dpl_live, playbook_mid)

    await writer.write_refresh(
        market_date       = doc_id,
        dpl_live          = dpl_live,
        live_session_high = session_high,
        live_session_low  = session_low,
        recommendation    = upgrade_rec,
        reason            = upgrade_reason,
        algorithm_step    = upgrade_step,
    )

    # ── Phase 5: render-snapshot (final) ─────────────────────────────────────
    final_playbook = await writer.get_playbook(doc_id)
    gcs_path = None
    try:
        artifact = await renderer.render(
            phase    = "final",
            playbook = final_playbook,
            mdate    = target_date,
        )
        await writer.write_screenshot_metadata(
            market_date      = doc_id,
            phase            = "final",
            storage_path     = artifact["storage_path"],
            public_url       = artifact.get("public_url"),
            width            = artifact["width"],
            height           = artifact["height"],
            template_version = artifact["template_version"],
        )
        gcs_path = artifact["storage_path"]
    except Exception as exc:
        logger.warning("replay render failed (non-blocking): %s", exc)
        warnings.append(f"render_failed: {exc}")

    final_playbook = await writer.get_playbook(doc_id)
    duration = int((_time.monotonic() - t0) * 1000)
    logger.info("replay complete date=%s doc=%s rec=%s duration_ms=%d",
                target_date, doc_id, final_playbook.get("recommendation"), duration)

    return {
        "status":         "ok",
        "target_date":    target_date,
        "doc_id":         doc_id,
        "phases_run":     ["generate", "resolve", "lock-minute14", "refresh", "render-snapshot"],
        "recommendation": final_playbook.get("recommendation"),
        "algorithm_step": final_playbook.get("algorithm_step"),
        "official_open":  final_playbook.get("official_open"),
        "min14_high":     final_playbook.get("min14_high"),
        "min14_low":      final_playbook.get("min14_low"),
        "dpl_direction":  (final_playbook.get("dpl_live") or {}).get("direction"),
        "gcs_path":       gcs_path,
        "duration_ms":    duration,
        "warnings":       warnings,
    }


# ─────────────────────────────────────────────────────────────────────────────
# Internal helpers
# ─────────────────────────────────────────────────────────────────────────────

def _build_sheet_from_snapshot(snapshot: Dict, mdate: str) -> Dict:
    """
    Convert a raw Tradier snapshot dict into the playbook payload shape.
    Delegates to the signal engine for all computations.
    """
    from services.signal_engine.gex import compute_gex
    from services.signal_engine.signals import (
        detect_gap, compute_dpl, compute_spy_component,
        compute_itod, compute_optimized_tod, compute_tod_gap,
        compute_ad_65, compute_dom_gap,
    )
    from services.signal_engine.vix import compute_vix
    from services.signal_engine.breadth import compute_breadth
    from services.signal_engine.models import Quote, Candle
    from datetime import datetime as _dt

    spy_raw   = snapshot["spy_quote"]
    vix_raw   = snapshot["vix_quotes"]
    breadth_q = snapshot["breadth_quotes"]
    chain_raw = snapshot["options_chain"]
    c5_raw    = snapshot["candles_5min"]

    spot = float(spy_raw.get("last") or spy_raw.get("close") or 0)
    prev = float(spy_raw.get("prevclose") or spot)

    # GEX
    from services.signal_engine.models import OptionContract
    contracts = _raw_to_contracts(chain_raw, spot)
    from services.signal_engine.gex import compute_gex as _compute_gex
    gex = _compute_gex(contracts, spot)

    # Signals
    gap = detect_gap(float(spy_raw.get("open") or spot), prev)

    spy_quote_obj = _make_quote(spy_raw)
    spy_comp = compute_spy_component(spy_quote_obj)

    candles_5 = _raw_to_candles(c5_raw)
    dpl = compute_dpl(candles_5, spot)

    now = datetime.utcnow()
    itod     = compute_itod(now, spy_comp)
    opt_tod  = compute_optimized_tod(itod, candles_5, gap)
    tod_gap  = compute_tod_gap(opt_tod, gap, now)

    # Breadth
    bq = {sym: {"last": float(q.get("last") or 0),
                "prev_close": float(q.get("prevclose") or 0),
                "volume": int(q.get("volume") or 0)}
          for sym, q in breadth_q.items()}
    breadth = compute_breadth(bq)
    ad_65   = compute_ad_65(breadth.advances, breadth.declines)
    dom_gap_sig = compute_dom_gap(candles_5, gap)

    # VIX
    vix_q   = vix_raw.get("VIX", {})
    vix3m_q = vix_raw.get("VIX3M")
    vvix_q  = vix_raw.get("VVIX")
    vix_res = compute_vix(
        vix_last   = float(vix_q.get("last") or 20),
        vix_prev   = float(vix_q.get("prevclose") or 20),
        spx_spot   = spot * 10,
        spx_prev   = prev * 10,
        vix3m_last = float(vix3m_q["last"]) if vix3m_q else None,
        vvix_last  = float(vvix_q["last"])  if vvix_q  else None,
    )

    from services.signal_engine.algorithm import _run_algorithm, _dpl_to_direction
    from services.signal_engine.models import DPLColor, DPLResult as DPLModel
    dpl_dir = _dpl_to_direction(dpl)

    return {
        "source_symbol":   "SPY",
        "source_mode":     "proxy",
        "yesterday_close": prev * 10,   # SPX ≈ 10× SPY
        "premarket_price": spot * 10,
        "premarket_bias":  spy_comp.value,

        "net_gex":      gex.net_gex_billions,
        "flip_level":   gex.flip_point,
        "gamma_wall":   gex.wall_vs_rally or 0,
        "put_wall":     gex.wall_vs_drop  or 0,
        "regime":       gex.regime.value,
        "wall_rally": [{"strike": gex.wall_vs_rally, "gex_millions": gex.wall_vs_rally_gex}] if gex.wall_vs_rally else [],
        "wall_drop":  [{"strike": gex.wall_vs_drop,  "gex_millions": gex.wall_vs_drop_gex}]  if gex.wall_vs_drop  else [],
        "spx_range_est": gex.range_estimate_pts,

        "signals": {
            "spy_component":  {"bias": spy_comp.value, "value": spot * 10, "confidence": 0.8},
            "iToD":           {"bias": itod.value,     "value": 0,         "confidence": 0.6},
            "optimized_tod":  {"bias": opt_tod.value,  "value": 0,         "confidence": 0.6},
            "tod_gap":        {"bias": tod_gap.value,  "value": gap.gap_points, "confidence": 0.7},
            "dpl": {
                "direction":    dpl_dir.value,
                "color":        dpl.color.value,
                "separation":   dpl.separation,
                "is_expanding": dpl.breakup or dpl.breakdown,
            },
            "ad_6_5": {
                "ratio":         ad_65.ratio,
                "bias":          ad_65.direction.value,
                "participation": breadth.breadth_label.value,
            },
            "dom_gap": {"bias": dom_gap_sig.value, "value": 0, "confidence": 0.5},
        },

        "dpl_live": {
            "direction":    dpl_dir.value,
            "color":        dpl.color.value,
            "separation":   dpl.separation,
            "is_expanding": False,
        },

        # VIX context (extra fields)
        "vix":              vix_res.vix,
        "vix_regime":       vix_res.regime.value,
        "vix_range_1sd":    vix_res.daily_range_1sd,
        "position_size_mult": vix_res.position_size_mult,
    }


def _resolve_algorithm(
    official_open:  float,
    yesterday_close: float,
    signals:        Dict,
    dpl_live:       Optional[Dict],
) -> tuple:
    """Returns (algorithm_step, recommendation, signal_unity, reason)."""
    gap_points = abs(official_open - yesterday_close)

    # Step 1: significant gap (> 5 SPX points)
    if gap_points > 5:
        return (1, "WAIT",
                False,
                f"Gap day ({gap_points:.1f} pts). Wait for post-open DPL confirmation.")

    # Collect signal biases
    biases = [v["bias"] if isinstance(v, dict) else v
              for v in signals.values()]

    bulls  = sum(1 for b in biases if "bullish" in str(b).lower() or "long" in str(b).lower())
    bears  = sum(1 for b in biases if "bearish" in str(b).lower() or "short" in str(b).lower())
    total  = len(biases)

    # Step 2: all unified
    if bulls == total:
        return (2, "GO_LONG",  True,  "All 7 signals unified bullish.")
    if bears == total:
        return (2, "GO_SHORT", True,  "All 7 signals unified bearish.")

    # Step 3: DPL tiebreaker
    dpl_direction = (dpl_live or {}).get("direction", "NEUTRAL")
    if dpl_direction == "long":
        return (3, "GO_LONG",  False, f"Mixed signals ({bulls}B/{bears}S). DPL LONG tiebreaker.")
    if dpl_direction == "short":
        return (3, "GO_SHORT", False, f"Mixed signals ({bulls}B/{bears}S). DPL SHORT tiebreaker.")
    return (3, "WAIT", False,
            f"Mixed signals ({bulls}B/{bears}S). DPL neutral — wait for confirmation.")


def _compute_live_dpl(candles_5min_raw: list, spot: float) -> Dict:
    from services.signal_engine.signals import compute_dpl
    candles = _raw_to_candles(candles_5min_raw)
    dpl = compute_dpl(candles, spot)
    from services.signal_engine.algorithm import _dpl_to_direction
    return {
        "direction":    _dpl_to_direction(dpl).value,
        "color":        dpl.color.value,
        "separation":   dpl.separation,
        "is_expanding": dpl.breakup or dpl.breakdown,
    }


def _can_upgrade_wait(dpl_live: Dict, playbook: Dict,
                      session_high: float, session_low: float) -> bool:
    """True when DPL has formed a clear direction and gap (if any) has resolved."""
    return dpl_live.get("direction") in ("long", "short") and \
           abs(dpl_live.get("separation", 0)) > 0.05


def _compute_upgrade(dpl_live: Dict, playbook: Dict) -> tuple:
    direction = dpl_live["direction"]
    if direction == "long":
        return ("GO_LONG",  "WAIT upgraded: DPL confirmed LONG after open window.", 3)
    return ("GO_SHORT", "WAIT upgraded: DPL confirmed SHORT after open window.", 3)


def _find_opening_bars(candles: list, target_date: str) -> list:
    """
    Return bars at the 09:30 open for target_date.
    Handles both 'YYYY-MM-DD HH:MM:SS' and 'YYYY-MM-DDTHH:MM:SS' formats,
    and Unix epoch timestamps.
    """
    results = []
    for c in candles:
        t = c.get("time", "")
        # Normalise: replace T separator and strip seconds
        normalised = str(t).replace("T", " ")[:16]   # → "YYYY-MM-DD HH:MM"
        if normalised.startswith(f"{target_date} 09:3"):
            results.append(c)
    return results


def _bar_in_window(time_str: str, mdate: str, start: str, end: str) -> bool:
    try:
        normalised = str(time_str).replace("T", " ")
        bar_time   = normalised.split(" ")[1][:5]   # HH:MM
        return start <= bar_time <= end
    except Exception:
        return False


def _raw_to_candles(raw: list):
    from services.signal_engine.models import Candle
    candles = []
    for c in (raw or []):
        try:
            candles.append(Candle(
                timestamp=datetime.fromisoformat(c["time"]),
                open=float(c["open"]), high=float(c["high"]),
                low=float(c["low"]),   close=float(c["close"]),
                volume=int(c["volume"]),
            ))
        except Exception:
            pass
    return candles


def _raw_to_contracts(raw: list, spot: float):
    from services.signal_engine.models import OptionContract
    contracts = []
    for o in (raw or []):
        try:
            g = o.get("greeks") or {}
            contracts.append(OptionContract(
                symbol=o["symbol"], underlying=o["underlying"],
                strike=float(o["strike"]), expiration=o["expiration_date"],
                option_type=o["option_type"],
                bid=float(o.get("bid") or 0), ask=float(o.get("ask") or 0),
                last=float(o.get("last") or 0),
                volume=int(o.get("volume") or 0),
                open_interest=int(o.get("open_interest") or 0),
                iv=float(g.get("smv_vol") or 0),
                delta=float(g.get("delta") or 0), gamma=float(g.get("gamma") or 0),
                theta=float(g.get("theta") or 0), vega=float(g.get("vega") or 0),
            ))
        except Exception:
            pass
    return contracts


def _make_quote(raw: Dict):
    from services.signal_engine.models import Quote
    return Quote(
        symbol=raw.get("symbol", ""),
        bid=float(raw.get("bid") or 0), ask=float(raw.get("ask") or 0),
        last=float(raw.get("last") or raw.get("close") or 0),
        volume=int(raw.get("volume") or 0),
        open=float(raw["open"]) if raw.get("open") else None,
        prev_close=float(raw.get("prevclose") or 0),
        timestamp=datetime.utcnow(),
    )
