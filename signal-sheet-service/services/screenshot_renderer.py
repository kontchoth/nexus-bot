"""
NexusBot — Screenshot Renderer
Generates 3 PNG phase artifacts from a Firestore playbook document.

Phases:
  premarket  → 09:21 ET  — before open context sheet
  locked     → 09:45 ET  — first actionable image with min-14 locked
  final      → 10:06 ET  — complete early-session summary

Rules (spec §14):
  - reads ONLY from the stored playbook dict (no market data calls)
  - renders deterministic PNGs using Pillow
  - writes to GCS at gs://<bucket>/signal-sheet/<date>/<phase>.png
  - writes artifact metadata back via PlaybookWriter (called from main.py)
  - rendering failure must NOT block market-data endpoints
  - reruns overwrite the same GCS path

Color palette: dark background matching the reference screenshot
"""
from __future__ import annotations

import io
import logging
import os
from typing import Any, Dict, Optional

from google.cloud import storage
from PIL import Image, ImageDraw, ImageFont

logger = logging.getLogger(__name__)

TEMPLATE_VERSION = "v1.0"
GCS_BUCKET       = os.environ.get("SCREENSHOT_BUCKET", "nexus-bot-screenshots")

# ─── Palette ─────────────────────────────────────────────────────────────────
BG          = (13,  17,  23)    # near-black
CARD_BG     = (22,  27,  34)    # dark card
BORDER      = (48,  54,  61)    # subtle border
TEXT_WHITE  = (230, 237, 243)
TEXT_MUTED  = (139, 148, 158)
GREEN       = (63,  185, 80)
RED         = (248, 81,  73)
YELLOW      = (210, 153, 34)
BLUE        = (88,  166, 255)
ORANGE      = (210, 107, 33)

W, H = 1080, 1920   # portrait phone size

# ─────────────────────────────────────────────────────────────────────────────

