-- GENERATED. Read-only; no locations, emails, salts or tokens are read.
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
    ('safe_walk_nearby_live_test.require_enabled()','25c562f5321b6d27626be2abe2debdbf'),
    ('safe_walk_nearby_live_test.session_user(text)','77745397e67ea724b204c8d203186077'),
    ('public.swtest_login(text)','15cc0a58610c8cd344ef83a9ea5983a7'),
    ('public.swtest_logout(text)','aac5766b127f26b9646d47a08aaec37d'),
    ('public.swtest_opt_in(text,text)','a61411f2b38469cff099d03235f2f416'),
    ('public.swtest_opt_out(text)','eedc4fe4a62a94e758b4fcc30c363cfe'),
    ('public.swtest_report_location(text,double precision,double precision)','682e5de8b88b4de47315a5d97341e2eb'),
    ('public.swtest_send(text,double precision,double precision,uuid)','83e86fde358aadbad2717ff65ccc06ac'),
    ('public.swtest_fetch(text)','903a55067919d14a3e20f75bd0f65478')
  ) AS expected(signature,digest) LOOP
    SELECT * INTO f FROM pg_proc WHERE oid=to_regprocedure(r.signature);
    IF NOT FOUND OR NOT f.prosecdef OR f.proowner<>'postgres'::regrole
       OR f.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
       OR md5(replace(f.prosrc,E'\r\n',E'\n'))<>r.digest THEN
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
