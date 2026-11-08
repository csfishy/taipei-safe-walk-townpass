-- MANUAL ONLY: authorized empty-table provisioning from design commit 92565c9.
-- No RPC, client grant, position upload, notification, seed, TTL job or reset.
-- Existing schemas, legacy public objects and the PostGIS extension are untouched.
BEGIN;
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
END
$preflight$;

-- Deliberately no IF NOT EXISTS: an existing schema is never silently adopted.
CREATE SCHEMA safe_walk_nearby;
REVOKE ALL PRIVILEGES ON SCHEMA safe_walk_nearby
  FROM PUBLIC, anon, authenticated, service_role;

CREATE TABLE safe_walk_nearby.helper_profiles (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  consent_version text NOT NULL,
  consented_at timestamptz NOT NULL,
  revoked_at timestamptz
);

-- The design uses extensions.geography. Resolve the installed PostGIS namespace
-- instead: the authorized project's existing extension is in public. This keeps
-- geography(Point,4326) semantics without moving or changing the extension.
DO $postgis_tables$
DECLARE
  postgis_schema text;
BEGIN
  SELECT n.nspname INTO STRICT postgis_schema
  FROM pg_extension e JOIN pg_namespace n ON n.oid = e.extnamespace
  WHERE e.extname = 'postgis';

  EXECUTE format($ddl$
    CREATE TABLE safe_walk_nearby.helper_locations (
      user_id uuid PRIMARY KEY
        REFERENCES safe_walk_nearby.helper_profiles(user_id) ON DELETE CASCADE,
      geog %I.geography(Point, 4326) NOT NULL,
      accuracy_m real NOT NULL CHECK (accuracy_m >= 0),
      reported_at timestamptz NOT NULL,
      expires_at timestamptz NOT NULL
    )
  $ddl$, postgis_schema);

  EXECUTE format($ddl$
    CREATE TABLE safe_walk_nearby.alerts (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      sender_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
      client_request_id uuid NOT NULL,
      geog %I.geography(Point, 4326) NOT NULL,
      radius_m integer NOT NULL DEFAULT 500 CHECK (radius_m = 500),
      created_at timestamptz NOT NULL DEFAULT now(),
      expires_at timestamptz NOT NULL,
      UNIQUE (sender_id, client_request_id)
    )
  $ddl$, postgis_schema);
END
$postgis_tables$;

CREATE INDEX helper_locations_geog_gist
  ON safe_walk_nearby.helper_locations USING gist (geog);

CREATE TABLE safe_walk_nearby.alert_deliveries (
  alert_id uuid NOT NULL REFERENCES safe_walk_nearby.alerts(id) ON DELETE CASCADE,
  recipient_id uuid NOT NULL
    REFERENCES safe_walk_nearby.helper_profiles(user_id) ON DELETE CASCADE,
  delivered_at timestamptz NOT NULL DEFAULT now(),
  seen_at timestamptz,
  PRIMARY KEY (alert_id, recipient_id)
);

ALTER TABLE safe_walk_nearby.helper_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE safe_walk_nearby.helper_locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE safe_walk_nearby.alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE safe_walk_nearby.alert_deliveries ENABLE ROW LEVEL SECURITY;

REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA safe_walk_nearby
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA safe_walk_nearby
  FROM PUBLIC, anon, authenticated, service_role;

-- Applies only to this creating role and this schema. PostgreSQL global default
-- grants remain additive; these defaults cannot replace per-object REVOKEs.
ALTER DEFAULT PRIVILEGES IN SCHEMA safe_walk_nearby
  REVOKE ALL ON TABLES FROM PUBLIC, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA safe_walk_nearby
  REVOKE ALL ON SEQUENCES FROM PUBLIC, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA safe_walk_nearby
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated, service_role;

-- Fail this entire transaction if inherited privileges or unexpected policies
-- would expose the newly provisioned tables. This reads metadata only.
DO $locked_down$
DECLARE
  api_role text;
  relation record;
BEGIN
  IF (SELECT count(*) FROM pg_class
      WHERE relnamespace = 'safe_walk_nearby'::regnamespace AND relkind = 'r') <> 4
      OR EXISTS (SELECT 1 FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
                 WHERE c.relnamespace = 'safe_walk_nearby'::regnamespace)
      OR EXISTS (SELECT 1 FROM pg_proc
                 WHERE pronamespace = 'safe_walk_nearby'::regnamespace) THEN
    RAISE EXCEPTION 'Expected only four new tables, zero policies and zero functions';
  END IF;
  FOREACH api_role IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
    IF has_schema_privilege(api_role, 'safe_walk_nearby', 'USAGE') OR
        has_schema_privilege(api_role, 'safe_walk_nearby', 'CREATE') THEN
      RAISE EXCEPTION 'API role % retains effective schema access', api_role;
    END IF;
    FOR relation IN SELECT oid, relname, relrowsecurity FROM pg_class
      WHERE relnamespace = 'safe_walk_nearby'::regnamespace AND relkind = 'r'
    LOOP
      IF NOT relation.relrowsecurity OR EXISTS (
        SELECT 1 FROM unnest(ARRAY[
          'SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'
        ]) AS privilege_name
        WHERE has_table_privilege(api_role, relation.oid, privilege_name)
      ) THEN
        RAISE EXCEPTION 'RLS or effective table ACL failed for % / %',
          api_role, relation.relname;
      END IF;
    END LOOP;
  END LOOP;
END
$locked_down$;
COMMIT;
