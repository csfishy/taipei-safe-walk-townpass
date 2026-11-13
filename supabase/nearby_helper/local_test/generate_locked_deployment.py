"""Derive an owner-only deployment from the exact 3.3.7-tested SQL.

No database connection. The original migration/verifier and their evidence stay
unchanged. Only the final API ACL policy differs; all 14 function bodies match.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = 'migrations/20261113000000_upgrade_nearby_backend.sql'
TARGET = ROOT / 'migrations/20261113010000_upgrade_nearby_backend_locked.sql'
VERIFY = ROOT / '06_verify_locked_backend.sql'


def build():
    report = json.loads((ROOT / 'local_test/evidence/postgis-3.3.7.json').read_text(encoding='utf-8'))
    assert report['status'] == 'PASS' and report['passed_groups'] == 18
    sources = {}
    for name in (BASE, '04_verify_backend.sql'):
        data = (ROOT / name).read_bytes()
        assert hashlib.sha256(data).hexdigest() == report['sha256'][name], 'Validated source changed'
        sources[name] = data.decode('utf-8')
    migration = sources[BASE]
    start = migration.index("  if exists (select 1 from pg_catalog.pg_roles where rolname = 'authenticated') then")
    end = migration.index('  end if;', start) + len('  end if;')
    assert migration[start:end].count('grant execute on function') == 13
    migration = migration[:start] + '  -- Deliberately no API EXECUTE grants: deploy without activating notifications.' + migration[end:]

    def owner_only(sql):
        before = "AND (NOT expected.client_callable OR a.grantee <> 'authenticated'::regrole\n             OR a.privilege_type <> 'EXECUTE' OR a.is_grantable)"
        assert sql.count(before) == 1
        assert sql.count("(expected.client_callable AND api_role='authenticated')") == 1
        sql = sql.replace(before, 'AND true').replace("(expected.client_callable AND api_role='authenticated')", 'false')
        # Dashboard on Windows transports CRLF; SQL function prosrc retains it.
        # Normalize only line-ending pairs, never SQL tokens or other whitespace.
        assert sql.count('md5(actual.prosrc)') == 1
        return sql.replace('md5(actual.prosrc)', "md5(replace(actual.prosrc, E'\\r\\n', E'\\n'))")

    migration = owner_only(migration)
    verifier = owner_only(sources['04_verify_backend.sql'])
    header = '-- OWNER-ONLY DEPLOYMENT. No API EXECUTE grants; notifications remain disabled.\n'
    migration = header + migration
    verifier = header + verifier.replace('not Live/device verification', 'owner-only; notifications disabled; not Live/device verification')
    function_bodies = lambda s: re.findall(r'create or replace function .*?as \$\$(.*?)\$\$;', s, re.S)
    assert len(function_bodies(migration)) == 14
    assert function_bodies(migration) == function_bodies(sources[BASE])
    assert not re.search(r'^\s*grant execute', migration, re.M | re.I)
    return {TARGET: migration, VERIFY: verifier}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    for file, text in build().items():
        if args.check:
            assert file.read_text(encoding='utf-8') == text, 'Stale locked SQL'
        else:
            file.write_text(text, encoding='utf-8', newline='\n')
    print('Owner-only deployment SQL is current; all 14 function bodies unchanged')
