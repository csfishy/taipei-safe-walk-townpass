"""Validate preview native packages against the current build metadata."""
import argparse
import json
from pathlib import Path
import plistlib
import re
import struct
import zipfile
from urllib.parse import urlsplit

PREVIEW_ID = 'io.github.csfishy.taipeisafewalktownpass.preview'
PRERELEASE_VERSION = re.compile(
    r'\d+\.\d+\.\d+-pre\.'
    r'(?:\d+(?:\.g[0-9a-f]{12})?|r[0-9]{10}\.g[0-9a-f]{12})'
)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def validate_metadata(expected):
    require(expected.get('preview') is True, 'Expected preview build metadata')
    require(re.fullmatch(r'[0-9a-f]{40}', expected.get('commit', '')), 'Invalid source commit')
    require(PRERELEASE_VERSION.fullmatch(expected.get('version', '')), 'Expected prerelease version')
    require(str(expected.get('buildNumber', '')).isdigit(), 'Invalid build number')


def read_client_config(config_path):
    """Read only public build inputs, with errors that never echo their values."""
    try:
        value = json.loads(Path(config_path).read_text(encoding='utf-8'))
        url = value['SUPABASE_URL']
        key = value['SUPABASE_PUBLISHABLE_KEY']
        require(isinstance(url, str) and isinstance(key, str), 'Invalid public client configuration')
        origin = urlsplit(url)
        require(
            origin.scheme == 'https' and origin.hostname
            and not origin.username and not origin.password
            and origin.path in ('', '/') and not origin.query and not origin.fragment
            and re.fullmatch(r'sb_publishable_[A-Za-z0-9_-]+', key),
            'Invalid public client configuration',
        )
    except (OSError, ValueError, KeyError, TypeError):
        raise ValueError('Could not validate the public client configuration') from None
    return url, key


def verify_compiled_client(binary, config_path):
    # These are client-visible constants, not a database password. Search the
    # actual AOT payload: config only in an asset or app wrapper is insufficient.
    # This guards injection, not server availability or device acceptance.
    for value in read_client_config(config_path):
        require(
            value.encode('utf-8') in binary or value.encode('utf-16le') in binary,
            'Flutter AOT payload is missing the expected public client configuration',
        )


def arm64_macho_slice(binary):
    """Select a bounded arm64 Mach-O image from a thin or Apple fat binary."""
    arm64 = 0x0100000C

    def thin_arm64(image):
        require(
            len(image) >= 32 and struct.unpack_from('<II', image) == (0xFEEDFACF, arm64),
            'Mach-O image must contain a complete arm64 header',
        )
        commands_size = struct.unpack_from('<I', image, 20)[0]
        require(commands_size <= len(image) - 32, 'Mach-O load commands exceed the image')
        return image

    require(len(binary) >= 4, 'Mach-O header is truncated')
    magic = struct.unpack_from('>I', binary)[0]
    if magic not in (0xCAFEBABE, 0xCAFEBABF):
        return thin_arm64(binary)

    require(len(binary) >= 8, 'Mach-O fat header is truncated')
    count = struct.unpack_from('>I', binary, 4)[0]
    entry_size = 20 if magic == 0xCAFEBABE else 32
    require(0 < count <= (len(binary) - 8) // entry_size, 'Mach-O fat table is truncated or empty')
    table_end = 8 + count * entry_size
    intervals = []
    selected = []
    for index in range(count):
        entry = 8 + index * entry_size
        if entry_size == 20:
            cpu, _, offset, size, alignment = struct.unpack_from('>IIIII', binary, entry)
        else:
            cpu, _, offset, size, alignment, _ = struct.unpack_from('>IIQQII', binary, entry)
        require(
            offset >= table_end and size > 0 and offset <= len(binary)
            and size <= len(binary) - offset,
            'Mach-O fat slice is outside the file or overlaps its table',
        )
        require(alignment <= 63 and offset % (1 << alignment) == 0, 'Mach-O fat slice is misaligned')
        intervals.append((offset, offset + size))
        if cpu == arm64:
            selected.append((offset, size))
    intervals.sort()
    require(
        all(left[1] <= right[0] for left, right in zip(intervals, intervals[1:])),
        'Mach-O fat slices overlap',
    )
    # Do not accidentally validate a different arm64 variant than the device
    # chooses. Current iPhone packages contain one unambiguous arm64 slice.
    require(len(selected) == 1, 'Mach-O fat binary must contain one unambiguous arm64 slice')
    offset, size = selected[0]
    return thin_arm64(binary[offset:offset + size])


def verify(platform, package_path, metadata_path, supabase_config_path=None):
    expected = json.loads(Path(metadata_path).read_text(encoding='utf-8'))
    validate_metadata(expected)

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
            aot_binary = binary
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
            arm64_macho_slice(binary)
            asset = app + 'Frameworks/App.framework/flutter_assets/assets/build-info.json'
            if supabase_config_path is not None:
                aot_binary = arm64_macho_slice(
                    package.read(app + 'Frameworks/App.framework/App'),
                )
        require(json.loads(package.read(asset)) == expected, 'Embedded metadata does not match this source/build')
        if supabase_config_path is not None:
            verify_compiled_client(aot_binary, supabase_config_path)

    print(f'PASS: {platform} preview package, arm64 code and embedded source/version metadata')
    if supabase_config_path is not None:
        print('PASS: expected public client configuration is present in Flutter AOT code')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('platform', choices=('android', 'ios'))
    parser.add_argument('package', type=Path)
    parser.add_argument('--metadata', type=Path, default=Path('assets/build-info.json'))
    parser.add_argument('--supabase-config', type=Path, help='Require these public client settings in Flutter AOT code')
    args = parser.parse_args()
    try:
        verify(args.platform, args.package, args.metadata, args.supabase_config)
    except (ValueError, KeyError, OSError, zipfile.BadZipFile, plistlib.InvalidFileException) as error:
        raise SystemExit(f'Native release verification failed: {error}') from error
