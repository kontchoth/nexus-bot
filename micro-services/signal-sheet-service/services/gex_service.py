"""GEX calculation, options walls, daily range estimate, and premarket bias."""

from __future__ import annotations

import math
from datetime import date

from .tradier_client import TradierClient


class GEXService:
    def __init__(
        self,
        api_key: str | None = None,
        sandbox: bool = False,
        *,
        client: TradierClient | None = None,
    ):
        if client is None and api_key is None:
            raise ValueError("api_key is required when no TradierClient is provided")
        self._client = client or TradierClient(api_key, sandbox)

    async def get_spot_price(self, symbol: str) -> float:
        quote = await self._client.get_quote(symbol)
        last = quote.get("last") or quote.get("prevclose") or 0.0
        return float(last)

    async def get_premarket_bias(self, symbol: str) -> dict:
        quote = await self._client.get_quote(symbol)
        prev_close = float(quote.get("prevclose") or 0)
        pre_price = float(quote.get("last") or prev_close)

        if prev_close <= 0:
            return {"bias": "Neutral", "price": pre_price, "change_pct": 0.0}

        change_pct = ((pre_price - prev_close) / prev_close) * 100

        if change_pct > 0.75:
            bias = "Extremely Bullish"
        elif change_pct > 0.35:
            bias = "Bullish"
        elif change_pct > 0.10:
            bias = "Slightly Bullish"
        elif change_pct < -0.75:
            bias = "Extremely Bearish"
        elif change_pct < -0.35:
            bias = "Bearish"
        elif change_pct < -0.10:
            bias = "Slightly Bearish"
        else:
            bias = "Neutral"

        return {"bias": bias, "price": pre_price, "change_pct": round(change_pct, 4)}

    async def get_yesterday_close(self, symbol: str) -> float:
        quote = await self._client.get_quote(symbol)
        return float(quote.get("prevclose") or 0)

    async def calculate_gex(self, symbol: str, *, as_of_date: date | None = None) -> dict:
        expirations = await self._client.get_options_expirations(symbol)
        spot = await self.get_spot_price(symbol)

        # Use near-term expirations (next 30 days) for GEX — most relevant
        today = as_of_date or date.today()
        near_term = [
            exp for exp in expirations
            if 0 <= (date.fromisoformat(exp) - today).days <= 30
        ][:5]  # max 5 expirations

        total_gex = 0.0
        strike_gex: dict[float, float] = {}

        for exp in near_term:
            chain = await self._client.get_options_chain(symbol, exp)
            for opt in chain:
                greeks = opt.get("greeks") or {}
                gamma = float(greeks.get("gamma") or 0)
                oi = float(opt.get("open_interest") or 0)
                strike = float(opt.get("strike") or 0)
                otype = opt.get("option_type", "call")

                if gamma == 0 or oi == 0:
                    continue

                gex = gamma * oi * 100 * spot
                if otype == "put":
                    gex = -gex

                total_gex += gex
                strike_gex[strike] = strike_gex.get(strike, 0.0) + gex

        flip_level = _find_flip_level(strike_gex, spot)
        gamma_wall = _find_gamma_wall(strike_gex)
        put_wall = _find_put_wall(strike_gex, spot)

        return {
            "net_gex": total_gex,
            "flip_level": flip_level,
            "gamma_wall": gamma_wall,
            "put_wall": put_wall,
            "strike_gex": {str(k): v for k, v in strike_gex.items()},
            "regime": _derive_regime(total_gex),
        }

    async def get_options_walls(self, symbol: str, *, as_of_date: date | None = None) -> dict:
        spot = await self.get_spot_price(symbol)
        expirations = await self._client.get_options_expirations(symbol)

        # Use first 2 near-term expirations for OI walls
        today = as_of_date or date.today()
        near_term = [
            exp for exp in expirations
            if 0 <= (date.fromisoformat(exp) - today).days <= 14
        ][:2]

        calls_by_strike: dict[float, int] = {}
        puts_by_strike: dict[float, int] = {}

        for exp in near_term:
            chain = await self._client.get_options_chain(symbol, exp)
            for opt in chain:
                strike = float(opt.get("strike") or 0)
                oi = int(opt.get("open_interest") or 0)
                otype = opt.get("option_type", "call")
                if otype == "call" and strike > spot:
                    calls_by_strike[strike] = calls_by_strike.get(strike, 0) + oi
                elif otype == "put" and strike < spot:
                    puts_by_strike[strike] = puts_by_strike.get(strike, 0) + oi

        top_calls = sorted(calls_by_strike.items(), key=lambda x: x[1], reverse=True)[:2]
        top_puts = sorted(puts_by_strike.items(), key=lambda x: x[1], reverse=True)[:2]

        return {
            "rally": [[s, oi] for s, oi in top_calls],
            "drop": [[s, oi] for s, oi in top_puts],
        }

    async def estimate_daily_range(self, symbol: str, *, as_of_date: date | None = None) -> float:
        spot = await self.get_spot_price(symbol)
        expirations = await self._client.get_options_expirations(symbol)

        today = as_of_date or date.today()
        near = sorted(
            [exp for exp in expirations if (date.fromisoformat(exp) - today).days >= 0],
            key=lambda x: date.fromisoformat(x),
        )
        if not near:
            return 0.0

        chain = await self._client.get_options_chain(symbol, near[0])
        atm = min(
            chain,
            key=lambda x: abs(float(x.get("strike") or 0) - spot),
            default=None,
        )
        if not atm:
            return 0.0

        greeks = atm.get("greeks") or {}
        iv = float(greeks.get("mid_iv") or greeks.get("smv_vol") or 0.15)
        if iv <= 0:
            iv = 0.15

        return round(spot * iv / math.sqrt(252), 2)


# ── Helpers ───────────────────────────────────────────────────────────────────

def _find_flip_level(strike_gex: dict[float, float], spot: float) -> float:
    """Strike where cumulative GEX (sorted by strike) crosses zero."""
    if not strike_gex:
        return spot
    sorted_strikes = sorted(strike_gex.items())
    cumulative = 0.0
    prev_strike = sorted_strikes[0][0]
    for strike, gex in sorted_strikes:
        prev_cumulative = cumulative
        cumulative += gex
        if prev_cumulative * cumulative < 0:  # sign change
            return strike
        prev_strike = strike
    return spot


def _find_gamma_wall(strike_gex: dict[float, float]) -> float:
    """Strike with highest positive GEX contribution."""
    if not strike_gex:
        return 0.0
    positive = {k: v for k, v in strike_gex.items() if v > 0}
    if not positive:
        return 0.0
    return max(positive, key=lambda k: positive[k])


def _find_put_wall(strike_gex: dict[float, float], spot: float) -> float:
    """Strike below spot with most negative GEX."""
    if not strike_gex:
        return 0.0
    below = {k: v for k, v in strike_gex.items() if k < spot and v < 0}
    if not below:
        return 0.0
    return min(below, key=lambda k: below[k])


def _derive_regime(net_gex: float) -> str:
    if net_gex < -30_000_000_000:
        return "Short Gamma — Amplified"
    if net_gex < 0:
        return "Short Gamma — Moderate"
    if net_gex > 30_000_000_000:
        return "Long Gamma — Suppressed"
    return "Neutral Gamma"
