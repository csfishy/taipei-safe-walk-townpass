-- Manual, read-only metadata preflight. Creates or changes nothing.
-- Run on the explicitly authorized Supabase project before 01_create_tables.sql.
BEGIN TRANSACTION READ ONLY;
SET LOCAL search_path = pg_catalog;

DO $preflight$
DECLARE
  postgis_schema text;
  client_role text;
BEGIN
  IF to_regnamespace('safe_walk_nearby') IS NOT NULL THEN
    RAISE EXCEPTION 'safe_walk_nearby already exists; stop and review, do not recreate';
  END IF;
  SELECT n.nspname INTO postgis_schema
  FROM pg_extension e JOIN pg_namespace n ON n.oid = e.extnamespace
  WHERE e.extname = 'postgis';
  IF postgis_schema IS NULL OR
      to_regtype(format('%I.geography', postgis_schema)) IS NULL THEN
    RAISE EXCEPTION 'An existing PostGIS geography type is required; no extension will be installed or moved';
  END IF;
  IF to_regclass('auth.users') IS NULL OR NOT EXISTS (
    SELECT 1 FROM pg_attribute
    WHERE attrelid = to_regclass('auth.users') AND attname = 'id'
      AND atttypid = 'uuid'::regtype AND NOT attisdropped
  ) THEN
    RAISE EXCEPTION 'Expected existing auth.users(id uuid)';
  END IF;
  FOREACH client_role IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = client_role) THEN
      RAISE EXCEPTION 'Expected Supabase API role % is missing', client_role;
    END IF;
  END LOOP;
  IF NOT has_database_privilege(current_user, current_database(), 'CREATE') THEN
    RAISE EXCEPTION 'Current database role cannot create an isolated schema';
  END IF;
END
$preflight$;

SELECT current_database() AS database_name, current_user AS execution_role,
  e.extversion AS postgis_version, n.nspname AS postgis_schema,
  to_regnamespace('safe_walk_nearby') IS NULL AS new_schema_absent,
  to_regclass('auth.users') IS NOT NULL AS auth_users_present
FROM pg_extension e JOIN pg_namespace n ON n.oid = e.extnamespace
WHERE e.extname = 'postgis';

-- Metadata only: global defaults are additive and cannot be removed by a
-- schema-scoped REVOKE. New objects must always receive explicit REVOKEs.
SELECT d.defaclobjtype AS object_kind,
  CASE WHEN d.defaclnamespace = 0 THEN '(global)' ELSE n.nspname END AS scope,
  d.defaclacl AS owner_default_acl
FROM pg_default_acl d
LEFT JOIN pg_namespace n ON n.oid = d.defaclnamespace
WHERE d.defaclrole = (SELECT oid FROM pg_roles WHERE rolname = current_user)
ORDER BY object_kind, scope;
COMMIT;
