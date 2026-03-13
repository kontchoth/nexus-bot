"""PNG snapshot rendering for daily signal-sheet playbooks."""

from __future__ import annotations

import io
import textwrap
from dataclasses import dataclass
from datetime import datetime

from PIL import Image, ImageDraw, ImageFont

PHASES = {"premarket", "locked", "final"}
TEMPLATE_VERSION = "pillow-v1"
WIDTH = 1600
HEIGHT = 1100

_BG = "#050914"
_PANEL = "#101827"
_BORDER = "#1f2a3c"
_TEXT = "#e7edf5"
_MUTED = "#8ea3bb"
_ACCENT = "#f0b24a"
_GREEN = "#28c76f"
_RED = "#f25555"
_BLUE = "#5ea8ff"
_YELLOW = "#f6c760"


@dataclass(frozen=True)
class RenderResult:
    image_bytes: bytes
    width: int
    height: int
    template_version: str


class RenderService:
    def phase_readiness(self, playbook: dict, phase: str) -> tuple[bool, str | None]:
        if phase not in PHASES:
            return False, "unsupported_phase"
        if not playbook.get("generated_at"):
            return False, "playbook_not_generated"
        if phase == "premarket":
            return True, None
        if playbook.get("min14_high") is None or playbook.get("min14_low") is None:
            return False, "minute14_not_locked"
        if phase == "locked":
            return True, None
        if playbook.get("last_refreshed_at") is None:
            return False, "no_live_refresh"
        return True, None

    def render(self, playbook: dict, phase: str) -> RenderResult:
        image = Image.new("RGB", (WIDTH, HEIGHT), _BG)
        draw = ImageDraw.Draw(image)

        fonts = _Fonts()
        self._draw_header(draw, fonts, playbook, phase)
        self._draw_kpis(draw, fonts, playbook)
        self._draw_signals(draw, fonts, playbook)
        self._draw_decision(draw, fonts, playbook)
        self._draw_reference(draw, fonts, playbook, phase)
        self._draw_footer(draw, fonts, playbook, phase)

        buffer = io.BytesIO()
        image.save(buffer, format="PNG", optimize=True)
        return RenderResult(
            image_bytes=buffer.getvalue(),
            width=WIDTH,
            height=HEIGHT,
            template_version=TEMPLATE_VERSION,
        )

    def _draw_header(self, draw: ImageDraw.ImageDraw, fonts: "_Fonts", playbook: dict, phase: str) -> None:
        title = f"NexusBot / {playbook.get('symbol', 'SPX')} Daily Signal Sheet"
        date_label = playbook.get("date", "--")
        phase_label = phase.upper()
        draw.text((48, 34), title, font=fonts.title, fill=_TEXT)
        draw.text((48, 78), date_label, font=fonts.meta, fill=_ACCENT)
        draw.text((1288, 42), f"PHASE  {phase_label}", font=fonts.meta, fill=_MUTED)

    def _draw_kpis(self, draw: ImageDraw.ImageDraw, fonts: "_Fonts", playbook: dict) -> None:
        cards = [
            ("Prev Close", _fmt_num(playbook.get("yesterday_close")), _TEXT),
            (
                "Net GEX / Flip",
                f"{_fmt_compact(playbook.get('net_gex'))} / {_fmt_num(playbook.get('flip_level'), 0)}",
                _BLUE,
            ),
            ("Regime", str(playbook.get("regime") or "--"), _TEXT),
            ("Gamma Wall", _fmt_num(playbook.get("gamma_wall"), 0), _TEXT),
            ("Put Wall", _fmt_num(playbook.get("put_wall"), 0), _TEXT),
            ("Range Est.", _fmt_points(playbook.get("spx_range_est")), _BLUE),
        ]
        x = 48
        y = 120
        w = 240
        h = 112
        gap = 18
        for index, (label, value, color) in enumerate(cards):
            self._panel(draw, x + index * (w + gap), y, w, h, label, [value], fonts, value_color=color)

    def _draw_signals(self, draw: ImageDraw.ImageDraw, fonts: "_Fonts", playbook: dict) -> None:
        signals = playbook.get("signals") or {}
        rows = []
        ordered = [
            ("spy_component", "Premarket"),
            ("iToD", "iToD"),
            ("optimized_tod", "Optimized ToD"),
            ("tod_gap", "ToD / Gap"),
            ("dpl", "DPL"),
            ("ad_6_5", "AD 6.5"),
            ("dom_gap", "DOM / Gap"),
        ]
        for key, label in ordered:
            value = signals.get(key) or {}
            rows.append(f"{label}: {_signal_label(value)}")
        self._panel(draw, 48, 264, 430, 360, "All 7 Signals", rows, fonts)

    def _draw_decision(self, draw: ImageDraw.ImageDraw, fonts: "_Fonts", playbook: dict) -> None:
        recommendation = playbook.get("recommendation") or "WAIT"
        color = _recommendation_color(recommendation)
        reason = playbook.get("reason") or "Awaiting market decision context."
        algorithm_step = playbook.get("algorithm_step")
        headline = f"{recommendation.replace('_', ' ')}"
        lines = [
            f"Algorithm step: {algorithm_step if algorithm_step is not None else '--'}",
            f"Signal unity: {_fmt_bool(playbook.get('signal_unity'))}",
            "",
            "Reason:",
        ]
        lines.extend(_wrap(reason, width=46))
        self._panel(
            draw,
            510,
            264,
            520,
            360,
            "Decision State",
            [headline, ""] + lines,
            fonts,
            accent=color,
            value_color=color,
        )

    def _draw_reference(self, draw: ImageDraw.ImageDraw, fonts: "_Fonts", playbook: dict, phase: str) -> None:
        left_lines = [
            f"Premarket bias: {playbook.get('premarket_bias') or '--'}",
            f"Premarket price: {_fmt_num(playbook.get('premarket_price'))}",
            f"Official open: {_fmt_num(playbook.get('official_open'))}",
            f"DPL live: {_dpl_label(playbook.get('dpl_live'))}",
            f"Last refresh: {_fmt_timestamp(playbook.get('last_refreshed_at'))}",
        ]
        self._panel(draw, 1062, 264, 490, 210, "Session Context", left_lines, fonts)

        if phase == "premarket":
            ref_lines = [
                "Minute-14 lock not available before market open.",
                "OTM references will populate after 09:44 ET.",
            ]
        else:
            ref_lines = [
                f"Min-14 High: {_fmt_num(playbook.get('min14_high'))}",
                f"Min-14 Low: {_fmt_num(playbook.get('min14_low'))}",
                f"OTM Long Strike: {_fmt_num(playbook.get('otm_long_strike'), 0)}",
                f"OTM Short Strike: {_fmt_num(playbook.get('otm_short_strike'), 0)}",
            ]
        self._panel(draw, 1062, 496, 490, 128, "Reference Levels", ref_lines, fonts, accent=_YELLOW)

    def _draw_footer(self, draw: ImageDraw.ImageDraw, fonts: "_Fonts", playbook: dict, phase: str) -> None:
        summary_lines = [
            f"Status: {str(playbook.get('status') or '--').upper()}",
            f"Template: {TEMPLATE_VERSION}",
            f"Phase artifact: {phase}",
        ]
        screenshots = playbook.get("screenshots") or {}
        if screenshots:
            available = ", ".join(sorted(screenshots.keys()))
            summary_lines.append(f"Existing artifacts: {available}")
        self._panel(draw, 48, 656, 1504, 172, "Artifact Summary", summary_lines, fonts)

    def _panel(
        self,
        draw: ImageDraw.ImageDraw,
        x: int,
        y: int,
        w: int,
        h: int,
        title: str,
        lines: list[str],
        fonts: "_Fonts",
        *,
        accent: str = _BORDER,
        value_color: str = _TEXT,
    ) -> None:
        draw.rounded_rectangle((x, y, x + w, y + h), radius=16, fill=_PANEL, outline=accent, width=2)
        draw.text((x + 20, y + 16), title.upper(), font=fonts.label, fill=_ACCENT)
        cursor_y = y + 52
        for index, line in enumerate(lines):
            if line == "":
                cursor_y += 10
                continue
            color = value_color if index == 0 else _TEXT
            wrapped = _wrap(line, width=max(18, int(w / 12)))
            for part in wrapped:
                draw.text((x + 20, cursor_y), part, font=fonts.body, fill=color)
                cursor_y += 26
                if cursor_y > y + h - 20:
                    return


