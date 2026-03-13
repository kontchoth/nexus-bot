"""NexusBot signal-sheet Cloud Run service."""

from __future__ import annotations

import asyncio
import os
from typing import Literal

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from services.gex_service import GEXService
from services.market_session import get_session_context, is_after, utcnow_iso
from services.playbook_writer import PlaybookWriter
from services.render_service import PHASES, RenderService
from services.signal_engine import SignalEngine
from services.storage_service import ArtifactStorage
from services.tradier_client import TradierClient

TRADIER_KEY = os.environ["TRADIER_API_KEY"]
SYMBOL = os.environ.get("SIGNAL_SYMBOL", "SPX")
SANDBOX = os.environ.get("ENVIRONMENT", "production") != "production"
SIGNAL_ENGINE_VERSION = os.environ.get("SIGNAL_ENGINE_VERSION", "v1")
SCHEMA_VERSION = int(os.environ.get("SIGNAL_SHEET_SCHEMA_VERSION", "2"))
OIDC_AUDIENCE = os.environ.get("OIDC_AUDIENCE", "").strip()
ALLOWED_SCHEDULER_EMAIL = os.environ.get("SCHEDULER_SERVICE_ACCOUNT_EMAIL", "").strip()

app = FastAPI(title="NexusBot Signal Sheet Service", version="1.1.0")


class RenderSnapshotRequest(BaseModel):
    phase: Literal["premarket", "locked", "final"]


async def verify_oidc(request: Request):
    """Verify the caller is the expected Cloud Scheduler principal."""
    auth_header = request.headers.get("Authorization", "")
    if not auth_header.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="missing_oidc_token")

    token = auth_header.split(" ", 1)[1]
    try:
        from google.auth.transport import requests as google_requests
        from google.oauth2 import id_token

        claims = id_token.verify_oauth2_token(
            token,
            google_requests.Request(),
            audience=OIDC_AUDIENCE or None,
        )
    except Exception as exc:
        raise HTTPException(status_code=401, detail=f"invalid_oidc_token: {exc}") from exc

    issuer = claims.get("iss", "")
    if issuer not in {"accounts.google.com", "https://accounts.google.com"}:
        raise HTTPException(status_code=401, detail="invalid_oidc_issuer")

    if OIDC_AUDIENCE and claims.get("aud") != OIDC_AUDIENCE:
        raise HTTPException(status_code=401, detail="invalid_oidc_audience")

    if ALLOWED_SCHEDULER_EMAIL and claims.get("email") != ALLOWED_SCHEDULER_EMAIL:
        raise HTTPException(status_code=403, detail="unauthorized_scheduler_email")

    return claims


def _ok(date_value: str, phase: str, outcome: str, **extra) -> dict:
    payload = {
        "status": "ok",
        "date": date_value,
        "phase": phase,
        "outcome": outcome,
    }
    payload.update(extra)
    return payload


def _noop(date_value: str, phase: str, reason: str, **extra) -> dict:
    return _ok(date_value, phase, "noop", reason=reason, **extra)


def _error_response(code: str, message: str, *, status_code: int = 500) -> JSONResponse:
    return JSONResponse(
        status_code=status_code,
        content={"status": "error", "code": code, "message": message},
    )


