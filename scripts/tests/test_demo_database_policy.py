"""An explicit activation policy must not enable destructive work by accident."""

import contextlib
import importlib.util
import io
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "demo_database_policy", ROOT / "scripts" / "demo_database_policy.py"
)
policy = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(policy)


class DemoDatabasePolicyTests(unittest.TestCase):
    def test_only_the_exact_true_value_enables_remote_reset(self):
        self.assertFalse(policy.resolve_activation(""))
        self.assertFalse(policy.resolve_activation("false"))
        self.assertTrue(policy.resolve_activation("true"))

    def test_ambiguous_values_are_rejected_instead_of_guessed(self):
        for value in ("TRUE", "True", "FALSE", "False", "0", "1", "yes", "no",
                      "off", " true", "true ", "false\n", "unrecognised"):
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    policy.resolve_activation(value)

    def run_main(self, directory, value=None, **overrides):
        output = directory / "output"
        summary = directory / "summary"
        environment = {"GITHUB_OUTPUT": str(output), "GITHUB_STEP_SUMMARY": str(summary)}
        if value is not None:
            environment["DEMO_DATABASE_RESET_ENABLED"] = value
        environment.update(overrides)
        stdout, stderr = io.StringIO(), io.StringIO()
        with mock.patch.dict(os.environ, environment, clear=True):
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                result = policy.main()
        return result, output, summary, stdout.getvalue() + stderr.getvalue()

    def test_missing_and_false_configuration_write_a_disabled_output_and_summary(self):
        for value in (None, "", "false"):
            with self.subTest(value=value), tempfile.TemporaryDirectory() as temporary:
                result, output, summary, _ = self.run_main(Path(temporary), value)
                self.assertEqual(result, 0)
                self.assertEqual(output.read_text(encoding="utf-8"), "enabled=false\n")
                self.assertIn("disabled", summary.read_text(encoding="utf-8").lower())

    def test_enabled_configuration_writes_true_and_describes_the_required_reset(self):
        with tempfile.TemporaryDirectory() as temporary:
            result, output, summary, _ = self.run_main(Path(temporary), "true")
            self.assertEqual(result, 0)
            self.assertEqual(output.read_text(encoding="utf-8"), "enabled=true\n")
            self.assertIn("enabled", summary.read_text(encoding="utf-8").lower())

    def test_actions_output_and_summary_are_appended_without_losing_prior_steps(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / "output").write_text("previous=value\n", encoding="utf-8")
            (directory / "summary").write_text("Previous step\n", encoding="utf-8")
            result, output, summary, _ = self.run_main(directory, "false")
            self.assertEqual(result, 0)
            self.assertEqual(output.read_text(encoding="utf-8"), "previous=value\nenabled=false\n")
            self.assertTrue(summary.read_text(encoding="utf-8").startswith("Previous step\n"))

    def test_invalid_configuration_fails_without_echoing_input_or_publishing_output(self):
        for value in ("TRUE", "private-config-do-not-echo", "true\nenabled=true"):
            with self.subTest(value=value), tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary)
                result, output, _, diagnostics = self.run_main(directory, value)
                self.assertEqual(result, 1)
                self.assertNotIn(value, diagnostics)
                self.assertTrue(diagnostics.strip(), "Failure needs a fixed actionable diagnostic")
                self.assertFalse(output.exists() and output.read_text(encoding="utf-8"))

    def test_missing_actions_output_path_fails_without_claiming_success(self):
        with tempfile.TemporaryDirectory() as temporary:
            result, _, _, _ = self.run_main(Path(temporary), "true", GITHUB_OUTPUT="")
            self.assertEqual(result, 1)

    def test_summary_path_is_optional_for_local_policy_validation(self):
        with tempfile.TemporaryDirectory() as temporary:
            result, output, summary, _ = self.run_main(Path(temporary), "false", GITHUB_STEP_SUMMARY="")
            self.assertEqual(result, 0)
            self.assertEqual(output.read_text(encoding="utf-8"), "enabled=false\n")
            self.assertFalse(summary.exists())

    def test_unwritable_output_fails_instead_of_silently_skipping_the_reset(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            result, _, _, _ = self.run_main(directory, "true", GITHUB_OUTPUT=str(directory))
            self.assertEqual(result, 1)


if __name__ == "__main__":
    unittest.main()
