"""Offline tool: fetch the Taipei AED dataset from data.taipei (network only, no transformation).

The app itself reads the source through DataTaipeiAedRepository (Dart); this mirrors it for
snapshots and fixture regeneration. Not a backend.
"""
from __future__ import annotations

import json
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any, Optional

TAIPEI_TZ = timezone(timedelta(hours=8))

DATASET_ID = "cd050577-115f-4299-b37a-012ff490a632"
RESOURCE_ID = "438c61ad-24f6-4e54-a1cc-e2cfe0e7051e"
DATASET_PAGE_URL = f"https://data.taipei/dataset/detail?id={DATASET_ID}"
METADATA_URL = f"https://data.taipei/api/frontstage/tpeod/dataset.view?id={DATASET_ID}"
ROWS_URL = "https://data.taipei/api/v1/dataset/{rid}?scope=resourceAquire&limit={limit}&offset={offset}"
PAGE_SIZE = 1000  # data.taipei caps one request at 1000 rows
USER_AGENT = "taipei-safe-walk-m4-tool/0.1"


class SourceUnavailable(Exception):
    """The source could not be read completely. Callers must not substitute demo data."""


@dataclass(frozen=True)
class RawSnapshot:
    rows: list[dict[str, Any]]
    retrieved_at: datetime              # when we read it (not when the city updated it)
    resource_last_modified: Optional[str]  # platform value, e.g. "2026-09-04 18:15:48"; None if metadata failed
    license_name: Optional[str]         # platform value, e.g. "依政府資料開放授權條款-第1版"


def _get_json(url: str, timeout: float, retries: int) -> Any:
    last_error: Exception | None = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return json.loads(resp.read().decode("utf-8-sig"))
        except (urllib.error.URLError, TimeoutError, OSError, json.JSONDecodeError) as exc:
            last_error = exc
            if attempt + 1 < retries:
                time.sleep(2 * (attempt + 1))  # data.taipei handshakes time out intermittently
    raise SourceUnavailable(f"GET {url} failed after {retries} attempts: {last_error}")


def _fetch_metadata(timeout: float, retries: int) -> tuple[Optional[str], Optional[str]]:
    """Resource update time and license. Failure is tolerated: both become None (unknown)."""
    try:
        payload = _get_json(METADATA_URL, timeout, retries)["payload"]
    except (SourceUnavailable, KeyError, TypeError):
        return None, None
    modified = None
    for res in payload.get("resources") or []:
        if res.get("rid") == RESOURCE_ID:
            modified = res.get("last_modified") or None
    return modified, payload.get("license_name") or None


def fetch_snapshot(timeout: float = 60, retries: int = 3) -> RawSnapshot:
    retrieved_at = datetime.now(TAIPEI_TZ).replace(microsecond=0)
    rows: list[dict[str, Any]] = []
    expected: Optional[int] = None
    offset = 0
    while True:
        url = ROWS_URL.format(rid=RESOURCE_ID, limit=PAGE_SIZE, offset=offset)
        try:
            result = _get_json(url, timeout, retries)["result"]
            page = result["results"]
            expected = int(result["count"])
        except (KeyError, TypeError, ValueError) as exc:
            raise SourceUnavailable(f"Unexpected response shape from {url}: {exc}") from exc
        rows.extend(page)
        offset += PAGE_SIZE
        if not page or len(rows) >= expected:
            break
    if expected is None or len(rows) != expected:
        raise SourceUnavailable(f"Incomplete read: got {len(rows)} rows, source reports {expected}")
    modified, license_name = _fetch_metadata(timeout, retries)
    return RawSnapshot(rows, retrieved_at, modified, license_name)
