"""Workflow contract tests for CI isolation and a single guarded remote reset."""

from pathlib import Path
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[2]
WORKFLOWS = ROOT / ".github" / "workflows"


def workflow(name):
    # BaseLoader preserves GitHub's `on` key and expression/boolean strings.
    return yaml.load((WORKFLOWS / name).read_text(encoding="utf-8"), Loader=yaml.BaseLoader)


def needs(job):
    value = job.get("needs", [])
    return {value} if isinstance(value, str) else set(value)


def job_text(job):
    return yaml.dump(job, allow_unicode=True)


class DatabaseWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.build = workflow("build.yml")
        self.safety = workflow("safe_walk.yml")
        self.database = workflow("demo_database_ci.yml")

    def test_both_compilation_workflows_require_the_ephemeral_database_checks(self):
        for name, document, check in (
            ("build", self.build, "check"),
            ("safe_walk", self.safety, "checks"),
        ):
            with self.subTest(workflow=name):
                caller = document["jobs"]["database-ci"]
                self.assertEqual(caller["uses"], "./.github/workflows/demo_database_ci.yml")
                self.assertNotIn("if", caller, "The isolated CI reset must not be opt-in")
                self.assertNotIn("secrets", caller, "PR jobs must not inherit Demo secrets")
                self.assertIn("database-ci", needs(document["jobs"][check]))

    def test_reusable_ci_reset_accepts_no_remote_credentials_or_dispatch(self):
        self.assertEqual(set(self.database["on"]), {"workflow_call"})
        self.assertNotIn("secrets", self.database["on"].get("workflow_call") or {})
        self.assertNotIn("secrets.", job_text(self.database))
        self.assertEqual(len(self.database["jobs"]), 1)
        job = self.database["jobs"]["reset-ci-database"]
        self.assertIn("postgis/postgis:", job["services"]["postgres"]["image"])
        self.assertEqual(job["env"]["RESET_DATABASE_ENVIRONMENT"], "ci")
        self.assertEqual(job["env"]["RESET_DATABASE_PROJECT_ID"], "local-ci")
        for variable in ("RESET_DATABASE_URL", "RESET_TEST_DATABASE_URL", "RESET_TEST_ADMIN_URL"):
            self.assertIn("@127.0.0.1:", job["env"][variable])
            self.assertIn("/safe_walk_ci?sslmode=disable", job["env"][variable])
        commands = "\n".join(step.get("run", "") for step in job["steps"])
        self.assertIn("python3 scripts/reset_demo_database.py --environment ci", commands)
        self.assertIn("unittest discover -s scripts/tests", commands)
        self.assertIn('test -n "$RESET_TEST_DATABASE_URL"', commands)
        self.assertIn('test -n "$RESET_TEST_ADMIN_URL"', commands)

    def test_only_one_remote_reset_exists_and_platform_jobs_have_no_demo_secret(self):
        remote_jobs = []
        for filename in ("build.yml", "safe_walk.yml", "demo_database_ci.yml"):
            document = workflow(filename)
            for name, job in document["jobs"].items():
                if "--environment demo" in job_text(job):
                    remote_jobs.append((filename, name))
        self.assertEqual(remote_jobs, [("build.yml", "demo-database-reset")])
        for platform in ("check", "web", "android", "ios"):
            self.assertNotIn("DEMO_DATABASE_URL", job_text(self.build["jobs"][platform]))
            self.assertNotIn("DEMO_SUPABASE_PROJECT_ID", job_text(self.build["jobs"][platform]))
        self.assertNotIn("DEMO_DATABASE_URL", job_text(self.safety))
        self.assertNotIn("--environment demo", job_text(self.safety))

    def test_remote_reset_waits_for_all_builds_and_requires_main_trusted_event(self):
        job = self.build["jobs"]["demo-database-reset"]
        self.assertEqual(needs(job), {"check", "web", "android", "ios"})
        condition = job["if"]
        self.assertIn("github.event_name == 'push'", condition)
        self.assertIn("github.event_name == 'workflow_dispatch'", condition)
        self.assertIn("github.ref == 'refs/heads/main'", condition)
        self.assertNotIn("pull_request", condition)
        self.assertNotIn("always()", condition, "A failed build must prevent a remote reset")
        self.assertEqual(job["environment"], "safe-walk-demo")
        self.assertEqual(job["env"]["RESET_DATABASE_ENVIRONMENT"], "demo")
        self.assertEqual(job["env"]["RESET_DATABASE_URL"], "${{ secrets.DEMO_DATABASE_URL }}")
        self.assertEqual(
            job["env"]["RESET_DATABASE_PROJECT_ID"], "${{ secrets.DEMO_SUPABASE_PROJECT_ID }}"
        )
        self.assertNotIn("continue-on-error", job)

    def test_remote_reset_has_a_repository_wide_non_cancelling_lock(self):
        concurrency = self.build["jobs"]["demo-database-reset"]["concurrency"]
        self.assertEqual(concurrency["group"], "safe-walk-demo-database")
        self.assertEqual(concurrency["cancel-in-progress"], "false")
        self.assertNotIn("github.workflow", concurrency["group"])
        self.assertNotIn("github.run_id", concurrency["group"])

    def test_failed_main_reset_blocks_publish_and_pages_but_tags_skip_remote_reset(self):
        publish = self.build["jobs"]["publish"]
        self.assertIn("demo-database-reset", needs(publish))
        self.assertIn("needs.demo-database-reset.result == 'success'", publish["if"])
        self.assertIn("needs.demo-database-reset.result == 'skipped'", publish["if"])
        self.assertIn("startsWith(github.ref, 'refs/tags/v')", publish["if"])
        for required in ("check", "web", "android", "ios"):
            self.assertIn(f"needs.{required}.result == 'success'", publish["if"])
        settings = self.build["jobs"]["pages-settings"]
        self.assertIn("demo-database-reset", needs(settings))
        self.assertIn("needs.demo-database-reset.result == 'success'", settings["if"])
        self.assertIn("pages-settings", needs(self.build["jobs"]["pages"]))


if __name__ == "__main__":
    unittest.main()
