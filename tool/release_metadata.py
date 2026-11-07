"""Generate the same traceable build metadata for each platform."""
import json
import os
from pathlib import Path
import re
import subprocess

text = Path('pubspec.yaml').read_text(encoding='utf-8')
match = re.search(r'^version:\s*(\d+\.\d+\.\d+(?:-pre\.\d+)?)(?:\+(\d+))?\s*$', text, re.M)
if not match:
    raise SystemExit('Expected version X.Y.Z[-pre.N][+BUILD] in pubspec.yaml')
version = match[1]
ref = os.environ.get('GITHUB_REF', '')
if ref.startswith('refs/tags/') and ref != f'refs/tags/v{version}':
    raise SystemExit('Tag must match pubspec.yaml version without +BUILD')
commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
if os.environ.get('GITHUB_SHA', commit) != commit:
    raise SystemExit('Checkout does not match the workflow source commit')
metadata = {
    'version': version,
    'buildNumber': os.environ.get('GITHUB_RUN_NUMBER', match[2] or '1'),
    'commit': commit,
    'flutterVersion': json.loads(Path('.fvmrc').read_text())['flutter'],
    'preview': True,
    'websiteBasePath': '/taipei-safe-walk-townpass/',
}
Path('assets/build-info.json').write_text(json.dumps(metadata, indent=2) + '\n', encoding='utf-8')
if output := os.environ.get('GITHUB_OUTPUT'):
    with open(output, 'a', encoding='utf-8') as file:
        file.write(f'version={version}\nbuild_name={version.split("-")[0]}\n')
print(json.dumps(metadata))
