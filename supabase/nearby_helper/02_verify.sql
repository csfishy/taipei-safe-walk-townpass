-- Manual, read-only verification after the optional-accuracy delta migration.
-- Spec: nearby-helper-backend commit 2661d02; catalogs and four table counts only.
-- No coordinates, users, alerts, existing business rows or secret values read.
BEGIN TRANSACTION READ ONLY;
SET LOCAL search_path = pg_catalog;

DO $verify$
DECLARE
  target_schema oid := to_regnamespace('safe_walk_nearby');
  postgis_schema text;
  geography_type oid;
  expected record;
  actual record;
  api_role text;
  relation record;
  normalized_check text;
BEGIN
  IF target_schema IS NULL THEN
    RAISE EXCEPTION 'safe_walk_nearby does not exist';
  END IF;
  SELECT n.nspname INTO STRICT postgis_schema
  FROM pg_extension e JOIN pg_namespace n ON n.oid = e.extnamespace
  WHERE e.extname = 'postgis';
  geography_type := to_regtype(format('%I.geography', postgis_schema));

  IF (SELECT count(*) FROM pg_class
      WHERE relnamespace = target_schema AND relkind = 'r') <> 4
      OR EXISTS (SELECT 1 FROM pg_class WHERE relnamespace = target_schema
                 AND relkind NOT IN ('r', 'i'))
      OR EXISTS (SELECT 1 FROM pg_proc WHERE pronamespace = target_schema)
      OR EXISTS (SELECT 1 FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid
                 WHERE c.relnamespace = target_schema)
      OR EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
                 WHERE c.relnamespace = target_schema AND NOT t.tgisinternal) THEN
    RAISE EXCEPTION 'Expected four ordinary tables, indexes, zero functions/policies/user triggers';
  END IF;

  IF (SELECT count(*) FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid
      WHERE c.relnamespace = target_schema AND c.relkind = 'r'
        AND a.attnum > 0 AND NOT a.attisdropped) <> 20 THEN
    RAISE EXCEPTION 'Expected exactly the 20 design columns';
  END IF;
  FOR expected IN SELECT * FROM (VALUES
    ('helper_profiles', 'user_id', 'uuid', true, NULL::text),
    ('helper_profiles', 'consent_version', 'text', true, NULL),
    ('helper_profiles', 'consented_at', 'timestamptz', true, NULL),
    ('helper_profiles', 'revoked_at', 'timestamptz', false, NULL),
    ('helper_locations', 'user_id', 'uuid', true, NULL),
    ('helper_locations', 'geog', 'geography', true, NULL),
    ('helper_locations', 'accuracy_m', 'real', false, NULL),
    ('helper_locations', 'reported_at', 'timestamptz', true, NULL),
    ('helper_locations', 'expires_at', 'timestamptz', true, NULL),
    ('alerts', 'id', 'uuid', true, 'gen_random_uuid()'),
    ('alerts', 'sender_id', 'uuid', true, NULL),
    ('alerts', 'client_request_id', 'uuid', true, NULL),
    ('alerts', 'geog', 'geography', true, NULL),
    ('alerts', 'radius_m', 'integer', true, '500'),
    ('alerts', 'created_at', 'timestamptz', true, 'now()'),
    ('alerts', 'expires_at', 'timestamptz', true, NULL),
    ('alert_deliveries', 'alert_id', 'uuid', true, NULL),
    ('alert_deliveries', 'recipient_id', 'uuid', true, NULL),
    ('alert_deliveries', 'delivered_at', 'timestamptz', true, 'now()'),
    ('alert_deliveries', 'seen_at', 'timestamptz', false, NULL)
  ) AS columns(table_name, column_name, type_name, required, default_expression)
  LOOP
    SELECT a.atttypid, a.atttypmod, a.attnotnull,
      pg_get_expr(d.adbin, d.adrelid) AS default_expression
    INTO actual FROM pg_attribute a
    LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
    WHERE a.attrelid = to_regclass(format('safe_walk_nearby.%I', expected.table_name))
      AND a.attname = expected.column_name AND a.attnum > 0 AND NOT a.attisdropped;
    IF NOT FOUND OR actual.attnotnull IS DISTINCT FROM expected.required
        OR actual.default_expression IS DISTINCT FROM expected.default_expression THEN
      RAISE EXCEPTION 'Missing column or nullability/default mismatch: %.%',
        expected.table_name, expected.column_name;
    END IF;
    IF expected.type_name = 'geography' THEN
      IF actual.atttypid IS DISTINCT FROM geography_type OR
          format_type(actual.atttypid, actual.atttypmod)
            IS DISTINCT FROM format('%I.geography(Point,4326)', postgis_schema) THEN
        RAISE EXCEPTION 'Expected installed PostGIS geography(Point,4326): %.%',
          expected.table_name, expected.column_name;
      END IF;
    ELSIF actual.atttypid IS DISTINCT FROM to_regtype(expected.type_name)
        OR actual.atttypmod <> -1 THEN
      RAISE EXCEPTION 'Column type mismatch: %.%', expected.table_name, expected.column_name;
    END IF;
  END LOOP;

  -- Verify the exact PK/UNIQUE keys through their ordered column names.
  FOR expected IN SELECT * FROM (VALUES
    ('helper_profiles', 'p', ARRAY['user_id']),
    ('helper_locations', 'p', ARRAY['user_id']),
    ('alerts', 'p', ARRAY['id']),
    ('alerts', 'u', ARRAY['sender_id', 'client_request_id']),
    ('alert_deliveries', 'p', ARRAY['alert_id', 'recipient_id'])
  ) AS keys(table_name, kind, column_names)
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint c
      WHERE c.conrelid = to_regclass(format('safe_walk_nearby.%I', expected.table_name))
        AND c.contype::text = expected.kind AND c.convalidated
        AND NOT c.condeferrable
        AND (SELECT array_agg(a.attname::text ORDER BY k.position)
             FROM unnest(c.conkey) WITH ORDINALITY AS k(attribute_number, position)
             JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = k.attribute_number)
          = expected.column_names
    ) THEN
      RAISE EXCEPTION 'Missing design PK/UNIQUE: % %', expected.table_name, expected.column_names;
    END IF;
  END LOOP;

  FOR expected IN SELECT * FROM (VALUES
    ('helper_profiles', 'user_id', 'auth.users', 'id'),
    ('helper_locations', 'user_id', 'safe_walk_nearby.helper_profiles', 'user_id'),
    ('alerts', 'sender_id', 'auth.users', 'id'),
    ('alert_deliveries', 'alert_id', 'safe_walk_nearby.alerts', 'id'),
    ('alert_deliveries', 'recipient_id', 'safe_walk_nearby.helper_profiles', 'user_id')
  ) AS fks(table_name, column_name, referenced_table, referenced_column)
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint c
      JOIN pg_attribute a ON a.attrelid = c.conrelid AND c.conkey = ARRAY[a.attnum]
      JOIN pg_attribute r ON r.attrelid = c.confrelid AND c.confkey = ARRAY[r.attnum]
      WHERE c.conrelid = to_regclass(format('safe_walk_nearby.%I', expected.table_name))
        AND c.contype = 'f' AND c.convalidated AND NOT c.condeferrable
        AND c.confrelid = to_regclass(expected.referenced_table)
        AND a.attname = expected.column_name AND r.attname = expected.referenced_column
        AND c.confdeltype = 'c' AND c.confupdtype = 'a' AND c.confmatchtype = 's'
    ) THEN
      RAISE EXCEPTION 'Missing validated CASCADE FK: %.%', expected.table_name, expected.column_name;
    END IF;
  END LOOP;
  IF (SELECT count(*) FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid
      WHERE t.relnamespace = target_schema) <> 12 THEN
    RAISE EXCEPTION 'Expected exactly 4 PK, 5 FK, 1 UNIQUE and 2 CHECK constraints';
  END IF;

  -- Normalize SQL keyword case, rendering parentheses/whitespace and numeric casts.
  -- No substring match: changed operators, constants or extra clauses fail.
  FOR expected IN SELECT * FROM (VALUES
    ('helper_locations', 'accuracy_misnulloraccuracy_m>=0'), ('alerts', 'radius_m=500')
  ) AS checks(table_name, expression)
  LOOP
    SELECT lower(regexp_replace(
      regexp_replace(pg_get_expr(c.conbin, c.conrelid),
        '::(double precision|real|integer|numeric)', '', 'g'),
      '[[:space:]()]', '', 'g'))
    INTO normalized_check FROM pg_constraint c
    WHERE c.conrelid = to_regclass(format('safe_walk_nearby.%I', expected.table_name))
      AND c.contype = 'c' AND c.convalidated;
    IF NOT FOUND OR normalized_check IS DISTINCT FROM expected.expression THEN
      RAISE EXCEPTION 'CHECK mismatch on %', expected.table_name;
    END IF;
  END LOOP;

  IF NOT EXISTS (
    SELECT 1 FROM pg_index i JOIN pg_class idx ON idx.oid = i.indexrelid
    JOIN pg_am am ON am.oid = idx.relam
    JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attname = 'geog'
    WHERE i.indrelid = 'safe_walk_nearby.helper_locations'::regclass
      AND am.amname = 'gist' AND i.indisvalid AND i.indisready
      AND i.indnkeyatts = 1 AND i.indnatts = 1 AND i.indkey[0] = a.attnum
      AND i.indpred IS NULL AND i.indexprs IS NULL
  ) THEN
    RAISE EXCEPTION 'Missing valid, unconditional single-column geog GiST index';
  END IF;

  -- PUBLIC is a pseudo-role: inspect raw ACLs as well as each real API role's
  -- effective privileges, which include grants inherited from other roles.
  IF EXISTS (SELECT 1 FROM pg_namespace n,
      LATERAL aclexplode(coalesce(n.nspacl, acldefault('n', n.nspowner))) a
      WHERE n.oid = target_schema AND a.grantee = 0)
      OR EXISTS (SELECT 1 FROM pg_class c,
      LATERAL aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
      WHERE c.relnamespace = target_schema AND c.relkind = 'r' AND a.grantee = 0) THEN
    RAISE EXCEPTION 'PUBLIC retains schema or table ACL';
  END IF;
  FOREACH api_role IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = api_role) THEN
      RAISE EXCEPTION 'Expected API role % is missing', api_role;
    END IF;
    IF has_schema_privilege(api_role, target_schema, 'USAGE') OR
        has_schema_privilege(api_role, target_schema, 'CREATE') THEN
      RAISE EXCEPTION 'API role % has effective schema access', api_role;
    END IF;
    FOR relation IN SELECT oid, relname, relrowsecurity FROM pg_class
      WHERE relnamespace = target_schema AND relkind = 'r'
    LOOP
      IF NOT relation.relrowsecurity OR EXISTS (
        SELECT 1 FROM unnest(ARRAY[
          'SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'
        ]) AS privilege_name
        WHERE has_table_privilege(api_role, relation.oid, privilege_name)
      ) OR has_any_column_privilege(api_role, relation.oid, 'SELECT')
        OR has_any_column_privilege(api_role, relation.oid, 'INSERT')
        OR has_any_column_privilege(api_role, relation.oid, 'UPDATE')
        OR has_any_column_privilege(api_role, relation.oid, 'REFERENCES') THEN
        RAISE EXCEPTION 'RLS/effective table or column ACL mismatch: % / %', api_role, relation.relname;
      END IF;
    END LOOP;
  END LOOP;
END
$verify$;

-- Aggregate counts only; no contents are selected. Empty tables are expected
-- immediately after provisioning; a later nonzero count is reported, not erased.
SELECT 'helper_profiles' AS table_name, count(*) AS row_count
FROM safe_walk_nearby.helper_profiles
UNION ALL SELECT 'helper_locations', count(*) FROM safe_walk_nearby.helper_locations
UNION ALL SELECT 'alerts', count(*) FROM safe_walk_nearby.alerts
UNION ALL SELECT 'alert_deliveries', count(*) FROM safe_walk_nearby.alert_deliveries;
COMMIT;