def _resolve_algorithm(signals: dict, yesterday_close: float, official_open: float) -> dict:
    gap = abs(official_open - yesterday_close) if yesterday_close > 0 else 0
    if gap > 5:
        return {
            "official_open": official_open,
            "algorithm_step": 1,
            "recommendation": "WAIT",
            "signal_unity": False,
            "reason": f"Gap of {gap:.1f}pts detected - wait for DPL confirmation",
        }

    biases = []
    for key, signal in signals.items():
        if key == "dpl":
            direction = signal.get("direction")
            if direction == "LONG":
                biases.append("bullish")
            elif direction == "SHORT":
                biases.append("bearish")
            else:
                biases.append("neutral")
            continue
        biases.append(signal.get("bias", "neutral"))

    if all(value == "bullish" for value in biases):
        return {
            "official_open": official_open,
            "algorithm_step": 2,
            "recommendation": "GO_LONG",
            "signal_unity": True,
            "reason": "All 7 signals unified bullish",
        }
    if all(value == "bearish" for value in biases):
        return {
            "official_open": official_open,
            "algorithm_step": 2,
            "recommendation": "GO_SHORT",
            "signal_unity": True,
            "reason": "All 7 signals unified bearish",
        }

    dpl_direction = (signals.get("dpl") or {}).get("direction", "NEUTRAL")
    recommendation = "WAIT"
    if dpl_direction == "LONG":
        recommendation = "GO_LONG"
    elif dpl_direction == "SHORT":
        recommendation = "GO_SHORT"

    return {
        "official_open": official_open,
        "algorithm_step": 3,
        "recommendation": recommendation,
        "signal_unity": False,
        "reason": f"Discordant signals - DPL tiebreaker: {dpl_direction}",
    }


def _extract_official_open(bars: list[dict]) -> float | None:
    if not bars:
        return None
    first_bar = bars[0]
    open_value = first_bar.get("open")
    if open_value is None:
        open_value = first_bar.get("close") or first_bar.get("price")
    try:
        return float(open_value)
    except (TypeError, ValueError):
        return None


def _first_fourteen_bars(bars: list[dict]) -> list[dict]:
    valid = [bar for bar in bars if bar.get("high") is not None or bar.get("low") is not None or bar.get("close") is not None]
    return valid[:14]


def _maybe_promote_wait(playbook: dict, dpl_live: dict) -> dict:
    if playbook.get("recommendation") != "WAIT":
        return {}
    if playbook.get("min14_high") is None or playbook.get("min14_low") is None:
        return {}

    direction = dpl_live.get("direction")
    if direction == "LONG":
        return {
            "recommendation": "GO_LONG",
            "reason": "Live DPL confirmation after minute-14 lock: LONG",
        }
    if direction == "SHORT":
        return {
            "recommendation": "GO_SHORT",
            "reason": "Live DPL confirmation after minute-14 lock: SHORT",
        }
    return {}


def _build_playbook(
    *,
    market_date: str,
    gex_data: dict,
    walls: dict,
    range_est: float,
    signals: dict,
    premarket: dict,
    yesterday_close: float,
) -> dict:
    source_mode = "direct" if SYMBOL == "SPX" else "proxy"
    return {
        "date": market_date,
        "symbol": "SPX",
        "source_symbol": SYMBOL,
        "source_mode": source_mode,
        "schema_version": SCHEMA_VERSION,
        "signal_engine_version": SIGNAL_ENGINE_VERSION,
        "generated_at": utcnow_iso(),
        "last_refreshed_at": None,
        "status": "premarket",
        "yesterday_close": yesterday_close,
        "official_open": None,
        "net_gex": gex_data["net_gex"],
        "flip_level": gex_data["flip_level"],
        "gamma_wall": gex_data["gamma_wall"],
        "put_wall": gex_data["put_wall"],
        "regime": gex_data["regime"],
        "wall_rally": walls["rally"],
        "wall_drop": walls["drop"],
        "spx_range_est": range_est,
        "premarket_bias": premarket["bias"],
        "premarket_price": premarket["price"],
        "signals": signals,
        "algorithm_step": None,
        "recommendation": None,
        "signal_unity": None,
        "reason": None,
        "min14_high": None,
        "min14_low": None,
        "otm_long_strike": None,
        "otm_short_strike": None,
        "dpl_live": signals.get("dpl"),
        "live_session_high": None,
        "live_session_low": None,
        "screenshots": {},
    }


