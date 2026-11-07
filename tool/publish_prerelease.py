"""Publish complete preview artifacts without replacing a published release."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
from urllib.parse import quote


ASSETS = (
    'taipei-safe-walk-townpass-android-prerelease.apk',
    'taipei-safe-walk-townpass-ios-unsigned.ipa',
    'taipei-safe-walk-townpass-web.zip',
    'build-info.json',
    'SHA256SUMS.txt',
)


def gh(*args, missing_ok=False):
    result = subprocess.run(['gh', *args], capture_output=True, text=True)
    if result.returncode:
        if missing_ok and '(HTTP 404)' in result.stderr:
            return None
        raise ValueError(f'GitHub command failed: {result.stderr.strip()}')
    return result.stdout


def api(path, missing_ok=True):
    response = gh('api', path, missing_ok=missing_ok)
    return None if response is None else json.loads(response)


def publish(tag, artifacts=Path('artifacts'), notes=Path('docs/PRERELEASE-NOTES.md')):
    repo = os.environ.get('GH_REPO', '')
    commit = os.environ.get('GITHUB_SHA', '')
    if not re.fullmatch(r'[\w.-]+/[\w.-]+', repo) or not re.fullmatch(r'[0-9a-f]{40}', commit):
        raise ValueError('GH_REPO and GITHUB_SHA must identify the workflow source')
    paths = [artifacts / name for name in ASSETS]
    if any(not path.is_file() or path.stat().st_size == 0 for path in paths):
        raise ValueError('Expected all five nonempty release artifacts')
    expected = json.loads((artifacts / 'build-info.json').read_text(encoding='utf-8'))
    if expected.get('commit') != commit or expected.get('preview') is not True:
        raise ValueError('Artifact metadata does not identify this preview source')
    if tag != f'v{expected.get("version")}' or not re.fullmatch(r'v[0-9A-Za-z.+-]+', tag):
        raise ValueError('Release tag must match the artifact version')

    tag_path = quote(tag, safe='')
    # A missing commit returns HTTP 422; a missing exact ref returns HTTP 404.
    # Probe the ref first so 422 and other API failures remain fatal.
    reference = api(f'repos/{repo}/git/ref/tags/{tag_path}')
    source = None
    if reference is not None:
        commit_ref = quote(f'refs/tags/{tag}', safe='')
        source = api(f'repos/{repo}/commits/{commit_ref}', missing_ok=False)
    if source is not None and source.get('sha') != commit:
        raise ValueError('Existing tag points to another source commit; refusing to move it')
    release = api(f'repos/{repo}/releases/tags/{tag_path}')
    if release is None:
        # The tag endpoint only finds published releases. The authenticated list
        # also includes drafts, including those whose tags do not exist yet.
        pages = json.loads(gh('api', f'repos/{repo}/releases?per_page=100', '--paginate', '--slurp'))
        matches = [item for page in pages for item in page if item.get('tag_name') == tag]
        if len(matches) > 1:
            raise ValueError('Multiple releases use this tag; refusing an ambiguous retry')
        release = matches[0] if matches else None
    if release is not None:
        if release.get('tag_name') != tag or release.get('prerelease') is not True:
            raise ValueError('Existing release is not the expected prerelease')
        if source is None and (not release.get('draft') or release.get('target_commitish') != commit):
            raise ValueError('Existing release source cannot be verified')
        if not release.get('draft'):
            uploaded = {
                asset['name'] for asset in release.get('assets', [])
                if asset.get('state') == 'uploaded' and asset.get('size', 0) > 0
            }
            if not set(ASSETS).issubset(uploaded):
                raise ValueError('Published prerelease is incomplete; refusing to replace its assets')
            with tempfile.TemporaryDirectory() as folder:
                gh('release', 'download', tag, '--repo', repo, '--pattern', 'build-info.json', '--dir', folder)
                actual = json.loads(Path(folder, 'build-info.json').read_text(encoding='utf-8'))
            if actual != expected:
                raise ValueError('Published prerelease metadata does not match this build')
            print(f'Prerelease already complete: https://github.com/{repo}/releases/tag/{tag}')
            return

    if release is None:
        body = notes.read_text(encoding='utf-8').rstrip()
        body += f'\n\nSource commit: [{commit}](https://github.com/{repo}/commit/{commit})\n'
        run_id = os.environ.get('GITHUB_RUN_ID', '')
        if run_id.isdigit():
            body += f'Workflow run: https://github.com/{repo}/actions/runs/{run_id}\n'
        with tempfile.TemporaryDirectory() as folder:
            notes_file = Path(folder, 'notes.md')
            notes_file.write_text(body, encoding='utf-8')
            gh('release', 'create', tag, '--repo', repo, '--draft', '--prerelease',
               '--target', commit, '--title', f'Town Pass Preview {tag}',
               '--notes-file', str(notes_file), '--latest=false')

    # A failed upload leaves a draft, so retrying can safely replace the full set.
    gh('release', 'upload', tag, '--repo', repo, *(str(path) for path in paths), '--clobber')
    gh('release', 'edit', tag, '--repo', repo, '--draft=false', '--prerelease=true', '--latest=false')
    print(f'Published prerelease: https://github.com/{repo}/releases/tag/{tag}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tag', required=True)
    args = parser.parse_args()
    try:
        publish(args.tag)
    except (ValueError, KeyError, OSError) as error:
        raise SystemExit(f'Prerelease publication failed: {error}') from error
