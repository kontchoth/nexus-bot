"""
Nexus Bot — Tradier Production API Client
Covers: quotes, candles (timesales), options chain, and market clock.
"""
import os
import time
import logging
from datetime import datetime, date, timedelta
from typing import List, Optional, Dict, Any
import requests
from .models import Quote, Candle, OptionContract

logger = logging.getLogger(__name__)

TRADIER_BASE = "https://api.tradier.com/v1"
TRADIER_BROKERAGE = "https://api.tradier.com/v1"

# ─── Token resolution (Lambda env var or passed directly) ────────────────────
def _get_token() -> str:
    token = os.environ.get("TRADIER_TOKEN")
    if not token:
        raise EnvironmentError("TRADIER_TOKEN environment variable not set.")
    return token


class TradierClient:
    """Thread-safe, session-reusing Tradier client."""

    def __init__(self, token: Optional[str] = None, timeout: int = 10):
        self.token   = token or _get_token()
        self.timeout = timeout
        self._session = requests.Session()
        self._session.headers.update({
            "Authorization": f"Bearer {self.token}",
            "Accept":        "application/json",
        })

    # ─────────────────────────────────────────────
    # Internal helpers
    # ─────────────────────────────────────────────

    def _get(self, path: str, params: Dict = None) -> Dict:
        url = f"{TRADIER_BASE}{path}"
        resp = self._session.get(url, params=params, timeout=self.timeout)
        resp.raise_for_status()
        return resp.json()

    # ─────────────────────────────────────────────
    # Market Clock / Status
    # ─────────────────────────────────────────────

    def market_status(self) -> Dict:
        """Returns current market state: 'open', 'premarket', 'postmarket', 'closed'."""
        data = self._get("/markets/clock")
        return data.get("clock", {})

    def is_market_open(self) -> bool:
        clock = self.market_status()
        return clock.get("state") == "open"

    def is_premarket(self) -> bool:
        clock = self.market_status()
        return clock.get("state") == "premarket"

    # ─────────────────────────────────────────────
    # Quotes
    # ─────────────────────────────────────────────

    def get_quote(self, symbol: str) -> Quote:
        data = self._get("/markets/quotes", {"symbols": symbol, "greeks": "false"})
        raw = data["quotes"]["quote"]
        return Quote(
            symbol     = raw["symbol"],
            bid        = float(raw.get("bid") or 0),
            ask        = float(raw.get("ask") or 0),
            last       = float(raw.get("last") or raw.get("close") or 0),
            volume     = int(raw.get("volume") or 0),
            open       = float(raw["open"]) if raw.get("open") else None,
            prev_close = float(raw["prevclose"] or raw.get("close") or 0),
            timestamp  = datetime.utcnow(),
        )

    def get_quotes(self, symbols: List[str]) -> Dict[str, Quote]:
        joined = ",".join(symbols)
        data   = self._get("/markets/quotes", {"symbols": joined, "greeks": "false"})
        quotes_raw = data["quotes"]["quote"]
        if isinstance(quotes_raw, dict):
            quotes_raw = [quotes_raw]
        return {
            q["symbol"]: Quote(
                symbol     = q["symbol"],
                bid        = float(q.get("bid") or 0),
                ask        = float(q.get("ask") or 0),
                last       = float(q.get("last") or q.get("close") or 0),
                volume     = int(q.get("volume") or 0),
                open       = float(q["open"]) if q.get("open") else None,
                prev_close = float(q["prevclose"] or q.get("close") or 0),
                timestamp  = datetime.utcnow(),
            )
            for q in quotes_raw
        }

    # ─────────────────────────────────────────────
    # Candles (timesales)
    # ─────────────────────────────────────────────

    def get_intraday_candles(
        self,
        symbol:   str,
        interval: str = "5min",   # '1min' | '5min' | '15min'
        start:    Optional[str] = None,
        end:      Optional[str] = None,
    ) -> List[Candle]:
        """
        Returns intraday OHLCV candles for today (or a specific date range).
        interval: '1min' | '5min' | '15min'
        """
        today = date.today().isoformat()
        params = {
            "symbol":   symbol,
            "interval": interval,
            "start":    start or f"{today} 09:30",
            "end":      end   or f"{today} 16:00",
            "session_filter": "open",
        }
        data = self._get("/markets/timesales", params)
        series = data.get("series") or {}
        raw_candles = series.get("data") or []
        if isinstance(raw_candles, dict):
            raw_candles = [raw_candles]

        candles = []
        for c in raw_candles:
            try:
                candles.append(Candle(
                    timestamp = datetime.fromisoformat(c["time"]),
                    open      = float(c["open"]),
                    high      = float(c["high"]),
                    low       = float(c["low"]),
                    close     = float(c["close"]),
                    volume    = int(c["volume"]),
                ))
            except (KeyError, ValueError) as e:
                logger.warning("Skipping malformed candle: %s — %s", c, e)
        return candles

    def get_daily_candles(
        self,
        symbol: str,
        lookback_days: int = 30,
    ) -> List[Candle]:
        """Returns daily OHLCV for the past N trading days."""
        end_date   = date.today()
        start_date = end_date - timedelta(days=lookback_days * 2)  # buffer for weekends
        params = {
            "symbol": symbol,
            "interval": "daily",
            "start":    start_date.isoformat(),
            "end":      end_date.isoformat(),
        }
        data = self._get("/markets/history", params)
        history = data.get("history") or {}
        raw = history.get("day") or []
        if isinstance(raw, dict):
            raw = [raw]

        candles = []
        for c in raw[-lookback_days:]:
            try:
                candles.append(Candle(
                    timestamp = datetime.fromisoformat(c["date"]),
                    open      = float(c["open"]),
                    high      = float(c["high"]),
                    low       = float(c["low"]),
                    close     = float(c["close"]),
                    volume    = int(c["volume"]),
                ))
            except (KeyError, ValueError) as e:
                logger.warning("Skipping malformed daily candle: %s — %s", c, e)
        return candles

    # ─────────────────────────────────────────────
    # Options Chain (with Greeks)
    # ─────────────────────────────────────────────

    def get_options_expirations(self, symbol: str) -> List[str]:
        data = self._get("/markets/options/expirations", {"symbol": symbol, "includeAllRoots": "true"})
        exp  = data.get("expirations", {}).get("date") or []
        return exp if isinstance(exp, list) else [exp]

    def get_options_chain(
        self,
        symbol:     str,
        expiration: Optional[str] = None,
        greeks:     bool = True,
    ) -> List[OptionContract]:
        """
        Fetches the full options chain for the nearest expiration (or specified date).
        Returns a flat list of OptionContract with Greeks.
        """
        if not expiration:
            expirations = self.get_options_expirations(symbol)
            if not expirations:
                return []
            # Prefer 0-DTE (today) or nearest weekly
            today_str = date.today().isoformat()
            expiration = expirations[0]
            for exp in expirations:
                if exp >= today_str:
                    expiration = exp
                    break

        params = {
            "symbol":     symbol,
            "expiration": expiration,
            "greeks":     "true" if greeks else "false",
        }
        data    = self._get("/markets/options/chains", params)
        options = data.get("options", {}).get("option") or []
        if isinstance(options, dict):
            options = [options]

        contracts = []
        for o in options:
            try:
                greeks_data = o.get("greeks") or {}
                contracts.append(OptionContract(
                    symbol        = o["symbol"],
                    underlying    = o["underlying"],
                    strike        = float(o["strike"]),
                    expiration    = o["expiration_date"],
                    option_type   = o["option_type"],        # 'call' | 'put'
                    bid           = float(o.get("bid")  or 0),
                    ask           = float(o.get("ask")  or 0),
                    last          = float(o.get("last") or 0),
                    volume        = int(o.get("volume") or 0),
                    open_interest = int(o.get("open_interest") or 0),
                    iv            = float(greeks_data.get("smv_vol") or o.get("iv") or 0),
                    delta         = float(greeks_data.get("delta") or 0),
                    gamma         = float(greeks_data.get("gamma") or 0),
                    theta         = float(greeks_data.get("theta") or 0),
                    vega          = float(greeks_data.get("vega")  or 0),
                ))
            except (KeyError, ValueError, TypeError) as e:
                logger.warning("Skipping malformed option: %s — %s", o.get("symbol"), e)
        return contracts

    # ─────────────────────────────────────────────
    # Advance / Decline (via index quotes)
    # ─────────────────────────────────────────────

    def get_advance_decline(self) -> Dict[str, int]:
        """
        Approximate A/D using SPY component ETFs as a proxy.
        For production accuracy, replace with a direct data source or
        track each S&P 500 constituent (expensive API-wise).

        Returns: {"advances": N, "declines": N, "unchanged": N}
        """
        # Sector ETFs as a breadth proxy (11 GICS sectors)
        sector_etfs = [
            "XLK", "XLF", "XLV", "XLC", "XLY", "XLP",
            "XLE", "XLI", "XLB", "XLRE", "XLU",
        ]
        quotes = self.get_quotes(sector_etfs)
        advances  = 0
        declines  = 0
        unchanged = 0
        for q in quotes.values():
            change = q.last - q.prev_close
            if change > 0.05:
                advances += 1
            elif change < -0.05:
                declines += 1
            else:
                unchanged += 1
        return {"advances": advances, "declines": declines, "unchanged": unchanged}
