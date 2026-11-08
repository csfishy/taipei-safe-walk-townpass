-- Manual acceptance with an artificial coordinate. ALL inserts are rolled
-- back. This never writes crime_reference, emergency or Demo data.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
-- Reproduce the API session setting that previously rounded saved coordinates
-- in a successful HTTP response and caused the App to reject the acknowledgement.
SET LOCAL extra_float_digits = 0;
DO $grants$
DECLARE
  v_role text;
BEGIN
  FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated'] LOOP
    IF has_schema_privilege(v_role, 'safe_walk_reports', 'USAGE')
       OR has_table_privilege(v_role, 'safe_walk_reports.reports', 'SELECT')
       OR has_table_privilege(v_role, 'safe_walk_reports.reports', 'INSERT')
       OR has_table_privilege(v_role, 'safe_walk_reports.reports', 'UPDATE')
       OR has_table_privilege(v_role, 'safe_walk_reports.reports', 'DELETE') THEN
      RAISE EXCEPTION 'unexpected direct report grants';
    END IF;
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'safe_walk_reports' AND c.relname = 'reports'
      AND c.relrowsecurity AND c.relforcerowsecurity) THEN
    RAISE EXCEPTION 'report RLS/FORCE missing';
  END IF;
END;
$grants$;
SET LOCAL ROLE anon;
DO $test$
DECLARE
  v_id uuid := gen_random_uuid();
  v_first jsonb;
  v_retry jsonb;
  v_page jsonb;
  v_reloaded jsonb;
  v_lat constant double precision := 0.012345678901234567;
  v_lng constant double precision := 0.0567890123456789123;
BEGIN
  v_first := public.safe_walk_map_report_submit(
    v_id, 'other', v_lat, v_lng, '人工驗證資料，交易結束即回滾');
  v_retry := public.safe_walk_map_report_submit(
    v_id, 'other', v_lat, v_lng, '人工驗證資料，交易結束即回滾');
  -- PostgREST serializes the jsonb after the function restores caller settings.
  v_first := (v_first::text)::jsonb;
  v_retry := (v_retry::text)::jsonb;
  IF v_first <> v_retry OR (v_first->'report'->>'id')::uuid <> v_id THEN
    RAISE EXCEPTION 'idempotent acknowledgement failed';
  END IF;
  IF (v_first->'report'->>'latitude')::double precision IS DISTINCT FROM v_lat
     OR (v_first->'report'->>'longitude')::double precision IS DISTINCT FROM v_lng THEN
    RAISE EXCEPTION 'submitted coordinates lost precision in acknowledgement';
  END IF;
  v_page := public.safe_walk_map_report_query(v_lat, v_lng, v_lat, v_lng, 200, 0);
  v_page := (v_page::text)::jsonb;
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_page->'records') r
                 WHERE (r->>'id')::uuid = v_id) THEN
    RAISE EXCEPTION 'submitted report missing from reload';
  END IF;
  IF (SELECT count(*) FROM jsonb_array_elements(v_page->'records') r
       WHERE (r->>'id')::uuid = v_id) <> 1 THEN
    RAISE EXCEPTION 'retry duplicated the report';
  END IF;
  SELECT r INTO v_reloaded FROM jsonb_array_elements(v_page->'records') r
    WHERE (r->>'id')::uuid = v_id;
  IF (v_reloaded->>'latitude')::double precision IS DISTINCT FROM v_lat
     OR (v_reloaded->>'longitude')::double precision IS DISTINCT FROM v_lng THEN
    RAISE EXCEPTION 'reloaded coordinates lost precision';
  END IF;
  IF current_setting('extra_float_digits') <> '0' THEN
    RAISE EXCEPTION 'RPC precision setting leaked into caller session';
  END IF;
  BEGIN
    PERFORM 1 FROM safe_walk_reports.reports LIMIT 1;
    RAISE EXCEPTION 'anon direct table access accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM public.safe_walk_map_report_submit(v_id, 'fight', v_lat, v_lng, 'changed');
    RAISE EXCEPTION 'changed retry must fail';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
  BEGIN
    PERFORM public.safe_walk_map_report_submit(gen_random_uuid(), 'invalid', 0, 0, '');
    RAISE EXCEPTION 'invalid category accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  BEGIN
    PERFORM public.safe_walk_map_report_submit(gen_random_uuid(), 'other', 'NaN', 0, '');
    RAISE EXCEPTION 'NaN coordinate accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  BEGIN
    PERFORM public.safe_walk_map_report_submit(gen_random_uuid(), 'other', 0, 'Infinity', '');
    RAISE EXCEPTION 'infinite coordinate accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  BEGIN
    PERFORM public.safe_walk_map_report_submit(gen_random_uuid(), 'other', '-Infinity', 0, '');
    RAISE EXCEPTION 'negative infinite coordinate accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  BEGIN
    PERFORM public.safe_walk_map_report_query(0, 0, 'NaN', 0, 200, 0);
    RAISE EXCEPTION 'NaN bounds accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  BEGIN
    PERFORM public.safe_walk_map_report_query(p_limit => 201);
    RAISE EXCEPTION 'unbounded query accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
END;
$test$;
SET LOCAL ROLE authenticated;
DO $authenticated$
BEGIN
  IF public.safe_walk_map_report_query(p_limit => 1)->>'interfaceVersion' IS DISTINCT FROM '1' THEN
    RAISE EXCEPTION 'authenticated report query failed';
  END IF;
  BEGIN
    PERFORM 1 FROM safe_walk_reports.reports LIMIT 1;
    RAISE EXCEPTION 'authenticated direct table access accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END;
$authenticated$;
ROLLBACK;
