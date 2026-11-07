"""Synthetic-only SQLite regression tests; never read the real crime store."""
from copy import deepcopy
from contextlib import closing
import json
import os
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import patch

from crime_reference_store import connect_read_only, create_snapshot, export_document, query, sha256, validate


def sample():
    return {"schemaVersion": "2.0.0", "year": 2026, "sources": [{"datasetId": "synthetic", "name": "人工測試來源", "url": "https://example.invalid"}], "records": [{
        "id": "synthetic:1", "sourceId": "synthetic", "city": "臺北市", "district": "中正區", "category": "人工案例",
        "date": "2026-01-01", "locationText": "人工位置</script>", "latitude": None, "longitude": None,
        "coordinateStatus": "not_provided", "spatialPrecision": "district_only",
    }]}


class CrimeReferenceStoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="synthetic-crime-store-")
        self.root = Path(self.temp.name)
        self.db = self.root / "database" / "nnk-crime-test.sqlite3"
        self.environment = patch.dict(os.environ, {"GITHUB_ACTIONS": "false", "CI": "false"})
        self.environment.start()

    def tearDown(self):
        self.environment.stop()
        if self.db.exists():
            self.db.chmod(0o666)
        self.temp.cleanup()

    def create(self):
        return create_snapshot(self.db, sample(), allow_write=True)

    def test_import_requires_explicit_write(self):
        with self.assertRaisesRegex(ValueError, "explicit"):
            create_snapshot(self.db, sample())
        self.assertFalse(self.db.exists())

    def test_ci_cannot_import(self):
        for variable in ("GITHUB_ACTIONS", "CI"):
            with self.subTest(variable=variable), patch.dict(os.environ, {variable: "true"}):
                with self.assertRaisesRegex(ValueError, "forbidden in CI"):
                    self.create()
        self.assertFalse(self.db.exists())

    def test_import_refuses_git_checkout(self):
        (self.root / ".git").mkdir()
        with self.assertRaisesRegex(ValueError, "outside every Git"):
            self.create()
        self.assertFalse(self.db.exists())

    def test_existing_store_never_replaced(self):
        first = self.create()
        with self.assertRaises(FileExistsError):
            self.create()
        self.assertEqual(sha256(self.db), first["sha256"])

    def test_real_sqlite_integrity_and_indexed_query(self):
        self.create()
        with closing(connect_read_only(self.db)) as connection:
            self.assertEqual(connection.execute("PRAGMA integrity_check").fetchone(), ("ok",))
            self.assertEqual(connection.execute("PRAGMA foreign_key_check").fetchall(), [])
            self.assertTrue(connection.execute("SELECT name FROM sqlite_master WHERE type='index' AND name='crime_city_date'").fetchone())
        self.assertEqual(len(query(self.db, city="臺北市", category="人工案例", text="人工")), 1)
        self.assertEqual(query(self.db, text="' OR 1=1 --"), [])
        self.assertEqual(query(self.db, city="新北市"), [])

    def test_readonly_query_refuses_dml_even_if_query_only_turned_off(self):
        original = self.create()["sha256"]
        connection = connect_read_only(self.db)
        try:
            connection.execute("PRAGMA query_only=OFF")
            with self.assertRaises(sqlite3.OperationalError):
                connection.execute("DELETE FROM crime_records")
        finally:
            connection.close()
        self.assertEqual(sha256(self.db), original)
        self.assertEqual(len(query(self.db)), 1)

    def test_missing_database_query_creates_nothing(self):
        with self.assertRaises(FileNotFoundError):
            query(self.db)
        self.assertFalse(self.db.exists())

    def test_export_is_readonly_and_escapes_script_data(self):
        original = self.create()["sha256"]
        template = self.root / "template.html"
        template.write_text('<script type="application/json">/*__CRIME_DATA__*/</script>', encoding="utf-8")
        output = self.root / "documents"
        report = export_document(self.db, output, template)
        self.assertTrue(report["databaseUnchanged"])
        self.assertEqual(sha256(self.db), original)
        self.assertIn("\\u003c/script>", (output / "nnk-crime-2026.html").read_text(encoding="utf-8"))
        self.assertEqual(json.loads((output / "nnk-crime-2026.json").read_text(encoding="utf-8"))["records"], sample()["records"])
        self.assertFalse(list(output.glob("*.sqlite*")))
        with self.assertRaisesRegex(ValueError, "separate"):
            export_document(self.db, self.db.parent, template)

    def test_rejects_outside_city_year_and_swapped_coordinates(self):
        for updates in ({"city": "桃園市"}, {"date": "2025-12-31"}, {"date": "2026-12-31"}, {"latitude": 121.5, "longitude": 25.0}):
            data = deepcopy(sample())
            data["records"][0].update(updates)
            with self.subTest(updates=updates), self.assertRaises(ValueError):
                validate(data)

    def test_export_refuses_checkout_and_worktree_assets_before_writing(self):
        original = self.create()["sha256"]
        template = self.root / "template.html"
        template.write_text('/*__CRIME_DATA__*/', encoding="utf-8")
        for marker_is_file in (False, True):
            checkout = self.root / str(marker_is_file)
            checkout.mkdir()
            marker = checkout / ".git"
            if marker_is_file:
                marker.write_text("gitdir: /synthetic/worktree", encoding="utf-8")
            else:
                marker.mkdir()
            for output in (checkout, checkout / "assets" / "exports"):
                with self.subTest(output=output), self.assertRaisesRegex(ValueError, "outside every Git"):
                    export_document(self.db, output, template)
                self.assertFalse((output / "nnk-crime-2026.json").exists())
        self.assertEqual(sha256(self.db), original)

    def test_unverified_or_district_coordinates_rejected(self):
        data = sample()
        data["records"][0].update(latitude=25.0, longitude=121.5)
        with self.assertRaisesRegex(ValueError, "cannot become"):
            validate(data)
        data["records"][0].update(coordinateStatus="reference_geocoded", spatialPrecision="address_range_reference")
        with self.assertRaisesRegex(ValueError, "missing evidence"):
            validate(data)


if __name__ == "__main__":
    unittest.main()
