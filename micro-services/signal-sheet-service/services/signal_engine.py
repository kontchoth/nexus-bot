"""Computes all 7 SPX/SPY trading signals from live market data."""

from __future__ import annotations

from datetime import date, datetime

from .market_session import MARKET_TZ
from .tradier_client import TradierClient

# ── Types ─────────────────────────────────────────────────────────────────────

SignalResult = dict   # {bias, value, confidence}
DPLResult    = dict   # {direction, color, separation, is_expanding}
BreadthResult = dict  # {ratio, bias, participation}

_SECTOR_ETFS = ["XLK", "XLF", "XLV", "XLE", "XLI", "XLC", "XLY", "XLP", "XLRE", "XLB", "XLU"]

# ── Engine ────────────────────────────────────────────────────────────────────

class SignalEngine:
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

    async def compute_all_7_signals(
        self,
        symbol: str,
        *,
        market_date: str | None = None,
        as_of_date: date | None = None,
        now: datetime | None = None,
    ) -> dict:
        today = market_date or date.today().isoformat()
        current_time = now or datetime.now(MARKET_TZ)
        reference_date = as_of_date or date.fromisoformat(today)

        # Fetch data in parallel where possible
        import asyncio
        bars_task    = self._client.get_intraday_bars(symbol, today)
        history_task = self._client.get_history(
            symbol,
            interval="daily",
            lookback_days=60,
            end_date=reference_date,
        )
        etf_task     = self._client.get_multi_quotes(_SECTOR_ETFS)
        chain_task   = self._get_near_chain(symbol, as_of_date=reference_date)

        bars, history, etf_quotes, chain = await asyncio.gather(
            bars_task, history_task, etf_task, chain_task
        )

        spy_component  = _compute_spy_component(history)
        itod           = _compute_itod(history, current_time)
        optimized_tod  = _compute_optimized_tod(bars)
        tod_gap        = _compute_tod_gap(history, bars)
        dpl            = _compute_dpl(bars)
        ad_breadth     = _compute_ad_breadth(etf_quotes)
        dom_gap        = _compute_dom_gap(chain, history, bars)

        return {
            "spy_component": spy_component,
            "iToD":          itod,
            "optimized_tod": optimized_tod,
            "tod_gap":       tod_gap,
            "dpl":           dpl,
            "ad_6_5":        ad_breadth,
            "dom_gap":       dom_gap,
        }

    async def compute_dpl_live(self, symbol: str, *, market_date: str | None = None) -> DPLResult:
        today = market_date or date.today().isoformat()
        bars = await self._client.get_intraday_bars(symbol, today)
        return _compute_dpl(bars)

    async def _get_near_chain(self, symbol: str, *, as_of_date: date | None = None) -> list:
        expirations = await self._client.get_options_expirations(symbol)
        today = as_of_date or date.today()
        near = sorted(
            [exp for exp in expirations if (date.fromisoformat(exp) - today).days >= 0],
            key=lambda x: date.fromisoformat(x),
        )
        if not near:
            return []
        return await self._client.get_options_chain(symbol, near[0])


# ── Signal implementations ────────────────────────────────────────────────────

def _compute_spy_component(history: list[dict]) -> SignalResult:
    """
    Premarket bias: compare most-recent session open vs prior close.
    Uses daily history because intraday premarket isn't always available.
    """
    if len(history) < 2:
        return _neutral_signal()

    prev  = history[-2]
    today = history[-1]
    prev_close = float(prev.get("close") or 0)
    open_price = float(today.get("open") or 0)

    if prev_close <= 0 or open_price <= 0:
        return _neutral_signal()

    gap_pct = (open_price - prev_close) / prev_close
    bias = _pct_to_bias(gap_pct, threshold=0.002)
    return {
        "bias":       bias,
        "value":      round(gap_pct * 100, 4),
        "confidence": min(abs(gap_pct) / 0.005, 1.0),
    }


def _compute_itod(history: list[dict], now: datetime) -> SignalResult:
    """
    Historical time-of-day bias.
    Groups daily returns by hour block and returns average directional bias
    for the current time block using available daily data as a proxy.
    For full iToD accuracy, replace history with 1-min historical bars.
    """
    if len(history) < 10:
        return _neutral_signal()

    # Proxy: use average of last N day directional biases
    recent = history[-20:]
    up_days = sum(
        1 for d in recent
        if float(d.get("close") or 0) > float(d.get("open") or 0)
    )
    ratio = up_days / len(recent)

    bias = "bullish" if ratio > 0.6 else "bearish" if ratio < 0.4 else "neutral"
    value = round((ratio - 0.5) * 2, 4)  # normalize to -1..1

    # Adjust confidence by time of day: highest after first hour
    hour = now.hour
    time_conf = 0.5 if hour < 10 else (0.8 if hour < 12 else 0.6)

    return {
        "bias":       bias,
        "value":      value,
        "confidence": round(min(abs(value) * time_conf, 1.0), 4),
    }


def _compute_optimized_tod(bars: list[dict]) -> SignalResult:
    """
    Optimized ToD: EMA5 vs EMA13 of intraday close prices.
    Positive separation → bullish, negative → bearish.
    """
    if len(bars) < 14:
        return _neutral_signal()

    closes = [float(b.get("close") or b.get("price") or 0) for b in bars]
    closes = [c for c in closes if c > 0]
    if len(closes) < 14:
        return _neutral_signal()

    ema5  = _ema(closes, 5)
    ema13 = _ema(closes, 13)
    sep   = ema5 - ema13
    deadband = 0.4

    if sep > deadband:
        bias, conf = "bullish", min(sep / 2.0, 1.0)
    elif sep < -deadband:
        bias, conf = "bearish", min(abs(sep) / 2.0, 1.0)
    else:
        bias, conf = "neutral", 0.3

    return {"bias": bias, "value": round(sep, 4), "confidence": round(conf, 4)}