class ScreenshotRenderer:

    def __init__(self, bucket_name: str = GCS_BUCKET):
        self._bucket_name = bucket_name
        self._gcs = storage.Client()

    async def render(
        self,
        phase:    str,
        playbook: Dict[str, Any],
        mdate:    str,
    ) -> Dict[str, Any]:
        """
        Render a PNG for the given phase, upload to GCS, return artifact metadata.
        """
        img = self._draw(phase, playbook)

        buf = io.BytesIO()
        img.save(buf, format="PNG", optimize=True)
        buf.seek(0)

        gcs_path    = f"signal-sheet/{mdate}/{phase}.png"
        public_url  = self._upload(gcs_path, buf.getvalue())

        return {
            "storage_path":     f"gs://{self._bucket_name}/{gcs_path}",
            "public_url":       public_url,
            "width":            W,
            "height":           H,
            "template_version": TEMPLATE_VERSION,
        }

    # ─────────────────────────────────────────────────────────────────────────
    # Drawing
    # ─────────────────────────────────────────────────────────────────────────

    def _draw(self, phase: str, pb: Dict[str, Any]) -> Image.Image:
        img  = Image.new("RGB", (W, H), BG)
        draw = ImageDraw.Draw(img)

        y = 0
        y = self._draw_header(draw, pb, y)
        y = self._draw_market_context(draw, pb, y)
        y = self._draw_signals_panel(draw, pb, y)
        y = self._draw_algorithm_panel(draw, pb, phase, y)

        if phase in ("locked", "final") and pb.get("min14_high") is not None:
            y = self._draw_minute14_panel(draw, pb, y)

        if phase == "final":
            y = self._draw_refresh_panel(draw, pb, y)

        self._draw_footer(draw, pb, phase)
        return img

    def _draw_header(self, draw: ImageDraw.Draw, pb: Dict, y: int) -> int:
        draw.rectangle([0, y, W, y + 80], fill=(10, 10, 18))
        _text(draw, "NexusBot",               (20, y + 14), TEXT_MUTED, 20)
        _text(draw, "SPX Daily Signal Sheet",  (20, y + 34), TEXT_WHITE, 28, bold=True)
        date_str = pb.get("date", "")
        _text(draw, date_str, (W - 160, y + 38), TEXT_MUTED, 18)
        return y + 90

    def _draw_market_context(self, draw: ImageDraw.Draw, pb: Dict, y: int) -> int:
        _section_label(draw, "MARKET CONTEXT", y)
        y += 30

        rows = [
            ("Yesterday Close",  f"{pb.get('yesterday_close', 0):,.2f}"),
            ("Net GEX / Flip",   f"{pb.get('net_gex', 0):+.3f}B  /  {pb.get('flip_level', 0):,.0f}"),
            ("Regime",           pb.get("regime", "—")),
            ("Wall vs Rally",    f"{pb.get('gamma_wall', '—')}"),
            ("Wall vs Drop",     f"{pb.get('put_wall', '—')}"),
            ("SPX Range Est",    f"{pb.get('spx_range_est', 0):.0f} pts"),
            ("VIX",              f"{pb.get('vix', 0):.2f}  ({pb.get('vix_regime', '—')})"),
        ]
        if pb.get("official_open"):
            rows.insert(1, ("Official Open", f"{pb['official_open']:,.2f}"))

        for label, value in rows:
            _kv_row(draw, label, value, y)
            y += 34
        return y + 10

    def _draw_signals_panel(self, draw: ImageDraw.Draw, pb: Dict, y: int) -> int:
        _section_label(draw, "ALL 7 SIGNALS", y)
        y += 30

        signals = pb.get("signals", {})
        premarket_bias = pb.get("premarket_bias", "—")

        rows = [
            ("P  SPY Component", premarket_bias),
            ("1  iToD",          _sig_bias(signals, "iToD")),
            ("2  Optimized ToD", _sig_bias(signals, "optimized_tod")),
            ("3  ToD / Gap",     _sig_bias(signals, "tod_gap")),
            ("4  DPL",           _dpl_label(signals.get("dpl", {}))),
            ("5  AD 6.5",        _sig_bias(signals, "ad_6_5")),
            ("6  DOM / Gap",     _sig_bias(signals, "dom_gap")),
        ]

        for label, value in rows:
            color = _bias_color(value)
            _kv_row(draw, label, value, y, value_color=color)
            y += 34
        return y + 10

    def _draw_algorithm_panel(self, draw: ImageDraw.Draw, pb: Dict, phase: str, y: int) -> int:
        rec   = pb.get("recommendation", "WAIT" if phase == "premarket" else "—")
        step  = pb.get("algorithm_step")
        reason = pb.get("reason", "")

        bg_color = {
            "GO_LONG":  (20, 50, 30),
            "GO_SHORT": (50, 20, 20),
        }.get(rec, (30, 30, 20))

        draw.rectangle([20, y, W - 20, y + 130], fill=bg_color, outline=BORDER, width=1)

        label_color = {
            "GO_LONG":  GREEN,
            "GO_SHORT": RED,
            "WAIT":     YELLOW,
        }.get(rec, TEXT_MUTED)

        arrow = "▲" if rec == "GO_LONG" else ("▼" if rec == "GO_SHORT" else "⏸")
        _text(draw, f"{arrow}  {rec}", (40, y + 15), label_color, 26, bold=True)
        if step:
            _text(draw, f"Step {step}", (W - 120, y + 18), TEXT_MUTED, 16)
        if reason:
            _wrap_text(draw, reason, 40, y + 52, W - 80, TEXT_WHITE, 15, max_lines=3)
        return y + 145

    def _draw_minute14_panel(self, draw: ImageDraw.Draw, pb: Dict, y: int) -> int:
        _section_label(draw, "MINUTE-14 REFERENCE", y)
        y += 30
        _kv_row(draw, "Min-14 High",     f"{pb.get('min14_high', 0):,.2f}", y)
        y += 34
        _kv_row(draw, "Min-14 Low",      f"{pb.get('min14_low', 0):,.2f}", y)
        y += 34
        _kv_row(draw, "OTM Long Strike", f"{pb.get('otm_long_strike', '—')}", y, value_color=GREEN)
        y += 34
        _kv_row(draw, "OTM Short Strike",f"{pb.get('otm_short_strike', '—')}", y, value_color=RED)
        return y + 20

    def _draw_refresh_panel(self, draw: ImageDraw.Draw, pb: Dict, y: int) -> int:
        dpl_live = pb.get("dpl_live") or {}
        _section_label(draw, "LIVE DPL", y)
        y += 30
        dpl_dir = dpl_live.get("direction", "—").upper()
        dpl_col = GREEN if "long" in dpl_dir.lower() else (RED if "short" in dpl_dir.lower() else TEXT_MUTED)
        _kv_row(draw, "DPL Direction",  dpl_dir, y, value_color=dpl_col)
        y += 34
        _kv_row(draw, "Separation",     f"{dpl_live.get('separation', 0):+.3f}", y)
        y += 34
        _kv_row(draw, "Last Refreshed", pb.get("last_refreshed_at", "—")[:19], y)
        return y + 20

    def _draw_footer(self, draw: ImageDraw.Draw, pb: Dict, phase: str) -> None:
        footer_y = H - 50
        draw.rectangle([0, footer_y - 10, W, H], fill=(10, 10, 18))
        _text(draw, f"Phase: {phase.upper()}  •  schema_v{pb.get('schema_version',2)}  •  engine {pb.get('signal_engine_version','—')}",
              (20, footer_y), TEXT_MUTED, 14)

    # ─────────────────────────────────────────────────────────────────────────
    # GCS upload
    # ─────────────────────────────────────────────────────────────────────────

    def _upload(self, gcs_path: str, data: bytes) -> Optional[str]:
        try:
            bucket = self._gcs.bucket(self._bucket_name)
            blob   = bucket.blob(gcs_path)
            blob.upload_from_string(data, content_type="image/png")
            # Return public URL only if bucket is public; otherwise None
            try:
                return blob.public_url
            except Exception:
                return None
        except Exception as exc:
            logger.error("GCS upload failed for %s: %s", gcs_path, exc)
            raise


