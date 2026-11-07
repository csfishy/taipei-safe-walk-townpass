"""PostGIS lifecycle tests, restricted to an explicit local disposable database.

CI must supply both RESET_TEST_DATABASE_URL (restricted reset role) and
RESET_TEST_ADMIN_URL (fixture setup role). Missing local infrastructure is a
visible skip; a configured nonlocal target is a failure before connecting.
"""

import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest import mock
from urllib.parse import unquote, urlsplit


SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
import reset_demo_database as reset  # noqa: E402


TABLES = ("helpers", "emergency_alerts", "alert_recipients")
REPOSITORY = "csfishy/taipei-safe-walk-townpass"
SENTINEL_ID = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"


def assert_local_ci_url(value):
    parsed = urlsplit(value)
    if (
        parsed.scheme not in {"postgres", "postgresql"}
        or parsed.hostname not in {"127.0.0.1", "localhost", "::1"}
        or unquote(parsed.path) != "/safe_walk_ci"
        or parsed.fragment
    ):
        raise RuntimeError("Integration tests require the explicit local safe_walk_ci database")
    # libpq accepts connection parameters in a URI query. Never let a host,
    # hostaddr, service, options or dbname query override the local URL check.
    from urllib.parse import parse_qsl
    query = parse_qsl(parsed.query, keep_blank_values=True)
    if len({name for name, _ in query}) != len(query) or any(
        name != "sslmode" or value not in {"disable", "prefer"}
        for name, value in query
    ):
        raise RuntimeError("Integration test database URL contains disallowed options")


class DatabaseResetIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.reset_url = os.environ.get("RESET_TEST_DATABASE_URL", "")
        cls.admin_url = os.environ.get("RESET_TEST_ADMIN_URL", "")
        if not cls.reset_url and not cls.admin_url:
            raise unittest.SkipTest(
                "Local PostGIS integration not configured: set both "
                "RESET_TEST_DATABASE_URL and RESET_TEST_ADMIN_URL"
            )
        if not cls.reset_url or not cls.admin_url:
            raise RuntimeError("Both local integration database URLs are required")
        assert_local_ci_url(cls.reset_url)
        assert_local_ci_url(cls.admin_url)
        import psycopg
        from psycopg import sql

        cls.psycopg, cls.sql = psycopg, sql
        cls.target = reset.load_target(
            "ci",
            {
                "GITHUB_ACTIONS": "true",
                "GITHUB_REPOSITORY": REPOSITORY,
                "GITHUB_EVENT_NAME": "pull_request",
                "GITHUB_REF": "refs/pull/42/merge",
                "RESET_DATABASE_ENVIRONMENT": "ci",
                "RESET_DATABASE_PROJECT_ID": "local-ci",
                "RESET_DATABASE_URL": cls.reset_url,
            },
        )
        # These are deliberately synthetic sentinels in a disposable local
        # PostGIS service, not a Supabase account or real Auth user.
        with cls.admin() as connection:
            for role in ("anon", "authenticated"):
                if not connection.execute(
                    "SELECT 1 FROM pg_roles WHERE rolname=%s", (role,)
                ).fetchone():
                    connection.execute(
                        cls.sql.SQL("CREATE ROLE {} NOLOGIN NOINHERIT").format(
                            cls.sql.Identifier(role)
                        )
                    )
            connection.execute("CREATE SCHEMA IF NOT EXISTS auth")
            connection.execute(
                "CREATE TABLE IF NOT EXISTS auth.users "
                "(id uuid PRIMARY KEY, email text NOT NULL)"
            )
            connection.execute(
                "CREATE TABLE IF NOT EXISTS public.unrelated_reset_sentinel "
                "(id integer PRIMARY KEY, value text NOT NULL)"
            )
            connection.execute("CREATE SCHEMA IF NOT EXISTS reset_unrelated")
            connection.execute(
                "INSERT INTO auth.users(id, email) VALUES (%s, %s) "
                "ON CONFLICT(id) DO UPDATE SET email=excluded.email",
                (SENTINEL_ID, "synthetic@example.invalid"),
            )
            connection.execute(
                "INSERT INTO public.unrelated_reset_sentinel(id, value) "
                "VALUES (1, 'must survive reset') ON CONFLICT(id) "
                "DO UPDATE SET value=excluded.value"
            )

    @classmethod
    def admin(cls):
        return cls.psycopg.connect(cls.admin_url, connect_timeout=5)

    def setUp(self):
        reset.reset_database(self.target)
        self.before = self.snapshot()
        self.protected_before = self.protected_snapshot()

    def snapshot(self):
        output = {}
        with self.admin() as connection:
            for name in TABLES:
                rows = connection.execute(
                    self.sql.SQL("SELECT to_jsonb(t) FROM {}.{} AS t ORDER BY to_jsonb(t)::text").format(
                        self.sql.Identifier("safe_walk_demo"), self.sql.Identifier(name)
                    )
                ).fetchall()
                output[name] = [row[0] for row in rows]
            output["columns"] = connection.execute(
                "SELECT table_name, column_name, data_type, udt_name, is_nullable, column_default "
                "FROM information_schema.columns WHERE table_schema='safe_walk_demo' "
                "AND table_name = ANY(%s) ORDER BY table_name, ordinal_position",
                (list(TABLES),),
            ).fetchall()
            output["rls"] = connection.execute(
                "SELECT c.relname, c.relrowsecurity, c.relforcerowsecurity "
                "FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace "
                "WHERE n.nspname='safe_walk_demo' AND c.relname = ANY(%s) ORDER BY c.relname",
                (list(TABLES),),
            ).fetchall()
        return output

    def protected_snapshot(self):
        with self.admin() as connection:
            return (
                connection.execute("SELECT id::text, email FROM auth.users ORDER BY id").fetchall(),
                connection.execute(
                    "SELECT id, value FROM public.unrelated_reset_sentinel ORDER BY id"
                ).fetchall(),
            )

    def assert_unchanged(self):
        self.assertEqual(self.snapshot(), self.before)
        self.assertEqual(self.protected_snapshot(), self.protected_before)

    def test_two_consecutive_resets_restore_identical_complete_seed_and_schema(self):
        first = reset.reset_database(self.target)
        one = self.snapshot()
        second = reset.reset_database(self.target)
        self.assertEqual(one, self.snapshot())
        self.assertEqual(first["tables"], 3)
        self.assertEqual(second["tables"], 3)
        self.assertGreaterEqual(first["migrations"], 1)
        self.assertEqual(len(one["helpers"]), 2)
        self.assertEqual(len(one["emergency_alerts"]), 1)
        self.assertEqual(len(one["alert_recipients"]), 1)
        self.assertTrue(all(row[1] for row in one["rls"]))
        self.assertEqual(self.protected_snapshot(), self.protected_before)

    def test_dirty_application_rows_are_removed_without_touching_auth_or_unrelated_tables(self):
        with self.admin() as connection:
            connection.execute(
                "INSERT INTO safe_walk_demo.helpers(helper_id, enabled, location, updated_at) "
                "VALUES ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', false, NULL, '2001-01-01T00:00:00Z')"
            )
            connection.execute("UPDATE safe_walk_demo.alert_recipients SET seen=true")
        reset.reset_database(self.target)
        self.assert_unchanged()

    def test_database_marker_mismatch_aborts_before_application_changes(self):
        with self.admin() as connection:
            connection.execute(
                "UPDATE safe_walk_demo_control.target SET project_id='wrong-project'"
            )
        try:
            with self.assertRaises(reset.ResetError):
                reset.reset_database(self.target)
            self.assert_unchanged()
        finally:
            with self.admin() as connection:
                connection.execute(
                    "UPDATE safe_walk_demo_control.target SET project_id='local-ci'"
                )

    def test_foreign_key_from_unowned_table_rejects_reset_without_cascade(self):
        with self.admin() as connection:
            connection.execute(
                "CREATE TABLE reset_unrelated.external_reference "
                "(helper_id uuid REFERENCES safe_walk_demo.helpers(helper_id))"
            )
        try:
            with self.assertRaises(reset.ResetError):
                reset.reset_database(self.target)
            self.assert_unchanged()
        finally:
            with self.admin() as connection:
                connection.execute("DROP TABLE reset_unrelated.external_reference")

    def test_truncate_trigger_cannot_modify_an_unowned_table(self):
        with self.admin() as connection:
            connection.execute(
                "CREATE FUNCTION reset_unrelated.unsafe_truncate_side_effect() RETURNS trigger "
                "LANGUAGE plpgsql SECURITY DEFINER AS $$ BEGIN "
                "UPDATE public.unrelated_reset_sentinel SET value='trigger ran'; "
                "RETURN NULL; END $$"
            )
            connection.execute(
                "CREATE TRIGGER unexpected_reset_trigger AFTER TRUNCATE "
                "ON safe_walk_demo.helpers FOR EACH STATEMENT "
                "EXECUTE FUNCTION reset_unrelated.unsafe_truncate_side_effect()"
            )
        try:
            with self.assertRaises(reset.ResetError):
                reset.reset_database(self.target)
            self.assert_unchanged()
        finally:
            with self.admin() as connection:
                connection.execute("DROP TRIGGER unexpected_reset_trigger ON safe_walk_demo.helpers")
                connection.execute("DROP FUNCTION reset_unrelated.unsafe_truncate_side_effect()")

    def test_unreviewed_check_constraint_cannot_modify_an_unowned_table_during_seed(self):
        with self.admin() as connection:
            connection.execute("CREATE SEQUENCE reset_unrelated.unsafe_check_witness")
            connection.execute(
                "CREATE FUNCTION reset_unrelated.unsafe_check_side_effect() RETURNS boolean "
                "LANGUAGE plpgsql SECURITY DEFINER AS $$ BEGIN "
                "PERFORM nextval('reset_unrelated.unsafe_check_witness'); "
                "UPDATE public.unrelated_reset_sentinel SET value='constraint ran'; "
                "RETURN true; END $$"
            )
            connection.execute(
                "ALTER TABLE safe_walk_demo.helpers ADD CONSTRAINT unexpected_reset_check "
                "CHECK (reset_unrelated.unsafe_check_side_effect()) NOT VALID"
            )
        try:
            with self.assertRaises(reset.ResetError):
                reset.reset_database(self.target)
            self.assert_unchanged()
            # A sequence increment survives transaction rollback: this proves
            # the unexpected function was rejected before INSERT evaluated it.
            with self.admin() as connection:
                self.assertFalse(
                    connection.execute(
                        "SELECT is_called FROM reset_unrelated.unsafe_check_witness"
                    ).fetchone()[0]
                )
        finally:
            with self.admin() as connection:
                connection.execute(
                    "ALTER TABLE safe_walk_demo.helpers DROP CONSTRAINT unexpected_reset_check"
                )
                connection.execute("DROP FUNCTION reset_unrelated.unsafe_check_side_effect()")
                connection.execute("DROP SEQUENCE reset_unrelated.unsafe_check_witness")
                connection.execute(
                    "UPDATE public.unrelated_reset_sentinel SET value='must survive reset' WHERE id=1"
                )

    def test_failed_seed_rolls_back_cleanup_and_all_partial_seed_rows(self):
        with tempfile.TemporaryDirectory() as temporary:
            sql_root = Path(temporary) / "demo"
            shutil.copytree(reset.SQL_ROOT, sql_root)
            seed = sql_root / "seed.sql"
            self.assertTrue(seed.exists(), "SQL_ROOT/seed.sql is part of the reset contract")
            with seed.open("a", encoding="utf-8") as stream:
                stream.write("\nSELECT 1 / 0;\n")
            with mock.patch.object(reset, "SQL_ROOT", sql_root):
                with self.assertRaises(reset.ResetError):
                    reset.reset_database(self.target)
        self.assert_unchanged()

    def test_modified_applied_migration_is_rejected_without_resetting_data(self):
        with tempfile.TemporaryDirectory() as temporary:
            sql_root = Path(temporary) / "demo"
            shutil.copytree(reset.SQL_ROOT, sql_root)
            migration = sorted((sql_root / "migrations").glob("*.sql"))[0]
            with migration.open("a", encoding="utf-8") as stream:
                stream.write("\n-- unexpected migration checksum drift\n")
            with mock.patch.object(reset, "SQL_ROOT", sql_root):
                with self.assertRaises(reset.ResetError):
                    reset.reset_database(self.target)
        self.assert_unchanged()

    def test_unreviewed_schema_drift_does_not_get_silently_repaired(self):
        with self.admin() as connection:
            connection.execute("ALTER TABLE safe_walk_demo.helpers ADD COLUMN unexpected text")
        try:
            self.before = self.snapshot()
            with self.assertRaises(reset.ResetError):
                reset.reset_database(self.target)
            self.assert_unchanged()
        finally:
            with self.admin() as connection:
                connection.execute("ALTER TABLE safe_walk_demo.helpers DROP COLUMN unexpected")

    def test_reset_role_cannot_change_its_environment_marker(self):
        with self.admin() as connection:
            connection.execute(
                "GRANT UPDATE ON safe_walk_demo_control.target TO safe_walk_demo_reset"
            )
        try:
            with self.assertRaises(reset.ResetError):
                reset.reset_database(self.target)
            self.assert_unchanged()
        finally:
            with self.admin() as connection:
                connection.execute(
                    "REVOKE UPDATE ON safe_walk_demo_control.target FROM safe_walk_demo_reset"
                )

    def test_elevated_reset_role_is_rejected_before_cleanup(self):
        with self.admin() as connection:
            connection.execute("ALTER ROLE safe_walk_demo_reset CREATEDB")
        try:
            with self.assertRaises(reset.ResetError):
                reset.reset_database(self.target)
            self.assert_unchanged()
        finally:
            with self.admin() as connection:
                connection.execute("ALTER ROLE safe_walk_demo_reset NOCREATEDB")

    def test_an_active_database_lock_rejects_another_reset(self):
        with self.admin() as connection:
            connection.execute("SELECT pg_advisory_xact_lock(%s)", (reset.LOCK_ID,))
            with self.assertRaises(reset.ResetError):
                reset.reset_database(self.target)
            self.assert_unchanged()

    def test_public_client_roles_cannot_read_write_or_call_nearby_rpc(self):
        with self.admin() as connection:
            for role in ("anon", "authenticated"):
                for table in TABLES:
                    for privilege in ("SELECT", "INSERT", "UPDATE", "DELETE", "TRUNCATE"):
                        self.assertFalse(
                            connection.execute(
                                "SELECT has_table_privilege(%s, %s, %s)",
                                (role, f"safe_walk_demo.{table}", privilege),
                            ).fetchone()[0],
                            (role, table, privilege),
                        )
            self.assertEqual(
                connection.execute(
                    "SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace "
                    "WHERE n.nspname='safe_walk_demo'"
                ).fetchone()[0],
                0,
            )
        self.assert_unchanged()


if __name__ == "__main__":
    unittest.main()
