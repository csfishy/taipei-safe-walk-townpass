"""Fail-closed target selection tests; no network or database is used."""

import contextlib
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock


SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
import reset_demo_database as reset  # noqa: E402


REPOSITORY = "csfishy/taipei-safe-walk-townpass"
DEMO_REF = "abcdefghijklmnopqrst"
PROTECTED_REF = "gxofnhzkqcmzrftxqddi"
POOLER = "aws-0-ap-northeast-1.pooler.supabase.com"
CI_DSN = (
    "postgresql://safe_walk_demo_reset:ci-disposable-password@127.0.0.1:5432/"
    "safe_walk_ci?sslmode=disable"
)


def ci_environment():
    return {
        "GITHUB_ACTIONS": "true",
        "GITHUB_REPOSITORY": REPOSITORY,
        "GITHUB_EVENT_NAME": "pull_request",
        "GITHUB_REF": "refs/pull/42/merge",
        "RESET_DATABASE_ENVIRONMENT": "ci",
        "RESET_DATABASE_PROJECT_ID": "local-ci",
        "RESET_DATABASE_URL": CI_DSN,
    }


def demo_environment():
    return {
        **ci_environment(),
        "GITHUB_EVENT_NAME": "push",
        "GITHUB_REF": "refs/heads/main",
        "RESET_DATABASE_ENVIRONMENT": "demo",
        "RESET_DATABASE_PROJECT_ID": DEMO_REF,
        "RESET_DATABASE_URL": (
            "postgresql://safe_walk_demo_reset:artificial-not-a-real-password@"
            f"db.{DEMO_REF}.supabase.co:5432/postgres?sslmode=verify-full"
        ),
    }


class TargetSelectionTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.manifest = Path(self.directory.name) / "targets.json"
        self.write_manifest()

    def write_manifest(self, **overrides):
        value = {
            "repository": REPOSITORY,
            "protected_project_ids": [PROTECTED_REF],
            "demo_projects": [{"project_id": DEMO_REF, "pooler_hosts": [POOLER]}],
            **overrides,
        }
        self.manifest.write_text(json.dumps(value), encoding="utf-8")

    def load(self, environment="ci", values=None):
        if values is None:
            values = ci_environment() if environment == "ci" else demo_environment()
        return reset.load_target(environment, values, manifest=self.manifest)

    def test_ci_accepts_only_explicit_disposable_local_target(self):
        target = self.load()
        self.assertEqual(target.environment, "ci")
        self.assertEqual(target.project_id, "local-ci")
        self.assertEqual(target.host, "127.0.0.1")
        self.assertNotIn("ci-disposable-password", repr(target))

    def test_demo_requires_reviewed_allowlist_entry_and_matching_direct_host(self):
        target = self.load("demo")
        self.assertEqual(target.project_id, DEMO_REF)
        self.assertEqual(target.environment, "demo")
        self.assertNotIn("artificial-not-a-real-password", repr(target))

    def test_pooler_requires_exact_host_and_project_bound_username(self):
        values = demo_environment()
        values["RESET_DATABASE_URL"] = (
            f"postgresql://safe_walk_demo_reset.{DEMO_REF}:artificial@"
            f"{POOLER}:5432/postgres?sslmode=verify-full"
        )
        self.assertEqual(self.load("demo", values).host, POOLER)
        for user in ("safe_walk_demo_reset", "postgres", f"safe_walk_demo_reset.{PROTECTED_REF}"):
            with self.subTest(user=user):
                wrong = {
                    **values,
                    "RESET_DATABASE_URL": (
                        f"postgresql://{user}:artificial@{POOLER}:5432/postgres"
                        "?sslmode=verify-full"
                    ),
                }
                with self.assertRaises(reset.ResetError):
                    self.load("demo", wrong)

    def test_required_environment_settings_cannot_be_inferred(self):
        for name in (
            "GITHUB_ACTIONS",
            "GITHUB_REPOSITORY",
            "RESET_DATABASE_ENVIRONMENT",
            "RESET_DATABASE_PROJECT_ID",
            "RESET_DATABASE_URL",
        ):
            with self.subTest(name=name):
                values = ci_environment()
                values.pop(name)
                with self.assertRaises(reset.ResetError):
                    self.load(values=values)

    def test_unknown_environment_and_repository_are_rejected(self):
        for environment in ("production", "prod", "staging", "", "CI"):
            with self.subTest(environment=environment):
                with self.assertRaises(reset.ResetError):
                    self.load(environment, ci_environment())
        for name, value in (
            ("GITHUB_ACTIONS", "false"),
            ("GITHUB_REPOSITORY", "other-owner/taipei-safe-walk-townpass"),
            ("RESET_DATABASE_ENVIRONMENT", "demo"),
            ("RESET_DATABASE_PROJECT_ID", PROTECTED_REF),
        ):
            with self.subTest(name=name, value=value):
                with self.assertRaises(reset.ResetError):
                    self.load(values={**ci_environment(), name: value})

    def test_ci_rejects_remote_hosts_non_ci_databases_and_privileged_roles(self):
        for url in (
            f"postgresql://safe_walk_demo_reset:artificial@db.{DEMO_REF}.supabase.co/safe_walk_ci",
            "postgresql://safe_walk_demo_reset:artificial@127.0.0.1/postgres",
            "postgresql://postgres:artificial@127.0.0.1/safe_walk_ci",
            "postgresql://safe_walk_demo_reset:artificial@127.0.0.1.evil.example/safe_walk_ci",
            "host=127.0.0.1 dbname=safe_walk_ci user=safe_walk_demo_reset",
        ):
            with self.subTest(url=url):
                with self.assertRaises(reset.ResetError):
                    self.load(values={**ci_environment(), "RESET_DATABASE_URL": url})

    def test_demo_cannot_run_for_pr_tag_or_other_branch(self):
        for event, ref in (
            ("pull_request", "refs/pull/42/merge"),
            ("pull_request_target", "refs/heads/main"),
            ("push", "refs/tags/v0.0.12-pre.1"),
            ("push", "refs/heads/feature"),
            ("workflow_dispatch", "refs/heads/feature"),
        ):
            with self.subTest(event=event, ref=ref):
                with self.assertRaises(reset.ResetError):
                    self.load("demo", {**demo_environment(), "GITHUB_EVENT_NAME": event, "GITHUB_REF": ref})

    def test_reviewed_demo_can_run_for_manual_build_of_main_only(self):
        target = self.load(
            "demo", {**demo_environment(), "GITHUB_EVENT_NAME": "workflow_dispatch"}
        )
        self.assertEqual(target.environment, "demo")

    def test_demo_rejects_ambiguous_dsn_or_weakened_tls(self):
        origin = f"db.{DEMO_REF}.supabase.co"
        for url in (
            f"postgresql://safe_walk_demo_reset:artificial@{origin}:5432/postgres",
            f"postgresql://safe_walk_demo_reset:artificial@{origin}:5432/postgres?sslmode=require",
            f"postgresql://safe_walk_demo_reset:artificial@{origin}:5432/postgres?sslmode=disable",
            f"postgresql://postgres:artificial@{origin}:5432/postgres?sslmode=verify-full",
            f"postgresql://safe_walk_demo_reset:artificial@{origin}:6543/postgres?sslmode=verify-full",
            f"postgresql://safe_walk_demo_reset:artificial@{origin}:5432/other?sslmode=verify-full",
            f"postgresql://safe_walk_demo_reset:artificial@{origin}:5432/postgres?sslmode=verify-full&host=evil.example",
            f"postgresql://safe_walk_demo_reset:artificial@{origin}:5432/postgres?sslmode=verify-full&options=-csearch_path=auth",
            f"postgresql://safe_walk_demo_reset:artificial@{origin}:5432/postgres?sslmode=verify-full&sslmode=disable",
            f"postgresql://safe_walk_demo_reset:artificial@{origin}:5432/postgres?sslmode=verify-full#private",
            "postgresql://safe_walk_demo_reset:artificial@unlisted.pooler.supabase.com:5432/postgres?sslmode=verify-full",
        ):
            with self.subTest(url=url):
                with self.assertRaises(reset.ResetError):
                    self.load("demo", {**demo_environment(), "RESET_DATABASE_URL": url})

    def test_allowlist_is_fail_closed_and_protected_ref_always_wins(self):
        self.write_manifest(demo_projects=[])
        with self.assertRaises(reset.ResetError):
            self.load("demo")
        self.write_manifest(
            demo_projects=[{"project_id": PROTECTED_REF, "pooler_hosts": []}]
        )
        values = {
            **demo_environment(),
            "RESET_DATABASE_PROJECT_ID": PROTECTED_REF,
            "RESET_DATABASE_URL": (
                "postgresql://safe_walk_demo_reset:artificial@"
                f"db.{PROTECTED_REF}.supabase.co:5432/postgres?sslmode=verify-full"
            ),
        }
        with self.assertRaises(reset.ResetError):
            self.load("demo", values)

    def test_manifest_missing_malformed_or_wrong_repository_is_rejected(self):
        self.manifest.unlink()
        with self.assertRaises(reset.ResetError):
            self.load("demo")
        self.manifest.write_text("{ malformed", encoding="utf-8")
        with self.assertRaises(reset.ResetError):
            self.load("demo")
        self.write_manifest(repository="another/repository")
        with self.assertRaises(reset.ResetError):
            self.load("demo")

    def test_validate_only_never_opens_a_connection(self):
        with (
            mock.patch.dict(os.environ, ci_environment(), clear=True),
            mock.patch.object(reset, "reset_database") as operation,
            contextlib.redirect_stdout(io.StringIO()),
            contextlib.redirect_stderr(io.StringIO()),
        ):
            result = reset.main(["--environment", "ci", "--validate-only"])
        self.assertEqual(result, 0)
        operation.assert_not_called()

    def test_cli_errors_never_print_the_database_credential(self):
        secret = "artificial-password-that-must-not-appear"
        values = {
            **ci_environment(),
            "RESET_DATABASE_URL": f"postgresql://postgres:{secret}@untrusted.example/prod",
        }
        out, err = io.StringIO(), io.StringIO()
        with (
            mock.patch.dict(os.environ, values, clear=True),
            mock.patch.object(reset, "reset_database") as operation,
            contextlib.redirect_stdout(out),
            contextlib.redirect_stderr(err),
        ):
            result = reset.main(["--environment", "ci"])
        self.assertNotEqual(result, 0)
        operation.assert_not_called()
        self.assertNotIn(secret, out.getvalue() + err.getvalue())
        self.assertNotIn(values["RESET_DATABASE_URL"], out.getvalue() + err.getvalue())


if __name__ == "__main__":
    unittest.main()
