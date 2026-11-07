"""Workflow contract tests for CI isolation and a single guarded remote reset."""

from pathlib import Path
import re
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


class ActionsCondition:
    """Evaluate the boolean subset used by the actual workflow conditions.

    This deliberately has no eval(), shell execution, or expression rewriting.
    Unknown syntax fails the test instead of silently approximating Actions.
    """

    TOKEN = re.compile(r"\s*(?:(\&\&|\|\||==|!=|[!(),])|('(?:[^']|'')*')|([A-Za-z_][\w.-]*))")
    STATUS_FUNCTIONS = frozenset({"always", "cancelled", "success", "failure"})

    def __init__(self, expression, context):
        expression = expression.strip()
        if expression.startswith("${{") and expression.endswith("}}"):
            expression = expression[3:-2].strip()
        self.tokens = []
        cursor = 0
        while cursor < len(expression):
            match = self.TOKEN.match(expression, cursor)
            if match is None:
                raise AssertionError(f"Unsupported workflow condition at offset {cursor}")
            self.tokens.append(next(value for value in match.groups() if value is not None))
            cursor = match.end()
        self.index = 0
        self.context = context
        self.calls = set()

    def take(self, token):
        if self.index < len(self.tokens) and self.tokens[self.index] == token:
            self.index += 1
            return True
        return False

    def evaluate(self):
        value = self.parse_or()
        if self.index != len(self.tokens):
            raise AssertionError("Unexpected trailing workflow condition tokens")
        return bool(value)

    def parse_or(self):
        value = self.parse_and()
        while self.take("||"):
            # Parse both sides even when one short-circuits, so unsupported
            # syntax or a changed dependency cannot hide in another branch.
            right = self.parse_and()
            value = bool(value) or bool(right)
        return value

    def parse_and(self):
        value = self.parse_equality()
        while self.take("&&"):
            right = self.parse_equality()
            value = bool(value) and bool(right)
        return value

    def parse_equality(self):
        value = self.parse_unary()
        while self.index < len(self.tokens) and self.tokens[self.index] in {"==", "!="}:
            operator = self.tokens[self.index]
            self.index += 1
            right = self.parse_unary()
            if isinstance(value, str) and isinstance(right, str):
                equal = value.casefold() == right.casefold()
            else:
                equal = value == right
            value = equal if operator == "==" else not equal
        return value

    def parse_unary(self):
        if self.take("!"):
            return not bool(self.parse_unary())
        if self.take("("):
            value = self.parse_or()
            if not self.take(")"):
                raise AssertionError("Unclosed workflow condition")
            return value
        if self.index >= len(self.tokens):
            raise AssertionError("Missing workflow condition value")
        token = self.tokens[self.index]
        self.index += 1
        if token.startswith("'"):
            return token[1:-1].replace("''", "'")
        if self.take("("):
            arguments = []
            if not self.take(")"):
                arguments.append(self.parse_or())
                while self.take(","):
                    arguments.append(self.parse_or())
                if not self.take(")"):
                    raise AssertionError("Unclosed workflow condition function")
            self.calls.add(token)
            if token == "startsWith" and len(arguments) == 2:
                return str(arguments[0]).casefold().startswith(str(arguments[1]).casefold())
            if token in self.STATUS_FUNCTIONS and not arguments:
                return self.context[token]
            raise AssertionError(f"Unsupported workflow condition function: {token}")
        if token == "true":
            return True
        if token == "false":
            return False
        if not token.startswith(("github.", "needs.")):
            raise AssertionError(f"Unsupported workflow condition property: {token}")
        # Missing outputs are the empty string in Actions, not boolean false.
        return self.context.get(token, "")


