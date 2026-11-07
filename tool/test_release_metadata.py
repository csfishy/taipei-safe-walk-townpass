"""Exercise release identity across push, PR, manual-tag and retry contexts."""
import contextlib
import io
import json
import os
from pathlib import Path
import runpy
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).with_name('release_metadata.py')
COMMIT = 'a' * 40


class ReleaseMetadataTest(unittest.TestCase):
    def generate(self, **env):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'assets').mkdir()
            (root / 'pubspec.yaml').write_text('version: 0.0.12-pre.1+1\n')
            (root / '.fvmrc').write_text('{"flutter": "3.47.6"}')
            output = root / 'output.txt'
            environment = {'GITHUB_OUTPUT': str(output), **env}
            with contextlib.chdir(root), patch.dict(os.environ, environment, clear=True), \
                    patch('subprocess.check_output', return_value=COMMIT), \
                    contextlib.redirect_stdout(io.StringIO()):
                runpy.run_path(str(SCRIPT), run_name='__main__')
            return json.loads((root / 'assets/build-info.json').read_text()), output.read_text()

    def test_main_push_has_unique_traceable_identity_and_stable_retry(self):
        env = dict(COMMIT_PRERELEASE='true', GITHUB_EVENT_NAME='push',
                   GITHUB_REF='refs/heads/main', GITHUB_SHA=COMMIT, GITHUB_RUN_NUMBER='42')
        metadata, output = self.generate(**env)
        self.assertEqual(metadata['version'], '0.0.12-pre.r0000000042.gaaaaaaaaaaaa')
        self.assertEqual(metadata['buildNumber'], '42')
        self.assertEqual(metadata['commit'], COMMIT)
        self.assertIn('build_name=0.0.12\n', output)
        self.assertIn('release_tag=v0.0.12-pre.r0000000042.gaaaaaaaaaaaa\n', output)
        self.assertEqual((metadata, output), self.generate(**env))
        self.assertNotEqual(metadata['version'], self.generate(**{**env, 'GITHUB_RUN_NUMBER': '43'})[0]['version'])

    def test_release_list_order_survives_digit_boundaries_and_legacy_tags(self):
        env = dict(COMMIT_PRERELEASE='true', GITHUB_EVENT_NAME='push',
                   GITHUB_REF='refs/heads/main', GITHUB_SHA=COMMIT)
        versions = [self.generate(**env, GITHUB_RUN_NUMBER=str(run))[0]['version']
                    for run in (9, 10, 84, 99, 100, 135, 999, 1000, 9999999999)]
        self.assertEqual(sorted(versions, reverse=True), versions[::-1])
        legacy = ['0.0.12-pre.1', '0.0.12-pre.84.gaaaaaaaaaaaa',
                  '0.0.12-pre.135.gaaaaaaaaaaaa', '0.0.12-pre.9999999999.gaaaaaaaaaaaa']
        self.assertGreater(min(versions), max(legacy))

    def test_automatic_counter_cannot_overflow_fixed_width(self):
        with self.assertRaises(SystemExit):
            self.generate(COMMIT_PRERELEASE='true', GITHUB_EVENT_NAME='push',
                          GITHUB_REF='refs/heads/main', GITHUB_RUN_NUMBER='10000000000')

    def test_pr_and_local_builds_keep_pubspec_version(self):
        for env in ({}, {'GITHUB_EVENT_NAME': 'pull_request', 'GITHUB_REF': 'refs/pull/7/merge',
                         'GITHUB_RUN_NUMBER': '43', 'COMMIT_PRERELEASE': 'false'}):
            with self.subTest(env=env):
                metadata, _ = self.generate(**env)
                self.assertEqual(metadata['version'], '0.0.12-pre.1')

    def test_matching_manual_tag_is_supported(self):
        metadata, output = self.generate(GITHUB_REF='refs/tags/v0.0.12-pre.1', GITHUB_RUN_NUMBER='44')
        self.assertEqual(metadata['version'], '0.0.12-pre.1')
        self.assertIn('release_tag=v0.0.12-pre.1\n', output)

    def test_wrong_tag_checkout_and_invalid_build_number_fail(self):
        for env in ({'GITHUB_REF': 'refs/tags/v0.0.13-pre.1'},
                    {'GITHUB_SHA': 'b' * 40}, {'GITHUB_RUN_NUMBER': 'bad'},
                    {'GITHUB_RUN_NUMBER': '0'}):
            with self.subTest(env=env), self.assertRaises(SystemExit):
                self.generate(**env)

    def test_automatic_mode_cannot_be_enabled_on_pr_manual_or_feature_branch(self):
        for event, ref in (('pull_request', 'refs/heads/main'),
                           ('workflow_dispatch', 'refs/heads/main'),
                           ('push', 'refs/heads/feature')):
            with self.subTest(event=event, ref=ref), self.assertRaises(SystemExit):
                self.generate(COMMIT_PRERELEASE='true', GITHUB_EVENT_NAME=event, GITHUB_REF=ref)


if __name__ == '__main__':
    unittest.main()
