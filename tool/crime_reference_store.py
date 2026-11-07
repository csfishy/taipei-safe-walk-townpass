"""Explicit offline import; query/export open the external crime store read-only.

No command is wired to an App startup, build, deployment, seed or Demo reset.
The only writer creates a NEW snapshot and refuses CI or an existing destination.
"""
from __future__ import annotations

import argparse
from contextlib import closing
from datetime import date
import hashlib
import json
import math
import os
from pathlib import Path
import sqlite3
import sys
from urllib.parse import urlparse

CITIES = ("臺北市", "新北市", "基隆市")
SCHEMA = """
PRAGMA foreign_keys = ON;
CREATE TABLE metadata (key TEXT PRIMARY KEY, value_json TEXT NOT NULL);
CREATE TABLE sources (id TEXT PRIMARY KEY, name TEXT NOT NULL, url TEXT NOT NULL, payload_json TEXT NOT NULL);
CREATE TABLE crime_records (
    id TEXT PRIMARY KEY,
    source_id TEXT NOT NULL REFERENCES sources(id),
    city TEXT NOT NULL CHECK(city IN ('臺北市','新北市','基隆市')),
    district TEXT NOT NULL,
    category TEXT NOT NULL,
    event_date TEXT NOT NULL CHECK(event_date >= '2026-01-01' AND event_date <= '2026-11-07'),
    location_text TEXT NOT NULL,
    latitude REAL,
    longitude REAL,
    coordinate_status TEXT NOT NULL,
    spatial_precision TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    CHECK ((latitude IS NULL AND longitude IS NULL) OR
           (latitude IS NOT NULL AND longitude IS NOT NULL AND latitude BETWEEN -90 AND 90 AND longitude BETWEEN -180 AND 180)),
    CHECK (spatial_precision NOT IN ('district_only','blurred_text','unresolved') OR (latitude IS NULL AND longitude IS NULL))
);
CREATE INDEX crime_city_date ON crime_records(city, event_date);
CREATE INDEX crime_category_date ON crime_records(category, event_date);
CREATE INDEX crime_district ON crime_records(city, district);
CREATE INDEX crime_reference_coordinates ON crime_records(latitude, longitude) WHERE latitude IS NOT NULL;
PRAGMA user_version = 1;
"""


def encoded(value: object) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False)


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def outside_git(path: Path) -> Path:
    resolved = path.expanduser().resolve()
    if any((parent / ".git").exists() for parent in (resolved.parent, *resolved.parents)):
        raise ValueError("Crime database must be outside every Git checkout/worktree")
    return resolved


def validate(data: dict) -> None:
    if data.get("year") != 2026:
        raise ValueError("Expected the reviewed 2026 snapshot")
    sources = data.get("sources", [])
    source_ids = {s.get("sourceKey", s["datasetId"]) for s in sources}
    if len(source_ids) != len(sources):
        raise ValueError("Duplicate source IDs")
    ids = set()
    for record in data["records"]:
        if record["id"] in ids or record["sourceId"] not in source_ids:
            raise ValueError("Duplicate record or missing source provenance")
        ids.add(record["id"])
        if record["city"] not in CITIES:
            raise ValueError("Record outside Taipei/New Taipei/Keelung")
        if not date(2026, 1, 1) <= date.fromisoformat(record["date"]) <= date(2026, 11, 7):
            raise ValueError("Record outside snapshot date range")
        lat, lon = record.get("latitude"), record.get("longitude")
        if (lat is None) != (lon is None):
            raise ValueError("Incomplete coordinate pair")
        if lat is not None:
            if any(isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v) for v in (lat, lon)):
                raise ValueError("Invalid coordinate number")
            if not (24.5 <= lat <= 25.5 and 121.1 <= lon <= 122.1):
                raise ValueError("Reference coordinates outside the NNK envelope or reversed")
            if record["spatialPrecision"] in ("district_only", "blurred_text", "unresolved"):
                raise ValueError("Unresolved/district record cannot become a crime point")
            geo = record.get("geocoding") or {}
            if record["coordinateStatus"] == "reference_geocoded":
                if record["spatialPrecision"] not in ("public_place_reference", "road_segment_reference", "address_range_reference", "address_reference"):
                    raise ValueError("Unsupported reference precision")
                if not all(geo.get(k) for k in ("method", "sourceName", "sourceUrl", "verifiedAt", "precisionLabel", "confidence")):
                    raise ValueError("Geocoded reference missing evidence")
                if geo["confidence"] not in ("high", "medium") or urlparse(geo["sourceUrl"]).scheme != "https":
                    raise ValueError("Unverified geocoding confidence/source")
            if record["coordinateStatus"] not in ("reference_geocoded", "source_provided"):
                raise ValueError("Unverified coordinates")


