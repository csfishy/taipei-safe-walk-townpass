-- MANUAL, READ ONLY. Run before reviewing/applying 01_initialize.sql.
BEGIN TRANSACTION READ ONLY;
SELECT current_database() AS database_name, current_user AS executing_role,
       current_setting('server_version') AS server_version,
       current_setting('pgrst.db_schemas', true) AS visible_postgrest_schema_setting;
SELECT n.nspname, pg_get_userbyid(n.nspowner) AS owner, n.nspacl,
       obj_description(n.oid, 'pg_namespace') AS schema_comment
FROM pg_namespace n WHERE n.nspname = 'crime_reference';
SELECT c.relname, c.relkind, c.relrowsecurity, c.relforcerowsecurity,
       pg_get_userbyid(c.relowner) AS owner, c.relacl
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='crime_reference' ORDER BY c.relname;
SELECT p.tablename, p.policyname, p.roles, p.cmd, p.qual, p.with_check
FROM pg_policies p WHERE p.schemaname='crime_reference';
SELECT r.rolname, has_schema_privilege(r.oid,n.oid,'USAGE') AS has_usage,
       has_schema_privilege(r.oid,n.oid,'CREATE') AS has_create
FROM pg_roles r CROSS JOIN pg_namespace n
WHERE n.nspname='crime_reference' AND r.rolname IN ('anon','authenticated','service_role');
SELECT c.relname, t.tgname, pg_get_triggerdef(t.oid) AS definition
FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='crime_reference' AND NOT t.tgisinternal;
-- Counts only; never reads unrelated application/user rows.
DO $preflight$
DECLARE t text; row_count bigint;
BEGIN
  FOREACH t IN ARRAY ARRAY['snapshots','sources','records'] LOOP
    IF to_regclass(format('crime_reference.%I',t)) IS NOT NULL THEN
      EXECUTE format('SELECT count(*) FROM crime_reference.%I',t) INTO row_count;
      RAISE NOTICE 'crime_reference.% rows=%', t, row_count;
    END IF;
  END LOOP;
END;
$preflight$;
COMMIT;
