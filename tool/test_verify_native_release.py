"""Verify current and previously published native build metadata formats."""
import unittest

from verify_native_release import validate_metadata


class NativeReleaseMetadataTest(unittest.TestCase):
    def metadata(self, **changes):
        return {
            'preview': True,
            'commit': 'a' * 40,
            'version': '0.0.12-pre.r0000000152.gaaaaaaaaaaaa',
            'buildNumber': '152',
            **changes,
        }

    def test_current_and_legacy_prerelease_formats_are_accepted(self):
        for version in ('0.0.12-pre.1', '0.0.12-pre.135.gaaaaaaaaaaaa',
                        '0.0.12-pre.r0000000152.gaaaaaaaaaaaa'):
            with self.subTest(version=version):
                validate_metadata(self.metadata(version=version))

    def test_new_format_requires_fixed_width_and_complete_lowercase_hash(self):
        for version in ('0.0.12-pre.r152.gaaaaaaaaaaaa',
                        '0.0.12-pre.r00000000152.gaaaaaaaaaaaa',
                        '0.0.12-pre.r０００００００１５２.gaaaaaaaaaaaa',
                        '0.0.12-pre.r0000000152',
                        '0.0.12-pre.r0000000152.gaaaaaaaaaaa',
                        '0.0.12-pre.r0000000152.gaaaaaaaaaaaaa',
                        '0.0.12-pre.r0000000152.gAAAAAAAAAAAA',
                        '0.0.12-pre.r0000000152.ggggggggggggg'):
            with self.subTest(version=version), self.assertRaisesRegex(ValueError, 'prerelease version'):
                validate_metadata(self.metadata(version=version))

    def test_existing_metadata_validation_is_preserved(self):
        for change, message in (({'preview': False}, 'preview build metadata'),
                                ({'preview': 'true'}, 'preview build metadata'),
                                ({'commit': 'a' * 39}, 'source commit'),
                                ({'commit': 'A' * 40}, 'source commit'),
                                ({'version': '0.0.12'}, 'prerelease version'),
                                ({'version': '0.0.12-pre.1.gshort'}, 'prerelease version'),
                                ({'buildNumber': '-1'}, 'build number'),
                                ({'buildNumber': 'bad'}, 'build number')):
            with self.subTest(change=change), self.assertRaisesRegex(ValueError, message):
                validate_metadata(self.metadata(**change))

    def test_missing_required_metadata_is_rejected(self):
        for field in ('preview', 'commit', 'version', 'buildNumber'):
            metadata = self.metadata()
            del metadata[field]
            with self.subTest(field=field), self.assertRaises(ValueError):
                validate_metadata(metadata)


if __name__ == '__main__':
    unittest.main()