class _Fonts:
    def __init__(self):
        self.title = _load_font(42, bold=True)
        self.meta = _load_font(18, bold=False)
        self.label = _load_font(18, bold=True)
        self.body = _load_font(24, bold=False)


def _load_font(size: int, *, bold: bool) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        "DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    ]
    for candidate in candidates:
        try:
            return ImageFont.truetype(candidate, size=size)
        except OSError:
            continue
    return ImageFont.load_default()


def _wrap(text: str, width: int) -> list[str]:
    return textwrap.wrap(str(text), width=width) or [str(text)]


def _fmt_num(value: object, decimals: int = 2) -> str:
    if value is None:
        return "--"
    try:
        number = float(value)
    except (TypeError, ValueError):
        return str(value)
    return f"{number:,.{decimals}f}"


def _fmt_points(value: object) -> str:
    if value is None:
        return "--"
    try:
        return f"{float(value):,.1f} pts"
    except (TypeError, ValueError):
        return str(value)


def _fmt_bool(value: object) -> str:
    if value is None:
        return "--"
    return "YES" if bool(value) else "NO"


def _fmt_compact(value: object) -> str:
    if value is None:
        return "--"
    try:
        number = float(value)
    except (TypeError, ValueError):
        return str(value)
    sign = "-" if number < 0 else ""
    number = abs(number)
    if number >= 1_000_000_000:
        return f"{sign}{number / 1_000_000_000:.2f}B"
    if number >= 1_000_000:
        return f"{sign}{number / 1_000_000:.2f}M"
    if number >= 1_000:
        return f"{sign}{number / 1_000:.2f}K"
    return f"{sign}{number:.0f}"


def _fmt_timestamp(value: object) -> str:
    if not value:
        return "--"
    try:
        parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        return parsed.strftime("%H:%M:%S UTC")
    except ValueError:
        return str(value)


def _signal_label(signal: dict) -> str:
    if "direction" in signal:
        return str(signal.get("direction") or "NEUTRAL")
    return str(signal.get("bias") or "neutral").upper()


def _dpl_label(signal: dict | None) -> str:
    if not signal:
        return "--"
    direction = signal.get("direction") or "NEUTRAL"
    separation = signal.get("separation")
    if separation is None:
        return str(direction)
    return f"{direction} ({float(separation):.4f})"


def _recommendation_color(recommendation: str) -> str:
    if recommendation == "GO_LONG":
        return _GREEN
    if recommendation == "GO_SHORT":
        return _RED
    return _YELLOW