def _compute_tod_gap(history: list[dict], bars: list[dict]) -> SignalResult:
    """
    ToD/Gap: blends gap-at-open with intraday trend.
    Significant gap (>0.35%) biases toward continuation; otherwise follows trend.
    """
    gap_signal  = _compute_spy_component(history)
    trend_signal = _compute_optimized_tod(bars)

    gap_pct = abs(float(gap_signal["value"]) / 100) if gap_signal["value"] != 0 else 0

    if gap_pct >= 0.35:
        # Significant gap — bias toward gap direction
        return {
            "bias":       gap_signal["bias"],
            "value":      gap_signal["value"],
            "confidence": min(gap_signal["confidence"] * 1.2, 1.0),
        }

    # No significant gap — defer to trend
    return trend_signal


def _compute_dpl(bars: list[dict]) -> DPLResult:
    """
    DPL = MACD(12, 26, 9) on intraday close prices.
    direction: LONG if MACD > signal line, SHORT otherwise.
    color: green (LONG) or red (SHORT).
    separation: magnitude of MACD - signal.
    is_expanding: separation growing vs prior bar.
    """
    if len(bars) < 27:
        return _neutral_dpl()

    closes = [float(b.get("close") or b.get("price") or 0) for b in bars]
    closes = [c for c in closes if c > 0]
    if len(closes) < 27:
        return _neutral_dpl()

    macd_line   = _macd_line(closes, fast=12, slow=26)
    signal_line = _ema(macd_line, 9)
    sep_now     = macd_line[-1] - signal_line
    sep_prev    = (macd_line[-2] - _ema(macd_line[:-1], 9)) if len(macd_line) > 1 else sep_now

    direction    = "LONG"  if sep_now > 0 else "SHORT"
    color        = "green" if sep_now > 0 else "red"
    is_expanding = abs(sep_now) > abs(sep_prev)

    return {
        "direction":    direction,
        "color":        color,
        "separation":   round(abs(sep_now), 6),
        "is_expanding": is_expanding,
    }


def _compute_ad_breadth(etf_quotes: list[dict]) -> BreadthResult:
    """
    Advance/Decline breadth via 11 sector ETFs.
    """
    if not etf_quotes:
        return {"ratio": 0.5, "bias": "neutral", "participation": "mixed"}

    advancing = sum(
        1 for q in etf_quotes
        if float(q.get("change_percentage") or q.get("change") or 0) > 0
    )
    total = len(etf_quotes)
    ratio = advancing / total if total > 0 else 0.5

    if ratio > 0.65:
        bias, part = "bullish", ("broad" if ratio > 0.80 else "mixed")
    elif ratio < 0.35:
        bias, part = "bearish", ("broad" if ratio < 0.20 else "mixed")
    else:
        bias, part = "neutral", "mixed"

    return {
        "ratio":         round(ratio, 4),
        "bias":          bias,
        "participation": part,
    }


def _compute_dom_gap(chain: list[dict], history: list[dict], bars: list[dict]) -> SignalResult:
    """
    DOM/Gap: upside call OI / downside put OI ratio, blended with gap signal.
    """
    spot = float(bars[-1].get("close") or bars[-1].get("price") or 0) if bars else 0
    if spot <= 0 and history:
        spot = float(history[-1].get("close") or 0)

    if not chain or spot <= 0:
        return _neutral_signal()

    upside_oi   = sum(
        int(opt.get("open_interest") or 0)
        for opt in chain
        if opt.get("option_type") == "call" and float(opt.get("strike") or 0) > spot
    )
    downside_oi = sum(
        int(opt.get("open_interest") or 0)
        for opt in chain
        if opt.get("option_type") == "put" and float(opt.get("strike") or 0) < spot
    )

    total_oi = upside_oi + downside_oi
    if total_oi == 0:
        return _neutral_signal()

    ratio = upside_oi / total_oi  # 0..1, >0.5 = more call OI above

    # Blend with gap signal
    gap_signal = _compute_spy_component(history)
    gap_weight = 0.3
    dom_weight = 0.7

    dom_value = (ratio - 0.5) * 2  # normalize to -1..1
    gap_value = float(gap_signal["value"]) / 100 if gap_signal["value"] != 0 else 0
    blended   = dom_value * dom_weight + gap_value * gap_weight

    bias = _pct_to_bias(blended, threshold=0.05)
    return {
        "bias":       bias,
        "value":      round(blended, 4),
        "confidence": min(abs(blended), 1.0),
    }


# ── Math helpers ──────────────────────────────────────────────────────────────

def _ema(values: list[float], period: int) -> float:
    """Returns the last EMA value."""
    if not values or len(values) < period:
        return values[-1] if values else 0.0
    k = 2 / (period + 1)
    ema = sum(values[:period]) / period
    for v in values[period:]:
        ema = v * k + ema * (1 - k)
    return ema


def _macd_line(closes: list[float], fast: int = 12, slow: int = 26) -> list[float]:
    """Returns the MACD line (EMA fast - EMA slow) across all available points."""
    result = []
    for i in range(slow, len(closes) + 1):
        window = closes[:i]
        result.append(_ema(window, fast) - _ema(window, slow))
    return result if result else [0.0]


def _pct_to_bias(pct: float, threshold: float = 0.002) -> str:
    if pct > threshold:
        return "bullish"
    if pct < -threshold:
        return "bearish"
    return "neutral"


def _neutral_signal() -> SignalResult:
    return {"bias": "neutral", "value": 0.0, "confidence": 0.0}


def _neutral_dpl() -> DPLResult:
    return {"direction": "NEUTRAL", "color": "gray", "separation": 0.0, "is_expanding": False}