def job_condition(job, context):
    evaluator = ActionsCondition(job.get("if", "success()"), context)
    actual = evaluator.evaluate()
    # GitHub applies success() implicitly unless an explicit status function
    # occurs. This matters because the reset job intentionally lacks always().
    if not evaluator.calls & evaluator.STATUS_FUNCTIONS:
        actual = actual and context["success"]
    return actual


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
        self.assertIn("needs.check.outputs.demo_reset_enabled == 'true'", condition)
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

    def test_policy_is_resolved_once_in_check_from_a_non_secret_repository_variable(self):
        check = self.build["jobs"]["check"]
        self.assertEqual(
            check["outputs"]["demo_reset_enabled"],
            "${{ steps.demo-policy.outputs.enabled }}",
        )
        steps = [step for step in check["steps"] if step.get("id") == "demo-policy"]
        self.assertEqual(len(steps), 1)
        step = steps[0]
        self.assertEqual(step["run"], "python3 scripts/demo_database_policy.py")
        self.assertEqual(
            step["env"]["DEMO_DATABASE_RESET_ENABLED"],
            "${{ vars.DEMO_DATABASE_RESET_ENABLED }}",
        )
        self.assertNotIn("continue-on-error", step)
        self.assertNotIn("secrets.", job_text(step))

    def test_publish_and_pages_depend_on_the_checked_policy_and_completed_builds(self):
        publish = self.build["jobs"]["publish"]
        self.assertEqual(needs(publish), {"check", "web", "android", "ios", "demo-database-reset"})
        self.assertIn("needs.demo-database-reset.result == 'success'", publish["if"])
        self.assertIn("needs.demo-database-reset.result == 'skipped'", publish["if"])
        self.assertIn("startsWith(github.ref, 'refs/tags/v')", publish["if"])
        settings = self.build["jobs"]["pages-settings"]
        self.assertEqual(needs(settings), {"check", "web", "android", "ios", "demo-database-reset"})
        for job in (publish, settings):
            self.assertIn("always()", job["if"])
            self.assertIn("!cancelled()", job["if"])
            for required in ("check", "web", "android", "ios"):
                self.assertIn(f"needs.{required}.result == 'success'", job["if"])
        pages = self.build["jobs"]["pages"]
        self.assertIn("pages-settings", needs(pages))
        self.assertIn("always()", pages["if"])
        self.assertIn("!cancelled()", pages["if"])
        self.assertIn("needs.pages-settings.result == 'success'", pages["if"])


