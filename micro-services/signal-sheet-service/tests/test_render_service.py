import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

try:
    from services.render_service import RenderService
except ModuleNotFoundError:
    RenderService = None


def _playbook() -> dict:
    return {
        "date": "2026-03-13",
        "symbol": "SPX",
        "generated_at": "2026-03-13T13:20:00+00:00",
        "last_refreshed_at": "2026-03-13T14:05:00+00:00",
        "status": "locked",
        "yesterday_close": 6672,
        "official_open": 6680,
        "net_gex": -63476000000,
        "flip_level": 6789,
        "gamma_wall": 6700,
        "put_wall": 6650,
        "regime": "Short Gamma - Amplified",
        "spx_range_est": 60,
        "premarket_bias": "Extremely Bullish",
        "premarket_price": 6688,
        "algorithm_step": 1,
        "recommendation": "WAIT",
        "signal_unity": False,
        "reason": "Gap day. Wait for post-open DPL confirmation.",
        "min14_high": 6692,
        "min14_low": 6678,
        "otm_long_strike": 6628,
        "otm_short_strike": 6742,
        "dpl_live": {"direction": "LONG", "separation": 2.15},
        "signals": {
            "spy_component": {"bias": "bullish"},
            "iToD": {"bias": "bullish"},
            "optimized_tod": {"bias": "neutral"},
            "tod_gap": {"bias": "bullish"},
            "dpl": {"direction": "LONG"},
            "ad_6_5": {"bias": "neutral"},
            "dom_gap": {"bias": "bullish"},
        },
        "screenshots": {},
    }


@unittest.skipIf(RenderService is None, "Pillow is not installed")
class RenderServiceTests(unittest.TestCase):
    def test_premarket_phase_is_ready_after_generate(self):
        ready, reason = RenderService().phase_readiness(_playbook(), "premarket")
        self.assertTrue(ready)
        self.assertIsNone(reason)

    def test_locked_phase_requires_minute14_levels(self):
        playbook = _playbook()
        playbook["min14_high"] = None
        ready, reason = RenderService().phase_readiness(playbook, "locked")
        self.assertFalse(ready)
        self.assertEqual(reason, "minute14_not_locked")

    def test_render_returns_png_bytes(self):
        rendered = RenderService().render(_playbook(), "locked")
        self.assertEqual(rendered.image_bytes[:8], b"\x89PNG\r\n\x1a\n")
        self.assertEqual(rendered.width, 1600)
        self.assertEqual(rendered.height, 1100)


if __name__ == "__main__":
    unittest.main()
