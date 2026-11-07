"""Verify current and previously published native build metadata formats."""
from contextlib import redirect_stdout
import io
import json
from pathlib import Path
import plistlib
import struct
import tempfile
import unittest
import zipfile

from verify_native_release import PREVIEW_ID, read_client_config, validate_metadata, verify


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


class NativeReleaseClientConfigurationTest(unittest.TestCase):
    # Deliberately artificial public inputs. No live account or data is used.
    client = {
        'SUPABASE_URL': 'https://reference.example.test/',
        'SUPABASE_PUBLISHABLE_KEY': 'sb_publishable_artificial_client',
    }

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.config = self.root / 'client.json'
        self.config.write_text(json.dumps(self.client), encoding='utf-8')
        self.metadata = NativeReleaseMetadataTest().metadata()
        self.metadata_path = self.root / 'metadata.json'
        self.metadata_path.write_text(json.dumps(self.metadata), encoding='utf-8')

    def package(self, platform, compiled_values, *, wrapper_values=b''):
        path = self.root / (platform + '.zip')
        mach_header = struct.pack('<II', 0xFEEDFACF, 0x0100000C)
        with zipfile.ZipFile(path, 'w') as package:
            if platform == 'android':
                binary = bytearray(20)
                binary[:4] = b'\x7fELF'
                struct.pack_into('<H', binary, 18, 183)
                package.writestr('lib/arm64-v8a/libapp.so', bytes(binary) + compiled_values)
                package.writestr('classes.dex', wrapper_values)
                package.writestr('AndroidManifest.xml', PREVIEW_ID.encode())
                asset = 'assets/flutter_assets/assets/build-info.json'
            else:
                app = 'Payload/Runner.app/'
                package.writestr(app + 'Info.plist', plistlib.dumps({
                    'CFBundleIdentifier': PREVIEW_ID,
                    'CFBundleShortVersionString': '0.0.12',
                    'CFBundleVersion': '152',
                    'CFBundleExecutable': 'Runner',
                }))
                package.writestr(app + 'Runner', mach_header + wrapper_values)
                package.writestr(app + 'Frameworks/App.framework/App', mach_header + compiled_values)
                asset = app + 'Frameworks/App.framework/flutter_assets/assets/build-info.json'
            package.writestr(asset, json.dumps(self.metadata))
            package.writestr('unused-client-config.json', json.dumps(self.client))
        return path

    def encoded_values(self, encoding='utf-8'):
        return b'\0'.join(value.encode(encoding) for value in self.client.values())

    def test_both_platforms_require_matching_configuration_in_aot(self):
        for platform in ('ios', 'android'):
            for encoding in ('utf-8', 'utf-16le'):
                with self.subTest(platform=platform, encoding=encoding), redirect_stdout(io.StringIO()):
                    verify(platform, self.package(platform, self.encoded_values(encoding)),
                           self.metadata_path, self.config)

    def test_settings_in_assets_or_wrapper_do_not_satisfy_aot_check(self):
        for platform in ('ios', 'android'):
            with self.subTest(platform=platform), self.assertRaisesRegex(ValueError, 'AOT payload is missing'):
                verify(platform, self.package(platform, b'', wrapper_values=self.encoded_values()),
                       self.metadata_path, self.config)

    def test_partial_or_wrong_configuration_is_rejected(self):
        for values in (self.client['SUPABASE_URL'].encode(),
                       self.client['SUPABASE_PUBLISHABLE_KEY'].encode(),
                       b'https://other.example.test/\0sb_publishable_different'):
            with self.subTest(values=bool(values)), self.assertRaisesRegex(ValueError, 'AOT payload is missing'):
                verify('ios', self.package('ios', values), self.metadata_path, self.config)

    def test_invalid_and_secret_inputs_never_appear_in_errors(self):
        for value in ({}, {'SUPABASE_URL': '', 'SUPABASE_PUBLISHABLE_KEY': ''},
                      {**self.client, 'SUPABASE_PUBLISHABLE_KEY': 'sb_secret_never_echo'},
                      {**self.client, 'SUPABASE_URL': 'https://user:password@example.test'},
                      {**self.client, 'SUPABASE_URL': None}, []):
            self.config.write_text(json.dumps(value), encoding='utf-8')
            with self.subTest(value_type=type(value).__name__), self.assertRaises(ValueError) as error:
                read_client_config(self.config)
            self.assertEqual(str(error.exception), 'Could not validate the public client configuration')

    def test_output_does_not_print_public_key_or_url(self):
        output = io.StringIO()
        with redirect_stdout(output):
            verify('ios', self.package('ios', self.encoded_values()), self.metadata_path, self.config)
        for value in self.client.values():
            self.assertNotIn(value, output.getvalue())


if __name__ == '__main__':
    unittest.main()
