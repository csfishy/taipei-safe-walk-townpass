"""Synthetic bytes only: these tests never create or open a real database."""

from pathlib import Path
import subprocess
import tempfile
import unittest
import zipfile

from check_crime_database_isolation import (
    SQLITE_HEADER, forbidden_database_name, scan_archive, scan_repository,
    write_policy_errors,
)


class RepositoryIsolationTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        subprocess.run(["git", "init", "-q", str(self.root)], check=True, capture_output=True)

    def write(self, name, value, *, track=False):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(value if isinstance(value, bytes) else value.encode())
        if track:
            subprocess.run(["git", "-C", str(self.root), "add", "--", name], check=True, capture_output=True)
        return path

    def test_normal_sources_and_asset_text_pass(self):
        self.write("tool/example.py", "# SQLite format 3 is documentation", track=True)
        self.write("assets/a.json", '{"label":"SQLite format 3"}')
        self.assertEqual(scan_repository(self.root), [])

    def test_tracked_disguised_header_is_rejected(self):
        self.write("data/innocent.bin", SQLITE_HEADER + b"synthetic", track=True)
        self.assertTrue(any("SQLite binary" in issue for issue in scan_repository(self.root)))

    def test_named_sidecars_and_private_directories_are_rejected(self):
        for name in ("nnk-crime-2026.sqlite3-wal", "data/NNK-CRIME-test.SQLITE-journal",
                     ".local-data/readme", "crime-reference-data/sample.json"):
            with self.subTest(name=name):
                self.assertTrue(forbidden_database_name(name))
        self.write("data/nnk-crime-2026.sqlite3-shm", b"sidecar", track=True)
        self.assertTrue(scan_repository(self.root))

    def test_ignored_untracked_asset_is_still_inspected(self):
        self.write(".gitignore", "assets/hidden.bin\n", track=True)
        self.write("assets/hidden.bin", SQLITE_HEADER + b"synthetic")
        self.assertTrue(any("assets/hidden.bin" in issue for issue in scan_repository(self.root)))

    def test_custom_flutter_asset_directory_is_inspected(self):
        self.write("pubspec.yaml", "name: sample\nflutter:\n  assets:\n    - custom_data/\n", track=True)
        self.write("custom_data/hidden.dat", SQLITE_HEADER)
        self.assertTrue(any("custom_data/hidden.dat" in issue for issue in scan_repository(self.root)))

    def test_external_database_not_scanned(self):
        # The guard has no database-path option and scans only checkout/asset files.
        outside = self.root.parent / (self.root.name + "-external.sqlite3")
        outside.write_bytes(SQLITE_HEADER + b"synthetic")
        self.addCleanup(outside.unlink)
        self.assertEqual(scan_repository(self.root), [])

    def test_outside_asset_declaration_rejected_without_read(self):
        self.write("pubspec.yaml", "flutter:\n  assets:\n    - ../external-data/\n", track=True)
        self.assertTrue(any("outside checkout" in issue for issue in scan_repository(self.root)))

    def test_untracked_sql_write_is_checked(self):
        self.write("tool/unsafe.sql", "DELETE FROM crime_reference.records;")
        self.assertTrue(any("reviewed manual SQL" in issue for issue in scan_repository(self.root)))


