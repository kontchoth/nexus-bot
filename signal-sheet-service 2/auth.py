"""
NexusBot — OIDC Auth for Cloud Scheduler → Cloud Run
Validates that every inbound request came from an authorised Cloud Scheduler
service account.

Spec requirements (section 16):
  - bearer token must be present
  - issuer must be accounts.google.com
  - audience must equal the deployed Cloud Run service URL
  - email/principal must match the approved scheduler service account
  - generic token validation without audience checking is NOT enough

Usage:
    from auth import require_scheduler_auth
    @app.post("/generate")
    async def generate(request: Request):
        require_scheduler_auth(request)   # raises HTTPException on failure
        ...
"""
from __future__ import annotations

import logging
import os
from functools import lru_cache

import httpx
from fastapi import HTTPException, Request
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token

logger = logging.getLogger(__name__)

# ─── Config (set via Cloud Run env vars) ─────────────────────────────────────
# SERVICE_URL  → full Cloud Run URL, e.g. https://signal-sheet-service-xxx.run.app
# SCHEDULER_SA → e.g. signal-sheet-scheduler@my-project.iam.gserviceaccount.com
_SERVICE_URL    = os.environ.get("SERVICE_URL", "")
_SCHEDULER_SA   = os.environ.get("SCHEDULER_SA", "")
_SKIP_AUTH      = os.environ.get("SKIP_AUTH", "false").lower() == "true"  # dev only


def require_scheduler_auth(request: Request) -> None:
    """
    Verify the OIDC token from Cloud Scheduler.
    Raises HTTP 401 on any failure.
    """
    if _SKIP_AUTH:
        logger.warning("SKIP_AUTH=true — skipping OIDC verification (dev mode only)")
        return

    auth_header = request.headers.get("Authorization", "")
    if not auth_header.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")

    token = auth_header.removeprefix("Bearer ").strip()

    try:
        claims = id_token.verify_oauth2_token(
            token,
            google_requests.Request(),
            audience=_SERVICE_URL,
        )
    except Exception as exc:
        logger.warning("OIDC verification failed: %s", exc)
        raise HTTPException(status_code=401, detail="Invalid OIDC token") from exc

    # Verify issuer
    issuer = claims.get("iss", "")
    if issuer not in ("accounts.google.com", "https://accounts.google.com"):
        raise HTTPException(status_code=401, detail=f"Unexpected issuer: {issuer}")

    # Verify caller identity
    if _SCHEDULER_SA:
        email = claims.get("email", "")
        if email != _SCHEDULER_SA:
            logger.warning("Caller %s is not approved scheduler SA %s", email, _SCHEDULER_SA)
            raise HTTPException(status_code=403, detail="Caller not authorised")

    logger.debug("OIDC verified: %s", claims.get("email"))
