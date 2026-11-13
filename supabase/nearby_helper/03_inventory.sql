-- Manual metadata inventory only. Does not call business RPCs or read user rows.
BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '15s';
SET LOCAL search_path = pg_catalog;
WITH inventory AS (
  SELECT 'extensions' AS section, jsonb_agg(jsonb_build_object(
    'name', e.extname, 'schema', n.nspname, 'version', e.extversion)
    ORDER BY e.extname) AS details
  FROM pg_extension e JOIN pg_namespace n ON n.oid = e.extnamespace
  WHERE e.extname IN ('postgis', 'pgcrypto', 'pg_cron')
  UNION ALL
  SELECT 'tables', jsonb_agg(jsonb_build_object(
    'name', c.relname, 'rls', c.relrowsecurity, 'owner', pg_get_userbyid(c.relowner),
    'columns', (SELECT jsonb_agg(jsonb_build_object('name', a.attname,
      'type', format_type(a.atttypid, a.atttypmod), 'required', a.attnotnull,
      'default', pg_get_expr(d.adbin, d.adrelid)) ORDER BY a.attnum)
      FROM pg_attribute a LEFT JOIN pg_attrdef d
        ON d.adrelid = a.attrelid AND d.adnum = a.attnum
      WHERE a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped),
    'constraints', (SELECT jsonb_agg(pg_get_constraintdef(k.oid) ORDER BY k.conname)
      FROM pg_constraint k WHERE k.conrelid = c.oid),
    'indexes', (SELECT jsonb_agg(pg_get_indexdef(i.indexrelid) ORDER BY i.indexrelid)
      FROM pg_index i WHERE i.indrelid = c.oid),
    'policies', (SELECT count(*) FROM pg_policy p WHERE p.polrelid = c.oid),
    'user_triggers', (SELECT count(*) FROM pg_trigger t
      WHERE t.tgrelid = c.oid AND NOT t.tgisinternal)) ORDER BY c.relname)
  FROM pg_class c WHERE c.relnamespace = to_regnamespace('safe_walk_nearby')
    AND c.relkind = 'r'
  UNION ALL
  SELECT 'table_acl', jsonb_agg(jsonb_build_object('table', c.relname,
    'role', r.rolname, 'schema_usage', has_schema_privilege(r.oid, c.relnamespace, 'USAGE'),
    'table_access', has_table_privilege(r.oid, c.oid,
      'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'),
    'column_access', has_any_column_privilege(r.oid, c.oid,
      'SELECT,INSERT,UPDATE,REFERENCES')) ORDER BY c.relname, r.rolname)
  FROM pg_class c CROSS JOIN pg_roles r
  WHERE c.relnamespace = to_regnamespace('safe_walk_nearby') AND c.relkind = 'r'
    AND r.rolname IN ('anon', 'authenticated', 'service_role')
  UNION ALL
  SELECT 'functions', jsonb_agg(jsonb_build_object('signature', p.oid::regprocedure::text,
    'returns', pg_get_function_result(p.oid), 'owner', pg_get_userbyid(p.proowner),
    'definer', p.prosecdef, 'config', p.proconfig, 'body_md5', md5(p.prosrc),
    'anon_execute', has_function_privilege('anon', p.oid, 'EXECUTE'),
    'authenticated_execute', has_function_privilege('authenticated', p.oid, 'EXECUTE'),
    'public_execute', EXISTS (SELECT 1 FROM aclexplode(coalesce(p.proacl,
      acldefault('f', p.proowner))) a WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE'))
    ORDER BY p.oid::regprocedure::text)
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'safe_walk_nearby' OR (n.nspname = 'public'
    AND (p.proname LIKE 'nearby\_%' ESCAPE '\'
      OR p.proname IN ('set_helper_opt_in', 'send_emergency_alert', 'fetch_pending_alerts')))
)
SELECT section, details FROM inventory ORDER BY section;
ROLLBACK;
