"""
NexusBot — Firestore Playbook Writer
Idempotent upserts for playbooks/{market_date}.

Rules (spec section 10):
  - document id = ET market date (YYYY-MM-DD)
  - all writes are idempotent upserts using merge=True
  - min14_* fields are immutable once written — writer enforces this
  - raw options chains / full bar arrays are never stored in the top-level doc
  - screenshot metadata is stored here; binaries go to GCS
"""
from __future__ import annotations

import logging
from datetime import datetime
from typing import Any, Dict, Optional

from google.cloud import firestore

logger = logging.getLogger(__name__)

COLLECTION = "playbooks"
SCHEMA_VERSION = 2


class PlaybookWriter:
    def __init__(self, db: Optional[firestore.AsyncClient] = None):
        self._db = db or firestore.AsyncClient()

    def _doc_ref(self, market_date: str) -> firestore.AsyncDocumentReference:
        return self._db.collection(COLLECTION).document(market_date)

    # ─────────────────────────────────────────────────────────────────────────
    # /generate → premarket snapshot
    # ─────────────────────────────────────────────────────────────────────────

    async def write_premarket(
        self,
        market_date:    str,
        payload:        Dict[str, Any],
        signal_version: str = "v2",
        display_date:   Optional[str] = None,
    ) -> None:
        doc = self._doc_ref(market_date)
        data = {
            # Meta
            "date":                   display_date or market_date,
            "symbol":                 "SPX",
            "schema_version":         SCHEMA_VERSION,
            "signal_engine_version":  signal_version,
            "generated_at":           _utcnow(),
            "status":                 "premarket",

            # Source mode
            "source_symbol":  payload.get("source_symbol", "SPX"),
            "source_mode":    payload.get("source_mode", "direct"),

            # Session reference
            "yesterday_close":  payload["yesterday_close"],
            "premarket_price":  payload["premarket_price"],
            "premarket_bias":   payload["premarket_bias"],

            # GEX
            "net_gex":       payload["net_gex"],
            "flip_level":    payload["flip_level"],
            "gamma_wall":    payload["gamma_wall"],
            "put_wall":      payload["put_wall"],
            "regime":        payload["regime"],

            # Walls + range
            "wall_rally":    payload.get("wall_rally", []),
            "wall_drop":     payload.get("wall_drop", []),
            "spx_range_est": payload["spx_range_est"],

            # 7 Signals
            "signals": payload["signals"],

            # DPL live (initial premarket read)
            "dpl_live": payload.get("dpl_live"),

            # Null placeholders for later phases
            "official_open":     None,
            "algorithm_step":    None,
            "recommendation":    None,
            "signal_unity":      None,
            "reason":            None,
            "min14_high":        None,
            "min14_low":         None,
            "otm_long_strike":   None,
            "otm_short_strike":  None,
            "last_refreshed_at": None,
        }
        await doc.set(data, merge=True)
        logger.info("Wrote premarket playbook %s", market_date)

    # ─────────────────────────────────────────────────────────────────────────
    # /resolve → opening algorithm decision
    # ─────────────────────────────────────────────────────────────────────────

    async def write_open_decision(
        self,
        market_date:    str,
        official_open:  float,
        algorithm_step: int,
        recommendation: str,
        signal_unity:   bool,
        reason:         str,
    ) -> None:
        doc = self._doc_ref(market_date)
        await doc.update({
            "official_open":    official_open,
            "algorithm_step":   algorithm_step,
            "recommendation":   recommendation,
            "signal_unity":     signal_unity,
            "reason":           reason,
            "status":           "open",
            "last_refreshed_at": _utcnow(),
        })
        logger.info("Wrote open decision %s: %s (step %d)", market_date, recommendation, algorithm_step)

    # ─────────────────────────────────────────────────────────────────────────
    # /lock-minute14 → immutable min14 lock
    # ─────────────────────────────────────────────────────────────────────────

    async def write_minute14_lock(
        self,
        market_date:    str,
        min14_high:     float,
        min14_low:      float,
    ) -> None:
        doc     = self._doc_ref(market_date)
        snap    = await doc.get()

        # Enforce immutability — never overwrite once set
        if snap.exists:
            existing = snap.to_dict() or {}
            if existing.get("min14_high") is not None:
                logger.warning(
                    "min14 already locked for %s (%s / %s) — skipping",
                    market_date, existing["min14_high"], existing["min14_low"],
                )
                return

        otm_long  = round(min14_low  - 50)
        otm_short = round(min14_high + 50)

        await doc.update({
            "min14_high":      min14_high,
            "min14_low":       min14_low,
            "otm_long_strike": otm_long,
            "otm_short_strike": otm_short,
            "status":          "locked",
        })
        logger.info(
            "Locked min14 for %s: H=%.2f L=%.2f OTM_L=%d OTM_S=%d",
            market_date, min14_high, min14_low, otm_long, otm_short,
        )

    # ─────────────────────────────────────────────────────────────────────────
    # /refresh → live DPL + optional recommendation upgrade
    # ─────────────────────────────────────────────────────────────────────────

    async def write_refresh(
        self,
        market_date:        str,
        dpl_live:           Dict[str, Any],
        live_session_high:  Optional[float] = None,
        live_session_low:   Optional[float] = None,
        recommendation:     Optional[str]   = None,
        reason:             Optional[str]   = None,
        algorithm_step:     Optional[int]   = None,
    ) -> None:
        update: Dict[str, Any] = {
            "dpl_live":          dpl_live,
            "last_refreshed_at": _utcnow(),
        }
        if live_session_high is not None:
            update["live_session_high"] = live_session_high
        if live_session_low is not None:
            update["live_session_low"] = live_session_low
        # Only upgrade recommendation if explicitly provided (WAIT → GO_LONG/GO_SHORT)
        if recommendation is not None:
            update["recommendation"] = recommendation
            update["reason"]         = reason
            if algorithm_step is not None:
                update["algorithm_step"] = algorithm_step

        await self._doc_ref(market_date).update(update)
        logger.info("Refreshed playbook %s dpl=%s rec=%s",
                    market_date, dpl_live.get("direction"), recommendation)

    # ─────────────────────────────────────────────────────────────────────────
    # /render-snapshot → write screenshot metadata
    # ─────────────────────────────────────────────────────────────────────────

    async def write_screenshot_metadata(
        self,
        market_date:      str,
        phase:            str,           # premarket | locked | final
        storage_path:     str,
        public_url:       Optional[str],
        width:            int,
        height:           int,
        template_version: str,
    ) -> None:
        artifact = {
            "phase":            phase,
            "generated_at":     _utcnow(),
            "storage_path":     storage_path,
            "public_url":       public_url,
            "width":            width,
            "height":           height,
            "template_version": template_version,
        }
        await self._doc_ref(market_date).update({
            f"screenshots.{phase}": artifact,
        })
        logger.info("Wrote screenshot metadata %s/%s → %s", market_date, phase, storage_path)

    # ─────────────────────────────────────────────────────────────────────────
    # Read helpers
    # ─────────────────────────────────────────────────────────────────────────

    async def delete_playbook(self, market_date: str) -> None:
        """Hard-delete a playbook document. Used by /replay with force=True."""
        await self._doc_ref(market_date).delete()
        logger.info("Deleted playbook %s", market_date)

    async def get_playbook(self, market_date: str) -> Optional[Dict[str, Any]]:
        snap = await self._doc_ref(market_date).get()
        return snap.to_dict() if snap.exists else None

    async def exists(self, market_date: str) -> bool:
        snap = await self._doc_ref(market_date).get()
        return snap.exists


# ─── helpers ─────────────────────────────────────────────────────────────────

def _utcnow() -> str:
    return datetime.utcnow().isoformat() + "Z"
