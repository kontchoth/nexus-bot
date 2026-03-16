"""
NexusBot — Tradier Client (pooled, async)
Replaces the per-call httpx.AsyncClient() pattern in the existing scaffold.

Changes vs original scaffold:
  - single shared AsyncClient with connection pool (lifespan-managed)
  - explicit per-call timeouts
  - bounded retries with exponential backoff for 429 / 5xx
  - structured latency logging
  - all methods are async

Usage:
    # In main.py lifespan:
    tradier = TradierClient()
    await tradier.start()
    ...
    await tradier.stop()

    # In a handler:
    quote  = await tradier.get_quote("SPX")
    chain  = await tradier.get_options_chain("SPXW")
"""
from __future__ import annotations

import asyncio
import logging
import os
import time as _time
from datetime import date, datetime, timedelta
from typing import Any, Dict, List, Optional

import httpx

logger = logging.getLogger(__name__)

TRADIER_BASE = "https://api.tradier.com/v1"

_DEFAULT_TIMEOUT  = httpx.Timeout(10.0, connect=5.0)
_RETRY_STATUSES   = {429, 500, 502, 503, 504}
_MAX_RETRIES      = 3
_BACKOFF_BASE     = 0.5   # seconds


def _token() -> str:
    t = os.environ.get("TRADIER_API_KEY") or os.environ.get("TRADIER_TOKEN")
    if not t:
        raise EnvironmentError("TRADIER_API_KEY environment variable not set")
    return t


