"""Validate preview native packages against the current build metadata."""
import argparse
import json
from pathlib import Path
import plistlib
import re
import struct
import zipfile

PREVIEW_ID = 'io.github.csfishy.taipeisafewalktownpass.preview'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def verify(platform, package_path, metadata_path):
    expected = json.loads(Path(metadata_path).read_text(encoding='utf-8'))
    require(expected.get('preview') is True, 'Expected preview build metadata')
    require(re.fullmatch(r'[0-9a-f]{40}', expected.get('commit', '')), 'Invalid source commit')
    require(re.fullmatch(r'\d+\.\d+\.\d+-pre\.\d+(?:\.g[0-9a-f]{12})?', expected.get('version', '')), 'Expected prerelease version')
    require(str(expected.get('buildNumber', '')).isdigit(), 'Invalid build number')

    with zipfile.ZipFile(package_path) as package:
        require(package.testzip() is None, 'Package ZIP integrity check failed')
        if platform == 'android':
            asset = 'assets/flutter_assets/assets/build-info.json'
            require('classes.dex' in package.namelist(), 'APK is missing compiled DEX')
            manifest = package.read('AndroidManifest.xml')
            require(
                PREVIEW_ID.encode() in manifest or PREVIEW_ID.encode('utf-16le') in manifest,
                'APK does not contain the preview application identifier',
            )
            binary = package.read('lib/arm64-v8a/libapp.so')
            require(
                binary[:4] == b'\x7fELF' and len(binary) >= 20
                and struct.unpack('<H', binary[18:20])[0] == 183,
                'APK is missing arm64 Flutter AOT code',
            )
        else:
            app = 'Payload/Runner.app/'
            info = plistlib.loads(package.read(app + 'Info.plist'))
            require(info['CFBundleIdentifier'] == PREVIEW_ID, 'Unexpected iOS bundle identifier')
            require(
                info['CFBundleShortVersionString'] == expected['version'].split('-')[0],
                'iOS marketing version does not match this build',
            )
            require(str(info['CFBundleVersion']) == expected['buildNumber'], 'iOS build number mismatch')
            require(app + '_CodeSignature/CodeResources' not in package.namelist(), 'IPA app is signed')
            require(app + 'embedded.mobileprovision' not in package.namelist(), 'Unexpected iOS provisioning profile')
            binary = package.read(app + info['CFBundleExecutable'])
            require(
                len(binary) >= 8 and struct.unpack('<II', binary[:8]) == (0xFEEDFACF, 0x0100000C),
                'IPA must contain an arm64 iPhone device executable',
            )
            asset = app + 'Frameworks/App.framework/flutter_assets/assets/build-info.json'
        require(json.loads(package.read(asset)) == expected, 'Embedded metadata does not match this source/build')

    print(f'PASS: {platform} preview package, arm64 code and embedded source/version metadata')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('platform', choices=('android', 'ios'))
    parser.add_argument('package', type=Path)
    parser.add_argument('--metadata', type=Path, default=Path('assets/build-info.json'))
    args = parser.parse_args()
    try:
        verify(args.platform, args.package, args.metadata)
    except (ValueError, KeyError, OSError, zipfile.BadZipFile, plistlib.InvalidFileException) as error:
        raise SystemExit(f'Native release verification failed: {error}') from error
