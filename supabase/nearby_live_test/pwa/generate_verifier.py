"""v2 contract, derived from immutable v1 + reviewed upgrade; never replaces v1."""
from pathlib import Path
import hashlib
import re
import runpy
import sys

root = Path(__file__).resolve().parent
original_argv = sys.argv
sys.argv = ['generate_verifier.py', '--check']
base = runpy.run_path(str(root.parent / 'generate_verifier.py'))['sql']
sys.argv = original_argv
sources = [(root.parent / '01_install.sql').read_text(), (root / '01_upgrade.sql').read_text()]
functions = {}
for source in sources:
    for name, args, body in re.findall(r'CREATE (?:OR REPLACE )?FUNCTION ([\w.]+)\((.*?)\).*? AS \$\$(.*?)\$\$;', source, re.S):
        types = ','.join(part.strip().split(' ', 1)[1] for part in args.split(',')) if args.strip() else ''
        functions[f'{name}({types})'] = hashlib.md5(body.encode()).hexdigest()
assert len(functions) == 19
values = ',\n'.join(f"    ('{name}','{digest}')" for name, digest in functions.items())
sql = re.sub(r'(?<=FOR r IN SELECT \* FROM \(VALUES\n).*?(?=\n  \) AS expected)', lambda _: values, base, flags=re.S)
sql = sql.replace("relkind='r')<>6", "relkind='r')<>8").replace("live_test'::regnamespace)<>2", "live_test'::regnamespace)<>4").replace("left(proname,7)='swtest_')<>7", "left(proname,7)='swtest_')<>15")
sql = sql.replace("'alerts','deliveries']", "'alerts','deliveries','push_devices','push_outbox']")
sql = sql.replace("(left(r.signature,14)<>'public.swtest_' OR a.grantee NOT IN('anon'::regrole,'authenticated'::regrole))", "(CASE WHEN r.signature LIKE 'public.swtest_push_%' THEN a.grantee<>'service_role'::regrole WHEN left(r.signature,14)='public.swtest_' THEN a.grantee NOT IN('anon'::regrole,'authenticated'::regrole) ELSE true END)")
sql = sql.replace("allowed:=left(r.signature,14)='public.swtest_' AND role_name IN('anon','authenticated');", "allowed:=CASE WHEN r.signature LIKE 'public.swtest_push_%' THEN role_name='service_role' ELSE left(r.signature,14)='public.swtest_' AND role_name IN('anon','authenticated') END;")
sql = sql.replace("'LIVE_TEST_CONTRACT_VERIFIED'", "'LIVE_TEST_PWA_V2_CONTRACT_VERIFIED'")
sql = sql.replace('enabled_until,coalesce', 'push_enabled,enabled_until,coalesce')
sql = sql.replace('  FOR r IN SELECT * FROM (VALUES', '''  IF (SELECT count(*) FROM pg_attribute WHERE attrelid='safe_walk_nearby_live_test.push_devices'::regclass AND attnum>0 AND NOT attisdropped)<>12
     OR (SELECT count(*) FROM pg_attribute WHERE attrelid='safe_walk_nearby_live_test.push_outbox'::regclass AND attnum>0 AND NOT attisdropped)<>9
     OR (SELECT count(*) FROM pg_constraint WHERE conrelid='safe_walk_nearby_live_test.push_devices'::regclass AND convalidated)<>4
     OR (SELECT count(*) FROM pg_constraint WHERE conrelid='safe_walk_nearby_live_test.push_outbox'::regclass AND convalidated)<>6
     OR NOT EXISTS(SELECT 1 FROM pg_index i JOIN pg_class c ON c.oid=i.indexrelid JOIN pg_am am ON am.oid=c.relam
       WHERE i.indrelid='safe_walk_nearby_live_test.push_devices'::regclass AND i.indisvalid AND am.amname='gist') THEN
    RAISE EXCEPTION 'PWA table structure/index mismatch';
  END IF;
  FOR r IN SELECT * FROM (VALUES''')
# The unchanged formal verifier still checks the 13 owner-only nearby_* RPCs.
formal = (root.parent.parent / 'nearby_helper/06_verify_locked_backend.sql').read_text()
sql = '-- v2 ONLY. Read-only formal + isolated test contract. Do not run the v1 verifier after upgrade.\n' + formal + '\n' + sql
out = root / '02_verify.sql'
if '--check' in sys.argv:
    assert out.read_text() == sql, 'Regenerate v2 verifier'
    print('PWA v2 verifier is current')
else:
    out.write_text(sql, newline='\n')