class WritePolicyTest(unittest.TestCase):
    def test_manual_sql_allowed_but_never_workflow(self):
        sql = "INSERT INTO crime_reference.records VALUES ('synthetic');"
        self.assertEqual(write_policy_errors("supabase/crime_reference/import.sql", sql), [])
        self.assertTrue(write_policy_errors("supabase/migrations/import.sql", sql))
        self.assertTrue(write_policy_errors(".github/workflows/build.yml", "run: psql -f supabase/crime_reference/import.sql"))

    def test_destructive_and_privilege_writes_rejected(self):
        for sql in ('TRUNCATE TABLE "crime_reference".records;',
                    "DROP SCHEMA IF EXISTS crime_reference CASCADE;",
                    "ALTER TABLE crime_reference.records DISABLE ROW LEVEL SECURITY;",
                    "GRANT USAGE ON SCHEMA crime_reference TO anon;",
                    'DROP SCHEMA "crime_reference";',
                    "CREATE UNIQUE INDEX records_id ON crime_reference.records(id);",
                    "COPY crime_reference.records FROM STDIN;",
                    "CALL crime_reference.import_snapshot();",
                    "SELECT crime_reference.import_snapshot();"):
            with self.subTest(sql=sql):
                self.assertTrue(write_policy_errors("tool/reset.sh", sql))

    def test_comments_and_read_only_query_are_not_writes(self):
        self.assertEqual(write_policy_errors("tool/query.sql", "-- DROP SCHEMA crime_reference\nSELECT * FROM crime_reference.records;"), [])

    def test_ci_cannot_import_or_reset_shared_project(self):
        for script in ("python3 tool/crime_reference_store.py import-new --allow-write",
                       "supabase db reset", "supabase db push", "supabase migration up"):
            with self.subTest(script=script):
                self.assertTrue(write_policy_errors(".github/workflows/build.yml", "run: " + script))

    def test_unqualified_search_path_writes_cannot_bypass_guard(self):
        for name, text in (
            ("tool/unsafe.sql", "SET search_path TO crime_reference; TRUNCATE records;"),
            ("tool/unsafe.sql", 'SET LOCAL search_path =\n  "crime_reference", pg_catalog; DELETE FROM records;'),
            (".github/workflows/reset.yml", 'run: PGOPTIONS="--search_path=crime_reference" psql -c "TRUNCATE records"'),
            ("tool/reset.sh", "PGOPTIONS='-c search_path=crime_reference,public' psql -c 'DELETE FROM records'"),
            (".github/workflows/reset.yml", 'env:\n  PGOPTIONS: "-c search_path=crime_reference"\nrun: psql -c "TRUNCATE records"'),
        ):
            with self.subTest(name=name, text=text):
                self.assertTrue(any("search_path/PGOPTIONS" in issue for issue in write_policy_errors(name, text)))

    def test_set_config_search_path_is_controlled_even_for_read_only_calls(self):
        for text in (
            "SELECT set_config('search_path', 'crime_reference, pg_catalog', true); DELETE FROM records;",
            "SELECT set_config(\n  'search_path',\n  'crime_reference', true); SELECT * FROM records;",
        ):
            with self.subTest(text=text):
                self.assertTrue(write_policy_errors("tool/query.sql", text))
                self.assertEqual(write_policy_errors("supabase/crime_reference/manual.sql", text), [])
        self.assertEqual(write_policy_errors("tool/query.sql", "SET search_path TO public; SELECT 1;"), [])


class ArchiveIsolationTest(unittest.TestCase):
    def test_zip_apk_and_ipa_sqlite_payloads_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            for suffix, member in (("zip", "assets/data.bin"), ("apk", "assets/flutter_assets/cache.dat"),
                                   ("ipa", "Payload/Runner.app/Frameworks/App.framework/flutter_assets/cache.dat")):
                with self.subTest(suffix=suffix):
                    path = Path(directory) / ("package." + suffix)
                    with zipfile.ZipFile(path, "w") as archive:
                        archive.writestr(member, SQLITE_HEADER + b"synthetic")
                    self.assertTrue(any("SQLite binary" in issue for issue in scan_archive(path)))

    def test_sidecar_without_header_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "package.zip"
            with zipfile.ZipFile(path, "w") as archive:
                archive.writestr("assets/NNK-CRIME-2026.sqlite3-wal", b"synthetic")
            self.assertTrue(scan_archive(path))

    def test_clean_archive_and_invalid_archive(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "package.zip"
            with zipfile.ZipFile(path, "w") as archive:
                archive.writestr("index.html", "<p>Reference database stays private.</p>")
            self.assertEqual(scan_archive(path), [])
            path.write_bytes(b"not a zip")
            self.assertTrue(any("cannot be verified" in issue for issue in scan_archive(path)))


if __name__ == "__main__":
    unittest.main()
