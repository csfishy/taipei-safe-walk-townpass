-- Fixed diagnostics only: never include rows, coordinates, or credentials.
DO $verify$
DECLARE
  client_role text;
  relation_name text;
  relation_oid oid;
  owner_oid oid;
BEGIN
  IF current_user <> 'safe_walk_demo_reset' THEN
    RAISE EXCEPTION 'Demo verification requires the restricted reset role';
  END IF;
  SELECT oid INTO owner_oid FROM pg_catalog.pg_roles WHERE rolname = current_user;
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles
    WHERE oid = owner_oid AND (rolsuper OR rolcreaterole OR rolcreatedb OR rolbypassrls OR rolinherit)
  ) OR EXISTS (SELECT 1 FROM pg_catalog.pg_auth_members WHERE member = owner_oid) THEN
    RAISE EXCEPTION 'Demo reset role privileges are not isolated';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_namespace
    WHERE nspname = 'safe_walk_demo' AND nspowner = owner_oid
  ) THEN
    RAISE EXCEPTION 'Demo schema ownership is invalid';
  END IF;

  FOREACH relation_name IN ARRAY ARRAY['helpers', 'emergency_alerts', 'alert_recipients'] LOOP
    relation_oid := to_regclass('safe_walk_demo.' || relation_name);
    IF relation_oid IS NULL OR NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_class
      WHERE oid = relation_oid AND relkind = 'r' AND relowner = owner_oid
        AND relrowsecurity AND NOT relforcerowsecurity
    ) THEN
      RAISE EXCEPTION 'Demo table, ownership, or row security is invalid';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_policy WHERE polrelid = relation_oid) THEN
      RAISE EXCEPTION 'Demo tables must have no client policies';
    END IF;
    IF EXISTS (
      SELECT 1 FROM pg_catalog.pg_class c,
        LATERAL pg_catalog.aclexplode(coalesce(c.relacl, pg_catalog.acldefault('r', c.relowner))) a
      WHERE c.oid = relation_oid AND a.grantee = 0
    ) THEN
      RAISE EXCEPTION 'Demo tables must not grant privileges to PUBLIC';
    END IF;
    FOREACH client_role IN ARRAY ARRAY['anon', 'authenticated'] LOOP
      IF EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = client_role) THEN
        IF pg_catalog.has_table_privilege(client_role, relation_oid,
            'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') THEN
          RAISE EXCEPTION 'Demo tables must not grant privileges to client roles';
        END IF;
      END IF;
    END LOOP;
  END LOOP;

  IF EXISTS (
    WITH expected(table_name, column_name, type_oid, not_null) AS (VALUES
      ('helpers', 'helper_id', 'uuid'::regtype::oid, true),
      ('helpers', 'enabled', 'boolean'::regtype::oid, true),
      ('helpers', 'location', 'extensions.geography'::regtype::oid, false),
      ('helpers', 'updated_at', 'timestamptz'::regtype::oid, true),
      ('emergency_alerts', 'id', 'uuid'::regtype::oid, true),
      ('emergency_alerts', 'sender_id', 'uuid'::regtype::oid, true),
      ('emergency_alerts', 'location', 'extensions.geography'::regtype::oid, true),
      ('emergency_alerts', 'radius_m', 'integer'::regtype::oid, true),
      ('emergency_alerts', 'created_at', 'timestamptz'::regtype::oid, true),
      ('alert_recipients', 'alert_id', 'uuid'::regtype::oid, true),
      ('alert_recipients', 'recipient_id', 'uuid'::regtype::oid, true),
      ('alert_recipients', 'seen', 'boolean'::regtype::oid, true)
    ), actual AS (
      SELECT c.relname::text, a.attname::text, a.atttypid, a.attnotnull
      FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
      JOIN pg_catalog.pg_attribute a ON a.attrelid = c.oid
      WHERE n.nspname = 'safe_walk_demo'
        AND c.relname IN ('helpers', 'emergency_alerts', 'alert_recipients')
        AND a.attnum > 0 AND NOT a.attisdropped
    )
    (SELECT * FROM expected EXCEPT SELECT * FROM actual)
    UNION ALL
    (SELECT * FROM actual EXCEPT SELECT * FROM expected)
  ) THEN
    RAISE EXCEPTION 'Demo table columns do not match the migration contract';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid IN ('safe_walk_demo.helpers'::regclass, 'safe_walk_demo.emergency_alerts'::regclass)
      AND a.attname = 'location' AND NOT a.attisdropped
      AND (extensions.postgis_typmod_type(a.atttypmod) <> 'Point'
        OR extensions.postgis_typmod_srid(a.atttypmod) <> 4326
        OR extensions.postgis_typmod_dims(a.atttypmod) <> 2)
  ) THEN
    RAISE EXCEPTION 'Demo geography columns must use two dimensional WGS84 points';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint
    WHERE conrelid = 'safe_walk_demo.helpers'::regclass AND contype = 'p'
      AND conkey = ARRAY[1]::smallint[] AND convalidated
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint
    WHERE conrelid = 'safe_walk_demo.emergency_alerts'::regclass AND contype = 'p'
      AND conkey = ARRAY[1]::smallint[] AND convalidated
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint
    WHERE conrelid = 'safe_walk_demo.alert_recipients'::regclass AND contype = 'p'
      AND conkey = ARRAY[1,2]::smallint[] AND convalidated
  ) THEN
    RAISE EXCEPTION 'Demo primary keys are missing or invalid';
  END IF;
  IF (SELECT count(*) FROM pg_catalog.pg_constraint
      WHERE conrelid = 'safe_walk_demo.alert_recipients'::regclass AND contype = 'f'
        AND confdeltype = 'c' AND convalidated
        AND ((conkey = ARRAY[1]::smallint[] AND confkey = ARRAY[1]::smallint[]
            AND confrelid = 'safe_walk_demo.emergency_alerts'::regclass)
          OR (conkey = ARRAY[2]::smallint[] AND confkey = ARRAY[1]::smallint[]
            AND confrelid = 'safe_walk_demo.helpers'::regclass))) <> 2 THEN
    RAISE EXCEPTION 'Demo recipient foreign keys are missing or invalid';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint
    WHERE conrelid = 'safe_walk_demo.emergency_alerts'::regclass
      AND conname = 'emergency_alerts_radius_m_check' AND contype = 'c'
      AND convalidated AND pg_catalog.pg_get_constraintdef(oid) =
        'CHECK (((radius_m >= 50) AND (radius_m <= 3000)))'
  ) THEN
    RAISE EXCEPTION 'Demo alert radius constraint is missing or invalid';
  END IF;

  IF (SELECT count(*) FROM safe_walk_demo.helpers) <> 2 OR NOT EXISTS (
    SELECT 1 FROM safe_walk_demo.helpers
    WHERE helper_id = '11111111-1111-4111-8111-111111111111' AND enabled
      AND updated_at = '2000-01-01T00:00:00Z'::timestamptz
      AND extensions.st_x(location::extensions.geometry) = 121.5654
      AND extensions.st_y(location::extensions.geometry) = 25.033
  ) OR NOT EXISTS (
    SELECT 1 FROM safe_walk_demo.helpers
    WHERE helper_id = '22222222-2222-4222-8222-222222222222' AND NOT enabled
      AND location IS NULL AND updated_at = '2000-01-01T00:00:00Z'::timestamptz
  ) THEN
    RAISE EXCEPTION 'Demo helper seed does not match the expected fixture';
  END IF;
  IF (SELECT count(*) FROM safe_walk_demo.emergency_alerts) <> 1 OR NOT EXISTS (
    SELECT 1 FROM safe_walk_demo.emergency_alerts
    WHERE id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
      AND sender_id = '33333333-3333-4333-8333-333333333333'
      AND radius_m = 500 AND created_at = '2000-01-01T00:00:00Z'::timestamptz
      AND extensions.st_x(location::extensions.geometry) = 121.5654
      AND extensions.st_y(location::extensions.geometry) = 25.033
  ) OR (SELECT count(*) FROM safe_walk_demo.alert_recipients) <> 1 OR NOT EXISTS (
    SELECT 1 FROM safe_walk_demo.alert_recipients
    WHERE alert_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
      AND recipient_id = '11111111-1111-4111-8111-111111111111' AND NOT seen
  ) THEN
    RAISE EXCEPTION 'Demo alert seed does not match the expected fixture';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_namespace n,
      LATERAL pg_catalog.aclexplode(coalesce(n.nspacl, pg_catalog.acldefault('n', n.nspowner))) a
    WHERE n.nspname = 'safe_walk_demo' AND a.grantee = 0
  ) OR EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'safe_walk_demo'
  ) THEN
    RAISE EXCEPTION 'Demo schema must not expose client access or RPC functions';
  END IF;
  FOREACH client_role IN ARRAY ARRAY['anon', 'authenticated'] LOOP
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = client_role) THEN
      IF pg_catalog.has_schema_privilege(client_role, 'safe_walk_demo', 'USAGE,CREATE') THEN
        RAISE EXCEPTION 'Demo schema must not grant privileges to client roles';
      END IF;
    END IF;
  END LOOP;
END
$verify$;
