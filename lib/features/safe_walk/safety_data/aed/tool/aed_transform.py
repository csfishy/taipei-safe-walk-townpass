"""Pure mapping: data.taipei AED rows -> normalized AssistancePoint JSON.

Mirror of ../aed_normalizer.dart; test/features/safe_walk/safety_data/aed/
compares both on the same real sample. Change both together.
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any, Optional

TAIPEI_TZ = timezone(timedelta(hours=8))
DATASET_ID = "cd050577-115f-4299-b37a-012ff490a632"
RESOURCE_ID = "438c61ad-24f6-4e54-a1cc-e2cfe0e7051e"
DATASET_PAGE_URL = f"https://data.taipei/dataset/detail?id={DATASET_ID}"

DISTRICTS = {
    "63000010": "松山區", "63000020": "信義區", "63000030": "大安區", "63000040": "中山區",
    "63000050": "中正區", "63000060": "大同區", "63000070": "萬華區", "63000080": "文山區",
    "63000090": "南港區", "63000100": "內湖區", "63000110": "士林區", "63000120": "北投區",
}
LAT_RANGE = (24.95, 25.22)
LNG_RANGE = (121.45, 121.67)

LIMITATIONS = [
    "只表示衛生局登錄的AED設置地點，不代表AED此刻可取用、場所開放或有人可提供協助。",
    "來源未提供開放時間；許多AED位於建築物內，需依場所開放時間進入。",
    "座標為來源提供，未經實地核對；同一場所可能有多台AED，各自為一筆。",
    "AED設置地點不是警察或官方合作求助據點，不構成安全保證。",
]


@dataclass(frozen=True)
class SourceInfo:
    retrieved_at: str                      # already formatted with +08:00
    resource_last_modified: Optional[str]  # data.taipei value, Asia/Taipei local time
    license_name: Optional[str]


def clean(value: Any) -> str:
    return re.sub(r"\s+", " ", "" if value is None else str(value)).strip()


def format_taipei_time(dt: datetime) -> str:
    if dt.tzinfo is None:
        raise ValueError("datetime must be timezone-aware")
    return dt.astimezone(TAIPEI_TZ).replace(microsecond=0).isoformat()


def platform_time_to_iso(value: Optional[str]) -> Optional[str]:
    if value is None:
        return None
    m = re.fullmatch(r"(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2}:\d{2})", value.strip())
    return f"{m.group(1)}T{m.group(2)}+08:00" if m else None


def normalize_license(name: Optional[str]) -> Optional[str]:
    name = clean(name)
    if "政府資料開放授權條款" not in name:
        return None
    return name[1:] if name.startswith("依") else name


def make_address(raw: str, district: Optional[str]) -> Optional[str]:
    addr = clean(raw)
    if not addr:
        return None
    addr = re.sub(r"^台北市", "臺北市", addr)
    if addr.startswith("臺北市"):
        full = addr
    elif district and addr.startswith(district):
        full = "臺北市" + addr
    else:
        full = "臺北市" + (district or "") + addr
    return full[:400]


def make_name(site: str, placement: str) -> str:
    site, placement = clean(site), clean(placement)
    return (f"{site}（AED：{placement}）" if placement and placement != site else site)[:200]


def build_source(info: SourceInfo) -> dict[str, Any]:
    return {
        "datasetId": f"data.taipei:{DATASET_ID}/{RESOURCE_ID}",
        "title": "臺北市AED自動體外心臟去顫器設置地點（臺北市政府衛生局）",
        "dataMode": "live",
        "sourceUrl": DATASET_PAGE_URL,
        "retrievedAt": info.retrieved_at,
        "dataUpdatedAt": platform_time_to_iso(info.resource_last_modified),
        "license": normalize_license(info.license_name),
        "coverage": "臺北市12行政區；臺北市政府衛生局登錄之AED設置場所",
        "limitations": list(LIMITATIONS),
    }


def _row_id(row: dict[str, Any]) -> int:
    value = row.get("_id")
    if isinstance(value, int):
        return value
    try:
        return int(clean(value))
    except ValueError:
        return 0


def _in_range(text: str, lo_hi: tuple[float, float]) -> Optional[float]:
    try:
        value = float(text)
    except ValueError:
        return None
    return value if lo_hi[0] <= value <= lo_hi[1] else None  # NaN fails both comparisons


def transform(rows: list[dict[str, Any]], info: SourceInfo) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    """(normalized points, rejected rows). Ids: tpe-aed-<區域代碼>-<緯度>-<經度>-<n>."""
    source = build_source(info)
    rejected: list[dict[str, Any]] = []
    accepted = []
    for row in rows:
        rid = _row_id(row)
        site = clean(row.get("場所名稱"))
        if not site:
            rejected.append({"rowId": rid, "reason": "missing 場所名稱"})
            continue
        lat, lng = clean(row.get("緯度")), clean(row.get("經度"))
        lat_v, lng_v = _in_range(lat, LAT_RANGE), _in_range(lng, LNG_RANGE)
        if lat_v is None or lng_v is None:
            rejected.append({"rowId": rid, "reason": "unparsable or out-of-Taipei coordinates"})
            continue
        key = (clean(row.get("區域代碼")), lat, lng, site, clean(row.get("場所地址")),
               clean(row.get("aed放置地點")), clean(row.get("aed地點描述")))
        accepted.append((key, rid, row, lat_v, lng_v))
    accepted.sort(key=lambda a: (a[0], a[1]))
    ordinals: dict[str, int] = {}
    points = []
    for key, _rid, row, lat_v, lng_v in accepted:
        code, lat, lng, site = key[0], key[1], key[2], key[3]
        base = f"tpe-aed-{code or 'unknown'}-{lat}-{lng}"
        ordinals[base] = ordinals.get(base, 0) + 1
        district = DISTRICTS.get(code)
        points.append({
            "schemaVersion": "1.0.0",
            "id": f"{base}-{ordinals[base]}"[:120],
            "name": make_name(site, clean(row.get("aed放置地點"))),
            "kind": "public_facility",
            "coordinates": {"lat": lat_v, "lng": lng_v},
            "address": make_address(clean(row.get("場所地址")), district),
            "publicPhone": None,
            "recognition": {"status": "not_applicable", "evidenceUrl": None, "checkedAt": None},
            "availability": "unknown",
            "availabilityCheckedAt": None,
            "capabilities": ["unknown"],
            "source": source,
        })
    rejected.sort(key=lambda r: r["rowId"])
    return points, rejected