# ─── Drawing helpers ─────────────────────────────────────────────────────────

def _get_font(size: int, bold: bool = False):
    """Load system font with graceful fallback to PIL default."""
    candidates = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf" if bold else
        "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
    ]
    for path in candidates:
        try:
            return ImageFont.truetype(path, size)
        except Exception:
            pass
    return ImageFont.load_default()


def _text(draw, text, pos, color, size, bold=False):
    draw.text(pos, str(text), fill=color, font=_get_font(size, bold))


def _section_label(draw, label, y):
    draw.rectangle([0, y, W, y + 26], fill=(20, 24, 30))
    _text(draw, label, (20, y + 4), TEXT_MUTED, 13, bold=True)


def _kv_row(draw, label, value, y, value_color=TEXT_WHITE):
    _text(draw, label, (30,       y), TEXT_MUTED, 16)
    _text(draw, value, (W - 350,  y), value_color, 16, bold=True)


def _wrap_text(draw, text, x, y, max_width, color, size, max_lines=3):
    font  = _get_font(size)
    words = text.split()
    line  = ""
    lines = []
    for word in words:
        test = (line + " " + word).strip()
        if draw.textlength(test, font=font) <= max_width:
            line = test
        else:
            lines.append(line)
            line = word
        if len(lines) >= max_lines:
            break
    if line and len(lines) < max_lines:
        lines.append(line)
    for i, l in enumerate(lines):
        _text(draw, l, (x, y + i * (size + 4)), color, size)


def _sig_bias(signals: Dict, key: str) -> str:
    v = signals.get(key)
    if isinstance(v, dict):
        return v.get("bias", "—")
    return str(v or "—")


def _dpl_label(dpl: Dict) -> str:
    direction = dpl.get("direction", "NEUTRAL")
    color     = dpl.get("color", "grey")
    sep       = dpl.get("separation", 0)
    return f"{direction.upper()} ({color}, {sep:+.2f})"


def _bias_color(value: str) -> tuple:
    v = value.lower()
    if "bullish" in v or "long" in v or "go_long" in v:
        return GREEN
    if "bearish" in v or "short" in v or "go_short" in v:
        return RED
    if "wait" in v or "neutral" in v:
        return YELLOW
    return TEXT_WHITE