def create_snapshot(path: Path, data: dict, *, allow_write: bool = False) -> dict:
    if not allow_write:
        raise ValueError("Import requires explicit --allow-write; query/export are read-only")
    if os.environ.get("GITHUB_ACTIONS", "").lower() == "true" or os.environ.get("CI", "").lower() in ("true", "1"):
        raise ValueError("Crime database import is forbidden in CI/build/deployment")
    path = outside_git(path)
    validate(data)
    path.parent.mkdir(parents=True, exist_ok=True)
    # Exclusive creation never truncates/replaces an existing database.
    with path.open("xb"):
        pass
    connection = None
    try:
        connection = sqlite3.connect(path)
        connection.executescript(SCHEMA)
        with connection:
            connection.executemany("INSERT INTO metadata VALUES (?, ?)", [(key, encoded(value)) for key, value in data.items() if key not in ("sources", "records")])
            connection.executemany("INSERT INTO sources VALUES (?, ?, ?, ?)", [(source.get("sourceKey", source["datasetId"]), source["name"], source["url"], encoded(source)) for source in data["sources"]])
            connection.executemany("INSERT INTO crime_records VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", [(
                r["id"], r["sourceId"], r["city"], r.get("district", ""), r["category"], r["date"], r.get("locationText", ""),
                r.get("latitude"), r.get("longitude"), r["coordinateStatus"], r["spatialPrecision"], encoded(r),
            ) for r in data["records"]])
        if connection.execute("PRAGMA integrity_check").fetchone()[0] != "ok" or connection.execute("PRAGMA foreign_key_check").fetchall():
            raise ValueError("Database integrity check failed")
        count = connection.execute("SELECT COUNT(*) FROM crime_records").fetchone()[0]
        assert count == len(data["records"])
        connection.close()
        connection = None
        path.chmod(0o444)
        return {"database": str(path), "records": count, "sha256": sha256(path), "readOnly": True}
    except BaseException:
        if connection is not None:
            connection.close()
        # Only our exclusively created, failed snapshot can be removed.
        path.unlink(missing_ok=True)
        raise


def connect_read_only(path: Path) -> sqlite3.Connection:
    path = outside_git(path)
    if not path.is_file():
        raise FileNotFoundError("Crime database does not exist; queries never create a database")
    connection = sqlite3.connect(path.as_uri() + "?mode=ro", uri=True)
    connection.execute("PRAGMA query_only=ON")
    if connection.execute("PRAGMA user_version").fetchone()[0] != 1:
        connection.close()
        raise ValueError("Unsupported crime database schema")
    return connection


def query(path: Path, *, city: str = "", category: str = "", text: str = "", limit: int = 100) -> list[dict]:
    if city and city not in CITIES:
        raise ValueError("Unknown city")
    clauses, values = [], []
    if city:
        clauses.append("city = ?")
        values.append(city)
    if category:
        clauses.append("category = ?")
        values.append(category)
    if text:
        clauses.append("(instr(location_text, ?) > 0 OR instr(category, ?) > 0 OR instr(id, ?) > 0)")
        values.extend([text, text, text])
    where = " WHERE " + " AND ".join(clauses) if clauses else ""
    values.append(max(1, min(limit, 10000)))
    with closing(connect_read_only(path)) as connection:
        return [json.loads(row[0]) for row in connection.execute("SELECT payload_json FROM crime_records" + where + " ORDER BY event_date DESC, id LIMIT ?", values)]