class DatabaseActivationTruthTableTests(unittest.TestCase):
    def setUp(self):
        self.jobs = workflow("build.yml")["jobs"]

    def evaluate(self, name, event="push", ref="refs/heads/main", enabled="false",
                 reset="skipped", build_results=None, cancelled=False,
                 pages_result="success", configured="true"):
        results = {name: "success" for name in ("check", "web", "android", "ios")}
        results.update(build_results or {})
        results["demo-database-reset"] = reset
        results["database-ci"] = "success"
        results["pages-settings"] = pages_result

        def ancestors(job_name):
            found = set()
            pending = list(needs(self.jobs[job_name]))
            while pending:
                dependency = pending.pop()
                if dependency not in found:
                    found.add(dependency)
                    pending.extend(needs(self.jobs[dependency]))
            return found

        upstream = ancestors(name)
        context = {
            "github.event_name": event,
            "github.ref": ref,
            "needs.check.outputs.demo_reset_enabled": enabled,
            "needs.pages-settings.outputs.configured": configured,
            "always": True,
            "cancelled": cancelled,
            "success": all(results.get(dependency) == "success" for dependency in upstream),
            "failure": any(results.get(dependency) == "failure" for dependency in upstream),
        }
        context.update({f"needs.{job}.result": result for job, result in results.items()})
        return job_condition(self.jobs[name], context)

    def test_main_publication_truth_table_requires_exact_activation_and_reset_pair(self):
        for enabled in ("", "false", "true", "invalid"):
            for reset in ("skipped", "success", "failure", "cancelled", ""):
                allowed = (enabled, reset) in {("false", "skipped"), ("true", "success")}
                for job in ("publish", "pages-settings"):
                    with self.subTest(job=job, enabled=enabled, reset=reset):
                        self.assertEqual(self.evaluate(job, enabled=enabled, reset=reset), allowed)

    def test_remote_reset_runs_only_when_enabled_on_main_push_or_manual(self):
        cases = (
            ("push", "refs/heads/main", True),
            ("workflow_dispatch", "refs/heads/main", True),
            ("pull_request", "refs/pull/45/merge", False),
            ("pull_request", "refs/heads/main", False),
            ("push", "refs/tags/v0.0.12-pre.1", False),
            ("push", "refs/heads/feature/test", False),
            ("workflow_dispatch", "refs/heads/feature/test", False),
        )
        for event, ref, trusted in cases:
            for enabled in ("", "false", "true", "invalid"):
                with self.subTest(event=event, ref=ref, enabled=enabled):
                    self.assertEqual(
                        self.evaluate("demo-database-reset", event, ref, enabled),
                        trusted and enabled == "true",
                    )

    def test_pr_and_feature_manual_never_publish_or_deploy(self):
        for event, ref in (
            ("pull_request", "refs/pull/45/merge"),
            ("pull_request", "refs/heads/main"),
            ("workflow_dispatch", "refs/heads/feature/test"),
            ("push", "refs/heads/feature/test"),
        ):
            for enabled, reset in (("false", "skipped"), ("true", "success")):
                for job in ("publish", "pages-settings"):
                    with self.subTest(event=event, ref=ref, job=job, enabled=enabled):
                        self.assertFalse(self.evaluate(job, event, ref, enabled, reset))

    def test_main_manual_can_update_pages_but_does_not_create_release(self):
        for enabled, reset in (("false", "skipped"), ("true", "success")):
            with self.subTest(enabled=enabled):
                self.assertTrue(self.evaluate("pages-settings", "workflow_dispatch", enabled=enabled, reset=reset))
                self.assertFalse(self.evaluate("publish", "workflow_dispatch", enabled=enabled, reset=reset))

    def test_release_tag_never_resets_demo_and_only_publishes_with_skipped_reset(self):
        for enabled in ("", "false", "true"):
            for reset in ("skipped", "success", "failure", "cancelled", ""):
                for job in ("publish", "pages-settings", "demo-database-reset"):
                    with self.subTest(job=job, enabled=enabled, reset=reset):
                        self.assertEqual(
                            self.evaluate(job, ref="refs/tags/v0.0.12-pre.1", enabled=enabled, reset=reset),
                            job == "publish" and reset == "skipped",
                        )

    def test_each_failed_cancelled_or_skipped_build_blocks_every_followup(self):
        for build in ("check", "web", "android", "ios"):
            for result in ("failure", "cancelled", "skipped", ""):
                for enabled, reset in (("false", "skipped"), ("true", "success")):
                    for job in ("demo-database-reset", "publish", "pages-settings"):
                        with self.subTest(build=build, result=result, job=job, enabled=enabled):
                            self.assertFalse(self.evaluate(
                                job, enabled=enabled, reset=reset, build_results={build: result}
                            ))

    def test_cancelled_workflow_does_not_publish_or_update_pages(self):
        for enabled, reset in (("false", "skipped"), ("true", "success")):
            for job in ("publish", "pages-settings", "pages"):
                with self.subTest(job=job, enabled=enabled):
                    self.assertFalse(self.evaluate(job, enabled=enabled, reset=reset, cancelled=True))

    def test_pages_runs_after_successful_settings_even_when_demo_ancestor_is_intentionally_skipped(self):
        self.assertTrue(self.evaluate("pages", enabled="false", reset="skipped"))
        self.assertTrue(self.evaluate("pages", enabled="true", reset="success"))

    def test_pages_requires_successful_settings_and_an_explicit_configured_output(self):
        for result in ("success", "failure", "cancelled", "skipped", ""):
            for configured in ("true", "false", "", "invalid"):
                with self.subTest(result=result, configured=configured):
                    self.assertEqual(
                        self.evaluate("pages", pages_result=result, configured=configured),
                        result == "success" and configured == "true",
                    )


if __name__ == "__main__":
    unittest.main()
