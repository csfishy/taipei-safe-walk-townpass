"""Exercise release retries and source guards without writing to GitHub."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from publish_prerelease import ASSETS, publish


COMMIT = 'a' * 40
TAG = 'v0.0.12-pre.42.g' + COMMIT[:12]


class PublishPrereleaseTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.metadata = {'version': TAG[1:], 'commit': COMMIT, 'preview': True, 'buildNumber': '42'}
        for name in ASSETS:
            (self.root / name).write_text('package', encoding='utf-8')
        (self.root / 'build-info.json').write_text(json.dumps(self.metadata), encoding='utf-8')
        self.notes = self.root / 'notes.md'
        self.notes.write_text('Preview limitations', encoding='utf-8')
        self.addCleanup(patch.stopall)
        patch.dict(os.environ, {'GH_REPO': 'example/townpass', 'GITHUB_SHA': COMMIT,
                               'GITHUB_RUN_ID': '123'}, clear=True).start()
        self.source = None
        self.ref_type = 'commit'
        self.release = None
        self.api_error = None
        self.upload_error = None
        self.download_metadata = self.metadata
        self.commands = []
        self.create_notes = ''
        self.runner = patch('publish_prerelease.subprocess.run', side_effect=self.run_gh).start()

    def run_gh(self, command, **kwargs):
        self.commands.append(command)
        if command[1] == 'api':
            if self.api_error:
                return subprocess.CompletedProcess(command, 1, '', self.api_error)
            if '/releases?' in command[2]:
                response = [[self.release]] if self.release else [[]]
            elif '/git/ref/tags/' in command[2]:
                response = None if self.source is None else {
                    'ref': f'refs/tags/{TAG}', 'object': {'type': self.ref_type, 'sha': self.source['sha']}}
            elif '/commits/' in command[2]:
                if self.source is None:
                    return subprocess.CompletedProcess(command, 1, '', 'gh: No commit found for SHA (HTTP 422)')
                response = self.source
            else:
                response = self.release if self.release and not self.release['draft'] else None
            if response is None:
                return subprocess.CompletedProcess(command, 1, '', 'gh: Not Found (HTTP 404)')
            return subprocess.CompletedProcess(command, 0, json.dumps(response), '')
        if command[1:3] == ['release', 'download']:
            destination = Path(command[command.index('--dir') + 1], 'build-info.json')
            destination.write_text(json.dumps(self.download_metadata), encoding='utf-8')
        if command[1:3] == ['release', 'create']:
            self.create_notes = Path(command[command.index('--notes-file') + 1]).read_text(encoding='utf-8')
        if command[1:3] == ['release', 'upload'] and self.upload_error:
            return subprocess.CompletedProcess(command, 1, '', self.upload_error)
        return subprocess.CompletedProcess(command, 0, '', '')

    def invoke(self):
        publish(TAG, self.root, self.notes)

    def complete_release(self, draft=False):
        self.source = {'sha': COMMIT}
        self.release = {'tag_name': TAG, 'draft': draft, 'prerelease': True,
                        'target_commitish': COMMIT,
                        'assets': [{'name': name, 'size': 1, 'state': 'uploaded'} for name in ASSETS]}

    def release_commands(self):
        return [command[2] for command in self.commands if command[1] == 'release']

    def test_new_release_stays_draft_until_all_assets_uploaded(self):
        self.invoke()
        self.assertEqual(self.release_commands(), ['create', 'upload', 'edit'])
        create, upload, edit = [command for command in self.commands if command[1] == 'release']
        self.assertIn('--draft', create)
        self.assertEqual(create[create.index('--target') + 1], COMMIT)
        self.assertIn(COMMIT, self.create_notes)
        self.assertIn('/actions/runs/123', self.create_notes)
        for name in ASSETS:
            self.assertIn(str(self.root / name), upload)
        self.assertIn('--draft=false', edit)
        self.assertIn('--prerelease=true', edit)
        self.assertIn('--latest=false', edit)

    def test_missing_tag_uses_ref_probe_without_querying_missing_commit(self):
        self.invoke()
        self.assertTrue(any('/git/ref/tags/' in command[2] for command in self.commands if command[1] == 'api'))
        self.assertFalse(any('/commits/' in command[2] for command in self.commands if command[1] == 'api'))

    def test_complete_published_release_rerun_does_not_write(self):
        self.complete_release()
        self.invoke()
        self.assertEqual(self.release_commands(), ['download'])

    def test_annotated_tag_is_resolved_to_its_commit(self):
        self.complete_release()
        self.ref_type = 'tag'
        self.invoke()
        self.assertEqual(self.release_commands(), ['download'])
        self.assertTrue(any('/commits/refs%2Ftags%2F' in command[2]
                            for command in self.commands if command[1] == 'api'))

    def test_partial_draft_resumes_upload_then_publish(self):
        self.complete_release(draft=True)
        self.release['assets'] = []
        self.invoke()
        self.assertEqual(self.release_commands(), ['upload', 'edit'])
        self.assertIn('--clobber', self.commands[-2])

    def test_upload_failure_leaves_draft_unpublished(self):
        self.upload_error = 'connection reset'
        with self.assertRaisesRegex(ValueError, 'connection reset'):
            self.invoke()
        self.assertEqual(self.release_commands(), ['create', 'upload'])

    def test_draft_without_tag_resumes_only_for_exact_target_sha(self):
        self.complete_release(draft=True)
        self.source = None
        self.invoke()
        self.assertEqual(self.release_commands(), ['upload', 'edit'])

    def test_wrong_tag_source_is_refused_even_without_release(self):
        self.source = {'sha': 'b' * 40}
        with self.assertRaisesRegex(ValueError, 'another source commit'):
            self.invoke()
        self.assertEqual(self.release_commands(), [])

    def test_published_metadata_mismatch_is_refused(self):
        self.complete_release()
        self.download_metadata = dict(self.metadata, buildNumber='43')
        with self.assertRaisesRegex(ValueError, 'metadata does not match'):
            self.invoke()
        self.assertEqual(self.release_commands(), ['download'])

    def test_incomplete_published_release_is_not_mutated(self):
        self.complete_release()
        self.release['assets'].pop()
        with self.assertRaisesRegex(ValueError, 'incomplete'):
            self.invoke()
        self.assertEqual(self.release_commands(), [])

    def test_non_404_api_failure_does_not_create_release(self):
        self.api_error = 'gh: Service Unavailable (HTTP 503)'
        with self.assertRaisesRegex(ValueError, 'HTTP 503'):
            self.invoke()
        self.assertEqual(self.release_commands(), [])

    def test_unverifiable_draft_target_is_refused(self):
        self.complete_release(draft=True)
        self.source = None
        self.release['target_commitish'] = 'main'
        with self.assertRaisesRegex(ValueError, 'source cannot be verified'):
            self.invoke()
        self.assertEqual(self.release_commands(), [])


if __name__ == '__main__':
    unittest.main()
