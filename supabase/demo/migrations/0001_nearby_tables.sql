-- Isolated CI/Demo storage only. This is deliberately NOT the legacy
-- public/anon security-definer RPC deployment in ../nearby_emergency.sql.
-- The restricted connection role must already own safe_walk_demo.
CREATE TABLE IF NOT EXISTS safe_walk_demo.helpers (
  helper_id uuid CONSTRAINT helpers_pkey PRIMARY KEY,
  enabled boolean NOT NULL DEFAULT false,
  location extensions.geography(Point, 4326),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS safe_walk_demo.emergency_alerts (
  id uuid DEFAULT gen_random_uuid() CONSTRAINT emergency_alerts_pkey PRIMARY KEY,
  sender_id uuid NOT NULL,
  location extensions.geography(Point, 4326) NOT NULL,
  radius_m integer NOT NULL CONSTRAINT emergency_alerts_radius_m_check
    CHECK (radius_m BETWEEN 50 AND 3000),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS safe_walk_demo.alert_recipients (
  alert_id uuid NOT NULL CONSTRAINT alert_recipients_alert_id_fkey
    REFERENCES safe_walk_demo.emergency_alerts(id) ON DELETE CASCADE,
  recipient_id uuid NOT NULL CONSTRAINT alert_recipients_recipient_id_fkey
    REFERENCES safe_walk_demo.helpers(helper_id) ON DELETE CASCADE,
  seen boolean NOT NULL DEFAULT false,
  CONSTRAINT alert_recipients_pkey PRIMARY KEY (alert_id, recipient_id)
);

ALTER TABLE safe_walk_demo.helpers ENABLE ROW LEVEL SECURITY;
ALTER TABLE safe_walk_demo.emergency_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE safe_walk_demo.alert_recipients ENABLE ROW LEVEL SECURITY;

-- No policies, public RPCs, grants to a mobile client, or location notifications.
-- The schema/table owner writes synthetic seeds using PostgreSQL's normal owner
-- bypass; the reset role has NO BYPASSRLS privilege and owns no other schema.
REVOKE ALL ON SCHEMA safe_walk_demo FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA safe_walk_demo FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA safe_walk_demo FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA safe_walk_demo FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA safe_walk_demo REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA safe_walk_demo REVOKE ALL ON SEQUENCES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA safe_walk_demo REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

DO $permissions$
DECLARE
  client_role text;
BEGIN
  FOREACH client_role IN ARRAY ARRAY['anon', 'authenticated'] LOOP
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = client_role) THEN
      EXECUTE format('REVOKE ALL ON SCHEMA safe_walk_demo FROM %I', client_role);
      EXECUTE format('REVOKE ALL ON ALL TABLES IN SCHEMA safe_walk_demo FROM %I', client_role);
      EXECUTE format('REVOKE ALL ON ALL SEQUENCES IN SCHEMA safe_walk_demo FROM %I', client_role);
      EXECUTE format('REVOKE ALL ON ALL FUNCTIONS IN SCHEMA safe_walk_demo FROM %I', client_role);
    END IF;
  END LOOP;
END
$permissions$;
