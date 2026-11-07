-- Only for a fresh, local, disposable CI database created from template0.
-- Never run this bootstrap against Supabase or an existing shared database.
\set ON_ERROR_STOP on
\if :{?ci_password}
\else
  \echo 'CI bootstrap requires the disposable ci_password variable'
  \quit 3
\endif

BEGIN;
DO $guard$
BEGIN
  IF current_database() <> 'safe_walk_ci' THEN
    RAISE EXCEPTION 'CI bootstrap requires the dedicated safe_walk_ci database';
  END IF;
END
$guard$;
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA extensions;

DO $role$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'safe_walk_demo_reset') THEN
    CREATE ROLE safe_walk_demo_reset LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'safe_walk_demo_reset'
      AND (rolsuper OR rolcreatedb OR rolcreaterole OR rolinherit OR rolbypassrls))
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_auth_members
      WHERE member = 'safe_walk_demo_reset'::regrole) THEN
    RAISE EXCEPTION 'CI reset role privileges are not isolated';
  END IF;
END
$role$;
SELECT format('ALTER ROLE safe_walk_demo_reset PASSWORD %L', :'ci_password') \gexec

CREATE SCHEMA IF NOT EXISTS safe_walk_demo AUTHORIZATION safe_walk_demo_reset;
CREATE SCHEMA IF NOT EXISTS safe_walk_demo_control;
CREATE TABLE IF NOT EXISTS safe_walk_demo_control.target (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  environment text NOT NULL CHECK (environment IN ('ci', 'demo')),
  project_id text NOT NULL,
  repository text NOT NULL
);
INSERT INTO safe_walk_demo_control.target (singleton, environment, project_id, repository)
VALUES (true, 'ci', 'local-ci', 'csfishy/taipei-safe-walk-townpass')
ON CONFLICT (singleton) DO NOTHING;
DO $marker$
BEGIN
  IF (SELECT count(*) FROM safe_walk_demo_control.target) <> 1 OR NOT EXISTS (
    SELECT 1 FROM safe_walk_demo_control.target
    WHERE singleton AND environment = 'ci' AND project_id = 'local-ci'
      AND repository = 'csfishy/taipei-safe-walk-townpass'
  ) THEN
    RAISE EXCEPTION 'CI database marker does not match this repository';
  END IF;
END
$marker$;
REVOKE ALL ON SCHEMA safe_walk_demo FROM PUBLIC;
REVOKE ALL ON SCHEMA safe_walk_demo_control FROM PUBLIC;
REVOKE ALL ON safe_walk_demo_control.target FROM PUBLIC, safe_walk_demo_reset;
GRANT USAGE ON SCHEMA safe_walk_demo_control, extensions TO safe_walk_demo_reset;
GRANT SELECT ON safe_walk_demo_control.target TO safe_walk_demo_reset;
COMMIT;
