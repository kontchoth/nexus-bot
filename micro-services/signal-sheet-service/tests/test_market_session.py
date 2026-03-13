import sys
import unittest
from datetime import date, datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from services.market_session import get_session_context, is_trading_day


class MarketSessionTests(unittest.TestCase):
    def test_weekday_is_trading_day(self):
        self.assertTrue(is_trading_day(date(2026, 3, 13)))

    def test_weekend_is_not_trading_day(self):
        self.assertFalse(is_trading_day(date(2026, 3, 14)))

    def test_observed_holiday_is_not_trading_day(self):
        self.assertFalse(is_trading_day(date(2026, 7, 3)))

    def test_session_context_uses_eastern_market_date(self):
        context = get_session_context(datetime(2026, 3, 13, 2, 30, tzinfo=timezone.utc))
        self.assertEqual(context.market_date, "2026-03-12")


if __name__ == "__main__":
    unittest.main()