@app.post("/generate", dependencies=[Depends(verify_oidc)])
async def generate_sheet():
    session = get_session_context()
    if not session.is_trading_day:
        return _noop(session.market_date, "generate", "non_trading_day")

    try:
        async with TradierClient(TRADIER_KEY, sandbox=SANDBOX) as client:
            gex_service = GEXService(client=client)
            signal_engine = SignalEngine(client=client)
            writer = PlaybookWriter()

            spot_task = gex_service.get_spot_price(SYMBOL)
            gex_task = gex_service.calculate_gex(SYMBOL, as_of_date=session.market_day)
            walls_task = gex_service.get_options_walls(SYMBOL, as_of_date=session.market_day)
            range_task = gex_service.estimate_daily_range(SYMBOL, as_of_date=session.market_day)
            signals_task = signal_engine.compute_all_7_signals(
                SYMBOL,
                market_date=session.market_date,
                as_of_date=session.market_day,
                now=session.now_et,
            )
            premarket_task = gex_service.get_premarket_bias(SYMBOL)
            yesterday_task = gex_service.get_yesterday_close(SYMBOL)

            _, gex_data, walls, range_est, signals, premarket, yesterday_close = await asyncio.gather(
                spot_task,
                gex_task,
                walls_task,
                range_task,
                signals_task,
                premarket_task,
                yesterday_task,
            )

            playbook = _build_playbook(
                market_date=session.market_date,
                gex_data=gex_data,
                walls=walls,
                range_est=range_est,
                signals=signals,
                premarket=premarket,
                yesterday_close=yesterday_close,
            )
            await writer.write(playbook)
            return _ok(session.market_date, "generate", "updated")
    except Exception as exc:
        return _error_response("generate_failed", str(exc))


@app.post("/resolve", dependencies=[Depends(verify_oidc)])
async def resolve():
    session = get_session_context()
    if not session.is_trading_day:
        return _noop(session.market_date, "resolve", "non_trading_day")

    try:
        writer = PlaybookWriter()
        playbook = await writer.get(session.market_date)
        if playbook is None:
            return _noop(session.market_date, "resolve", "missing_generate_phase")

        async with TradierClient(TRADIER_KEY, sandbox=SANDBOX) as client:
            bars = await client.get_intraday_bars(SYMBOL, session.market_date, interval="1min")

        official_open = _extract_official_open(bars)
        if official_open is None:
            return _noop(session.market_date, "resolve", "opening_bar_not_available")

        result = _resolve_algorithm(
            playbook["signals"],
            float(playbook.get("yesterday_close") or 0),
            official_open,
        )
        result["status"] = "open"
        result["last_refreshed_at"] = utcnow_iso()
        await writer.upsert(session.market_date, result)
        return _ok(
            session.market_date,
            "resolve",
            "updated",
            recommendation=result["recommendation"],
        )
    except Exception as exc:
        return _error_response("resolve_failed", str(exc))


@app.post("/lock-minute14", dependencies=[Depends(verify_oidc)])
async def lock_minute14():
    session = get_session_context()
    if not session.is_trading_day:
        return _noop(session.market_date, "lock-minute14", "non_trading_day")

    try:
        writer = PlaybookWriter()
        playbook = await writer.get(session.market_date)
        if playbook is None:
            return _noop(session.market_date, "lock-minute14", "missing_generate_phase")
        if playbook.get("min14_high") is not None and playbook.get("min14_low") is not None:
            return _noop(session.market_date, "lock-minute14", "minute14_already_locked")

        async with TradierClient(TRADIER_KEY, sandbox=SANDBOX) as client:
            bars = await client.get_intraday_bars(SYMBOL, session.market_date, interval="1min")

        first_fourteen = _first_fourteen_bars(bars)
        if len(first_fourteen) < 14:
            return _noop(session.market_date, "lock-minute14", "insufficient_open_bars")

        min14_high = max(float(bar.get("high") or bar.get("close") or 0) for bar in first_fourteen)
        min14_low = min(float(bar.get("low") or bar.get("close") or 0) for bar in first_fourteen)
        fields = {
            "min14_high": min14_high,
            "min14_low": min14_low,
            "otm_long_strike": round(min14_low - 50, 2),
            "otm_short_strike": round(min14_high + 50, 2),
            "status": "locked",
            "last_refreshed_at": utcnow_iso(),
        }
        await writer.upsert(session.market_date, fields)
        return _ok(
            session.market_date,
            "lock-minute14",
            "updated",
            min14_high=min14_high,
            min14_low=min14_low,
        )
    except Exception as exc:
        return _error_response("lock_minute14_failed", str(exc))


