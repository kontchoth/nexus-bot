"""Firestore read/write for daily playbooks."""

import os
from google.cloud import firestore

_COLLECTION = os.environ.get("FIRESTORE_COLLECTION", "playbooks")


class PlaybookWriter:
    def __init__(self):
        self._db  = firestore.AsyncClient()
        self._col = self._db.collection(_COLLECTION)

    async def write(self, playbook: dict) -> None:
        today = playbook["date"]
        await self._col.document(today).set(playbook)

    async def upsert(self, date: str, fields: dict) -> None:
        await self._col.document(date).set(fields, merge=True)

    async def update(self, date: str, fields: dict) -> None:
        await self._col.document(date).update(fields)

    async def get(self, date: str) -> dict | None:
        doc = await self._col.document(date).get()
        if not doc.exists:
            return None
        return doc.to_dict()

    async def get_today(self, date: str) -> dict:
        playbook = await self.get(date)
        if playbook is None:
            raise ValueError(f"No playbook found for {date}")
        return playbook

    async def exists(self, date: str) -> bool:
        doc = await self._col.document(date).get()
        return doc.exists
