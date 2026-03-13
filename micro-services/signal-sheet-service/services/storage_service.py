"""Artifact storage for rendered signal-sheet snapshots."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

from google.cloud import storage


@dataclass(frozen=True)
class ArtifactRef:
    storage_path: str
    public_url: str | None


class ArtifactStorage:
    def __init__(self):
        self._bucket_name = os.environ.get("SIGNAL_SHEET_ARTIFACT_BUCKET", "").strip()
        self._public_base_url = os.environ.get("SIGNAL_SHEET_ARTIFACT_PUBLIC_BASE_URL", "").strip()
        local_root = os.environ.get("SIGNAL_SHEET_LOCAL_ARTIFACT_ROOT", "/tmp/signal-sheet-artifacts")
        self._local_root = Path(local_root)
        self._client = storage.Client() if self._bucket_name else None

    def write_png(self, market_date: str, phase: str, image_bytes: bytes) -> ArtifactRef:
        object_name = f"signal-sheet/{market_date}/{phase}.png"
        if self._client and self._bucket_name:
            bucket = self._client.bucket(self._bucket_name)
            blob = bucket.blob(object_name)
            blob.upload_from_string(image_bytes, content_type="image/png")
            public_url = None
            if self._public_base_url:
                public_url = f"{self._public_base_url.rstrip('/')}/{object_name}"
            return ArtifactRef(
                storage_path=f"gs://{self._bucket_name}/{object_name}",
                public_url=public_url,
            )

        path = self._local_root / "signal-sheet" / market_date / f"{phase}.png"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(image_bytes)
        return ArtifactRef(storage_path=str(path), public_url=None)