@app.post("/refresh", dependencies=[Depends(verify_oidc)])
async def refresh():
    session = get_session_context()
    if not session.is_trading_day:
        return _noop(session.market_date, "refresh", "non_trading_day")

    try:
        writer = PlaybookWriter()
        playbook = await writer.get(session.market_date)
        if playbook is None:
            return _noop(session.market_date, "refresh", "missing_generate_phase")

        async with TradierClient(TRADIER_KEY, sandbox=SANDBOX) as client:
            signal_engine = SignalEngine(client=client)
            bars_task = client.get_intraday_bars(SYMBOL, session.market_date, interval="1min")
            dpl_task = signal_engine.compute_dpl_live(SYMBOL, market_date=session.market_date)
            bars, dpl_live = await asyncio.gather(bars_task, dpl_task)

        if not bars:
            return _noop(session.market_date, "refresh", "intraday_bars_unavailable")

        live_updates = {
            "dpl_live": dpl_live,
            "last_refreshed_at": utcnow_iso(),
            "live_session_high": max(float(bar.get("high") or bar.get("close") or 0) for bar in bars),
            "live_session_low": min(float(bar.get("low") or bar.get("close") or 0) for bar in bars),
        }
        live_updates.update(_maybe_promote_wait(playbook, dpl_live))
        await writer.upsert(session.market_date, live_updates)
        return _ok(
            session.market_date,
            "refresh",
            "updated",
            recommendation=live_updates.get("recommendation"),
        )
    except Exception as exc:
        return _error_response("refresh_failed", str(exc))


@app.post("/render-snapshot", dependencies=[Depends(verify_oidc)])
async def render_snapshot(payload: RenderSnapshotRequest):
    session = get_session_context()
    if not session.is_trading_day:
        return _noop(session.market_date, "render-snapshot", "non_trading_day", render_phase=payload.phase)

    try:
        writer = PlaybookWriter()
        playbook = await writer.get(session.market_date)
        if playbook is None:
            return _noop(session.market_date, "render-snapshot", "missing_generate_phase", render_phase=payload.phase)

        render_service = RenderService()
        ready, reason = render_service.phase_readiness(playbook, payload.phase)
        if not ready:
            return _noop(session.market_date, "render-snapshot", reason or "phase_not_ready", render_phase=payload.phase)

        render_result = render_service.render(playbook, payload.phase)
        storage = ArtifactStorage()
        artifact = storage.write_png(session.market_date, payload.phase, render_result.image_bytes)

        screenshots = dict(playbook.get("screenshots") or {})
        screenshots[payload.phase] = {
            "phase": payload.phase,
            "generated_at": utcnow_iso(),
            "storage_path": artifact.storage_path,
            "public_url": artifact.public_url,
            "width": render_result.width,
            "height": render_result.height,
            "template_version": render_result.template_version,
        }
        await writer.upsert(session.market_date, {"screenshots": screenshots})
        return _ok(
            session.market_date,
            "render-snapshot",
            "updated",
            render_phase=payload.phase,
            storage_path=artifact.storage_path,
        )
    except Exception as exc:
        return _error_response("render_snapshot_failed", str(exc))


@app.get("/health")
async def health():
    session = get_session_context()
    return {
        "status": "healthy",
        "service": "signal-sheet-service",
        "market_date": session.market_date,
        "trading_day": session.is_trading_day,
        "render_phases": sorted(PHASES),
        "after_open": is_after(session, 9, 30),
    }