class TradierClient:
    """Async Tradier client with a single shared connection pool."""

    def __init__(self, token: Optional[str] = None):
        self._token   = token or _token()
        self._client: Optional[httpx.AsyncClient] = None

    async def start(self) -> None:
        """Open the connection pool. Call once at app startup."""
        self._client = httpx.AsyncClient(
            base_url=TRADIER_BASE,
            headers={
                "Authorization": f"Bearer {self._token}",
                "Accept":        "application/json",
            },
            timeout=_DEFAULT_TIMEOUT,
            limits=httpx.Limits(max_connections=10, max_keepalive_connections=5),
        )
        logger.info("TradierClient pool opened")

    async def stop(self) -> None:
        """Close the connection pool. Call once at app shutdown."""
        if self._client:
            await self._client.aclose()
            logger.info("TradierClient pool closed")

    # ─────────────────────────────────────────────────────────────────────────
    # Internal
    # ─────────────────────────────────────────────────────────────────────────

    async def _get(self, path: str, params: Dict = None) -> Dict:
        if not self._client:
            raise RuntimeError("TradierClient not started — call await start() first")
        t0 = _time.monotonic()
        last_exc: Exception | None = None
        for attempt in range(_MAX_RETRIES):
            try:
                resp = await self._client.get(path, params=params)
                latency_ms = int((_time.monotonic() - t0) * 1000)
                if resp.status_code in _RETRY_STATUSES:
                    wait = _BACKOFF_BASE * (2 ** attempt)
                    logger.warning("Tradier %s → %d, retry %d in %.1fs",
                                   path, resp.status_code, attempt + 1, wait)
                    await asyncio.sleep(wait)
                    continue
                resp.raise_for_status()
                logger.debug("tradier %s %dms", path, latency_ms)
                return resp.json()
            except httpx.TransportError as exc:
                last_exc = exc
                wait = _BACKOFF_BASE * (2 ** attempt)
                logger.warning("Tradier transport error attempt %d: %s", attempt + 1, exc)
                await asyncio.sleep(wait)
        raise RuntimeError(f"Tradier request failed after {_MAX_RETRIES} attempts") from last_exc

    # ─────────────────────────────────────────────────────────────────────────
    # Market clock
    # ─────────────────────────────────────────────────────────────────────────

    async def market_status(self) -> Dict:
        data = await self._get("/markets/clock")
        return data.get("clock", {})

    # ─────────────────────────────────────────────────────────────────────────
    # Quotes
    # ─────────────────────────────────────────────────────────────────────────

    async def get_quote(self, symbol: str) -> Dict:
        data = await self._get("/markets/quotes", {"symbols": symbol, "greeks": "false"})
        return data["quotes"]["quote"]

    async def get_quotes(self, symbols: List[str]) -> Dict[str, Dict]:
        data = await self._get("/markets/quotes", {
            "symbols": ",".join(symbols),
            "greeks": "false",
        })
        raw = data["quotes"]["quote"]
        if isinstance(raw, dict):
            raw = [raw]
        return {q["symbol"]: q for q in raw}

    # ─────────────────────────────────────────────────────────────────────────
    # Candles
    # ─────────────────────────────────────────────────────────────────────────

    async def get_intraday_candles(
        self,
        symbol:   str,
        interval: str = "1min",
        start:    Optional[str] = None,
        end:      Optional[str] = None,
    ) -> List[Dict]:
        today = date.today().isoformat()
        params = {
            "symbol":         symbol,
            "interval":       interval,
            "start":          start or f"{today} 09:29",
            "end":            end   or f"{today} 16:01",
            "session_filter": "open",
        }
        try:
            data = await self._get("/markets/timesales", params)
        except httpx.HTTPStatusError as exc:
            if exc.response.status_code == 400:
                logger.warning("timesales 400 for %s/%s — no market data (market closed?)", symbol, interval)
                return []
            raise
        series = data.get("series") or {}
        candles = series.get("data") or []
        if isinstance(candles, dict):
            candles = [candles]
        return candles

    async def get_daily_candles(self, symbol: str, lookback: int = 30) -> List[Dict]:
        end_d   = date.today()
        start_d = end_d - timedelta(days=lookback * 2)
        data = await self._get("/markets/history", {
            "symbol":   symbol,
            "interval": "daily",
            "start":    start_d.isoformat(),
            "end":      end_d.isoformat(),
        })
        history = data.get("history") or {}
        days    = history.get("day") or []
        if isinstance(days, dict):
            days = [days]
        return days[-lookback:]

    # ─────────────────────────────────────────────────────────────────────────
    # Options chain
    # ─────────────────────────────────────────────────────────────────────────

    async def get_options_expirations(self, symbol: str) -> List[str]:
        data = await self._get("/markets/options/expirations", {
            "symbol":           symbol,
            "includeAllRoots":  "true",
        })
        exps = data.get("expirations", {}).get("date") or []
        return exps if isinstance(exps, list) else [exps]

    async def get_options_chain(
        self,
        symbol:     str,
        expiration: Optional[str] = None,
    ) -> List[Dict]:
        if not expiration:
            exps   = await self.get_options_expirations(symbol)
            today  = date.today().isoformat()
            expiration = exps[0]
            for e in exps:
                if e >= today:
                    expiration = e
                    break

        data    = await self._get("/markets/options/chains", {
            "symbol":     symbol,
            "expiration": expiration,
            "greeks":     "true",
        })
        options = data.get("options", {}).get("option") or []
        if isinstance(options, dict):
            options = [options]
        return options

    # ─────────────────────────────────────────────────────────────────────────
    # Shared market snapshot (call once per handler — avoid re-fetching)
    # ─────────────────────────────────────────────────────────────────────────

    async def fetch_market_snapshot(self, symbol: str = "SPX") -> Dict[str, Any]:
        """
        Single coordinated fetch for all data needed by /generate.
        Returns a dict with all raw data — pass this to calculators.
        """
        spy_sym   = "SPY" if symbol == "SPX" else symbol

        # Run independent fetches concurrently
        (
            quote,
            spy_quote,
            chain,
            intraday_1min,
            intraday_5min,
            vix_quotes,
            breadth_quotes,
        ) = await asyncio.gather(
            self.get_quote(symbol),
            self.get_quote(spy_sym),
            self.get_options_chain(symbol),
            self.get_intraday_candles(spy_sym, interval="1min"),
            self.get_intraday_candles(spy_sym, interval="5min"),
            self.get_quotes(["VIX", "VIX3M", "VVIX"]),
            self.get_quotes([
                "XLK","XLF","XLV","XLC","XLY","XLP","XLE","XLI","XLB","XLRE","XLU",
                "AAPL","MSFT","NVDA","AMZN","GOOGL","META","JPM","BAC","UNH",
            ]),
        )

        return {
            "quote":           quote,
            "spy_quote":       spy_quote,
            "options_chain":   chain,
            "candles_1min":    intraday_1min,
            "candles_5min":    intraday_5min,
            "vix_quotes":      vix_quotes,
            "breadth_quotes":  breadth_quotes,
            "fetched_at":      datetime.utcnow().isoformat(),
        }
