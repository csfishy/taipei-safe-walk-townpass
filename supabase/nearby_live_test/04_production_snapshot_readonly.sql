-- READ ONLY. Compare this output before/after installation and activation.
-- Only counts and digests leave the server; no row contents are returned.
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL statement_timeout='30s';
DO $snapshot$
DECLARE t record; n bigint; digest text; rows jsonb:='[]'::jsonb;
BEGIN
  FOR t IN SELECT relname FROM pg_class
    WHERE relnamespace='safe_walk_nearby'::regnamespace AND relkind='r'
    ORDER BY relname LOOP
    EXECUTE format('SELECT count(*),md5(coalesce(string_agg(h,'''' ORDER BY h),'''')) FROM (SELECT md5(to_jsonb(r)::text) h FROM safe_walk_nearby.%I r) s',t.relname)
      INTO n,digest;
    rows:=rows||jsonb_build_array(jsonb_build_object('table',t.relname,'rows',n,'digest',digest));
  END LOOP;
  PERFORM set_config('safe_walk_audit.snapshot',rows::text,true);
END $snapshot$;
SELECT current_setting('safe_walk_audit.snapshot')::jsonb AS production_data,
  (SELECT md5(string_agg(row(p.oid::regprocedure::text,p.proowner,p.proacl,p.proconfig,
    replace(pg_get_functiondef(p.oid),E'\r\n',E'\n'))::text,'' ORDER BY p.oid))
   FROM pg_proc p WHERE (p.pronamespace='safe_walk_nearby'::regnamespace)
     OR (p.pronamespace='public'::regnamespace AND (left(p.proname,7)='nearby_'
       OR p.proname IN('set_helper_opt_in','send_emergency_alert','fetch_pending_alerts')))) AS production_function_digest,
  (SELECT md5(string_agg(row(c.oid,c.relname,c.relowner,c.relacl,c.relrowsecurity,c.relforcerowsecurity)::text,'' ORDER BY c.oid))
   FROM pg_class c WHERE c.relnamespace='safe_walk_nearby'::regnamespace) AS production_relation_acl_digest,
  (SELECT md5(row(n.nspowner,n.nspacl)::text) FROM pg_namespace n WHERE n.oid='safe_walk_nearby'::regnamespace) AS production_schema_acl_digest;
ROLLBACK;
