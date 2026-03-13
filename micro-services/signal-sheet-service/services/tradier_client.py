"""Shared async Tradier HTTP client."""

from __future__ import annotations

from datetime import date, timedelta

import httpx

_BASE = "https://api.tradier.com/v1"
_BASE_SANDBOX = "https://sandbox.tradier.com/v1"


class TradierClient:
    def __init__(self, api_key: str, sandbox: bool = False):
        self._base = _BASE_SANDBOX if sandbox else _BASE
        headers = {
            "Authorization": f"Bearer {api_key}",
            "Accept": "application/json",
        }
        self._client = httpx.AsyncClient(base_url=self._base, headers=headers, timeout=20.0)

    async def close(self) -> None:
        await self._client.aclose()

    async def __aenter__(self) -> "TradierClient":
        return self

    async def __aexit__(self, exc_type, exc, tb) -> None:
        await self.close()

    async def _get(self, path: str, *, params: dict) -> dict:
        response = await self._client.get(path, params=params)
        response.raise_for_status()
        return response.json()

    async def get_quote(self, symbol: str) -> dict:
        data = await self._get("/markets/quotes", params={"symbols": symbol, "greeks": "false"})
        return data["quotes"]["quote"]

    async def get_options_expirations(self, symbol: str) -> list[str]:
        data = await self._get(
            "/markets/options/expirations",
            params={"symbol": symbol, "includeAllRoots": "true"},
        )
        expirations = data["expirations"]
        return expirations.get("date", []) if expirations else []

    async def get_options_chain(self, symbol: str, expiration: str) -> list[dict]:
        data = await self._get(
            "/markets/options/chains",
            params={"symbol": symbol, "expiration": expiration, "greeks": "true"},
        )
        options_root = data["options"]
        if not options_root:
            return []
        options = options_root.get("option", [])
        return options if isinstance(options, list) else [options]

    async def get_intraday_bars(
        self, symbol: str, session_date: str, interval: str = "1min"
    ) -> list[dict]:
        data = await self._get(
            "/markets/timesales",
            params={
                "symbol": symbol,
                "interval": interval,
                "start": f"{session_date} 09:30",
                "end": f"{session_date} 16:00",
                "session_filter": "open",
            },
        )
        series = data.get("series")
        if not series:
            return []
        items = series.get("data", [])
        rows = items if isinstance(items, list) else [items]
        return sorted(rows, key=_bar_sort_key)

    async def get_history(
        self,
        symbol: str,
        interval: str = "daily",
        lookback_days: int = 30,
        end_date: date | None = None,
    ) -> list[dict]:
        end = end_date or date.today()
        start = end - timedelta(days=lookback_days)
        data = await self._get(
            "/markets/history",
            params={
                "symbol": symbol,
                "interval": interval,
                "start": start.isoformat(),
                "end": end.isoformat(),
            },
        )
        history = data.get("history")
        if not history:
            return []
        items = history.get("day", [])
        return items if isinstance(items, list) else [items]

    async def get_multi_quotes(self, symbols: list[str]) -> list[dict]:
        data = await self._get(
            "/markets/quotes",
            params={"symbols": ",".join(symbols), "greeks": "false"},
        )
        quotes = data["quotes"]["quote"]
        return quotes if isinstance(quotes, list) else [quotes]


def _bar_sort_key(bar: dict) -> str:
    for field in ("time", "timestamp", "date"):
        value = bar.get(field)
        if value is not None:
            return str(value)
    return str(bar.get("seq") or "")
