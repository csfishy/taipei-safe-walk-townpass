"""Generate the read-only contract from reviewed installation function bodies."""
from pathlib import Path
import hashlib
import re
import sys

root = Path(__file__).resolve().parent
source = (root / '01_install.sql').read_text(encoding='utf-8')
functions = re.findall(r'CREATE FUNCTION ([\w.]+)\((.*?)\).*? AS \$\$(.*?)\$\$;', source, re.S)
assert len(functions) == 9
values = []
for name, args, body in functions:
    types = ','.join(part.strip().split(' ', 1)[1] for part in args.split(',')) if args.strip() else ''
    digest = hashlib.md5(body.encode()).hexdigest()
    values.append(f"('{name}({types})','{digest}')")
sql = """-- GENERATED. Read-only; no locations, emails, salts or tokens are read.
BEGIN TRANSACTION READ ONLY;
DO $verify$
DECLARE r record; f record; role_name text; t text; allowed boolean;
BEGIN
  IF (SELECT extversion FROM pg_extension WHERE extname='postgis')<>'3.3.7' THEN
    RAISE EXCEPTION 'Expected PostGIS 3.3.7';
  END IF;
  IF (SELECT count(*) FROM pg_class WHERE relnamespace='safe_walk_nearby_live_test'::regnamespace AND relkind='r')<>6
     OR (SELECT count(*) FROM pg_proc WHERE pronamespace='safe_walk_nearby_live_test'::regnamespace)<>2
     OR (SELECT count(*) FROM pg_proc WHERE pronamespace='public'::regnamespace AND left(proname,7)='swtest_')<>7 THEN
    RAISE EXCEPTION 'Unexpected Live-test objects';
  END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid IN(SELECT oid FROM pg_class WHERE relnamespace='safe_walk_nearby_live_test'::regnamespace)) THEN
    RAISE EXCEPTION 'Unexpected policies';
  END IF;
  FOREACH t IN ARRAY ARRAY['control','accounts','sessions','locations','alerts','deliveries'] LOOP
    IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid=('safe_walk_nearby_live_test.'||t)::regclass
                  AND relrowsecurity AND relowner='postgres'::regrole) THEN
      RAISE EXCEPTION 'Table security mismatch';
    END IF;
    IF EXISTS(SELECT 1 FROM pg_class c CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a
              WHERE c.oid=('safe_walk_nearby_live_test.'||t)::regclass AND a.grantee<>c.relowner) THEN
      RAISE EXCEPTION 'Unexpected table grant';
    END IF;
    FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
      IF has_schema_privilege(role_name,'safe_walk_nearby_live_test','USAGE')
         OR has_table_privilege(role_name,'safe_walk_nearby_live_test.'||t,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') THEN
        RAISE EXCEPTION 'Direct test-data privilege mismatch';
      END IF;
    END LOOP;
  END LOOP;
  FOR r IN SELECT * FROM (VALUES
__VALUES__
  ) AS expected(signature,digest) LOOP
    SELECT * INTO f FROM pg_proc WHERE oid=to_regprocedure(r.signature);
    IF NOT FOUND OR NOT f.prosecdef OR f.proowner<>'postgres'::regrole
       OR f.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
       OR md5(replace(f.prosrc,E'\\r\\n',E'\\n'))<>r.digest THEN
      RAISE EXCEPTION 'Function contract mismatch: %',r.signature;
    END IF;
    IF EXISTS(SELECT 1 FROM aclexplode(coalesce(f.proacl,acldefault('f',f.proowner))) WHERE grantee=0 AND privilege_type='EXECUTE') THEN
      RAISE EXCEPTION 'PUBLIC function grant';
    END IF;
    IF EXISTS(SELECT 1 FROM aclexplode(coalesce(f.proacl,acldefault('f',f.proowner))) a
              WHERE a.grantee<>f.proowner AND
                (left(r.signature,14)<>'public.swtest_' OR a.grantee NOT IN('anon'::regrole,'authenticated'::regrole))) THEN
      RAISE EXCEPTION 'Unexpected function grantee';
    END IF;
    FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
      allowed:=left(r.signature,14)='public.swtest_' AND role_name IN('anon','authenticated');
      IF has_function_privilege(role_name,f.oid,'EXECUTE') IS DISTINCT FROM allowed THEN
        RAISE EXCEPTION 'Function ACL mismatch';
      END IF;
    END LOOP;
  END LOOP;
END $verify$;
SELECT 'LIVE_TEST_CONTRACT_VERIFIED' AS status,
       enabled_until,coalesce(enabled_until>now(),false) AS test_enabled
FROM safe_walk_nearby_live_test.control WHERE id;
ROLLBACK;
""".replace('__VALUES__', ',\n'.join('    '+v for v in values))
out = root / '03_verify.sql'
if '--check' in sys.argv:
    assert out.read_text(encoding='utf-8') == sql, 'Regenerate verifier'
    print('Live-test verifier is current')
else:
    out.write_text(sql, encoding='utf-8', newline='\n')