def export_document(path: Path, output: Path, template: Path) -> dict:
    path = outside_git(path)
    output = output.expanduser().resolve()
    # JSON/HTML contain the complete reference records even without a SQLite
    # header. Keep these exports out of checkout assets and release packages.
    outside_git(output / "nnk-crime-2026.json")
    if output == path or output == path.parent or path.is_relative_to(output):
        raise ValueError("Document output must be separate from the protected database directory")
    before = sha256(path)
    with closing(connect_read_only(path)) as connection:
        data = {key: json.loads(value) for key, value in connection.execute("SELECT key, value_json FROM metadata")}
        data["sources"] = [json.loads(row[0]) for row in connection.execute("SELECT payload_json FROM sources ORDER BY id")]
        data["records"] = [json.loads(row[0]) for row in connection.execute("SELECT payload_json FROM crime_records ORDER BY event_date DESC, id")]
    data["databaseSnapshot"] = {"sha256": before, "access": "read-only export; database is not bundled", "recordCount": len(data["records"])}
    validate(data)
    html = template.read_text(encoding="utf-8")
    marker = "/*__CRIME_DATA__*/"
    if html.count(marker) != 1:
        raise ValueError("Template must contain exactly one data placeholder")
    payload = encoded(data).replace("<", "\\u003c").replace("\u2028", "\\u2028").replace("\u2029", "\\u2029")
    output.mkdir(parents=True, exist_ok=True)
    (output / "nnk-crime-2026.json").write_text(json.dumps(data, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    (output / "nnk-crime-2026.html").write_text(html.replace(marker, payload), encoding="utf-8")
    # Preserve the previously delivered links, now pointing to the updated NNK snapshot.
    for suffix in ("json", "html"):
        (output / f"taipei-crime-2026.{suffix}").write_bytes((output / f"nnk-crime-2026.{suffix}").read_bytes())
    if sha256(path) != before:
        raise ValueError("Database changed during read-only export")
    return {"databaseSha256": before, "databaseUnchanged": True, "recordCount": len(data["records"]), "document": str(output / "nnk-crime-2026.html")}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    actions = parser.add_subparsers(dest="action", required=True)
    create = actions.add_parser("import-new", help="Explicitly create a NEW protected snapshot; refuses CI/existing files")
    create.add_argument("--database", type=Path, required=True)
    create.add_argument("--input", type=Path, required=True)
    create.add_argument("--allow-write", action="store_true")
    lookup = actions.add_parser("query", help="Read-only, parameterized lookup")
    lookup.add_argument("--database", type=Path, required=True)
    lookup.add_argument("--city", choices=CITIES, default="")
    lookup.add_argument("--category", default="")
    lookup.add_argument("--text", default="")
    lookup.add_argument("--limit", type=int, default=100)
    export = actions.add_parser("export", help="Read database in mode=ro and write a separate offline document")
    export.add_argument("--database", type=Path, required=True)
    export.add_argument("--output", type=Path, required=True)
    export.add_argument("--template", type=Path, required=True)
    args = parser.parse_args()
    if args.action == "import-new":
        result = create_snapshot(args.database, json.loads(args.input.read_text(encoding="utf-8")), allow_write=args.allow_write)
    elif args.action == "query":
        result = query(args.database, city=args.city, category=args.category, text=args.text, limit=args.limit)
    else:
        result = export_document(args.database, args.output, args.template)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, FileExistsError, FileNotFoundError, sqlite3.Error) as error:
        print(f"Crime reference operation refused: {error}", file=sys.stderr)
        raise SystemExit(1) from error
