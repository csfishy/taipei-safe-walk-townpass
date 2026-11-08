-- MANUAL ONLY. Artificial reports only; every INSERT/DELETE is rolled back.
-- This never resolves an existing real report or touches another schema.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
SET LOCAL extra_float_digits = 0;

DO $permissions$
DECLARE
  v_role text;
  v_table text;
BEGIN
  FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated'] LOOP
    IF has_schema_privilege(v_role, 'safe_walk_reports', 'USAGE') THEN
      RAISE EXCEPTION 'unexpected direct report schema access';
    END IF;
    FOREACH v_table IN ARRAY ARRAY['safe_walk_reports.reports', 'safe_walk_reports.resolved_ids'] LOOP
      IF has_table_privilege(v_role, v_table, 'SELECT')
         OR has_table_privilege(v_role, v_table, 'INSERT')
         OR has_table_privilege(v_role, v_table, 'UPDATE')
         OR has_table_privilege(v_role, v_table, 'DELETE') THEN
        RAISE EXCEPTION 'unexpected direct report table access';
      END IF;
      IF NOT EXISTS (SELECT 1 FROM pg_class c
        WHERE c.oid = to_regclass(v_table) AND c.relrowsecurity AND c.relforcerowsecurity) THEN
        RAISE EXCEPTION 'report table RLS/FORCE missing';
      END IF;
    END LOOP;
    IF NOT has_function_privilege(v_role,
      'public.safe_walk_map_report_resolve(uuid)', 'EXECUTE') THEN
      RAISE EXCEPTION 'required community resolution RPC access missing';
    END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM pg_proc p,
    LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
    WHERE p.oid = 'public.safe_walk_map_report_resolve(uuid)'::regprocedure
      AND a.grantee = 0 AND a.privilege_type = 'EXECUTE') THEN
    RAISE EXCEPTION 'PUBLIC must not execute resolution RPC';
  END IF;
END;
$permissions$;

SET LOCAL ROLE anon;
DO $resolve$
DECLARE
  v_selected uuid := gen_random_uuid();
  v_other uuid := gen_random_uuid();
  v_missing uuid := gen_random_uuid();
  v_first jsonb;
  v_retry jsonb;
  v_page jsonb;
  v_lat constant double precision := 0.012345678901234567;
  v_lng constant double precision := 0.0567890123456789123;
BEGIN
  PERFORM set_config('safe_walk.test_resolve_selected', v_selected::text, true);
  PERFORM set_config('safe_walk.test_resolve_other', v_other::text, true);
  PERFORM set_config('safe_walk.test_resolve_missing', v_missing::text, true);
  PERFORM public.safe_walk_map_report_submit(v_selected, 'other', v_lat, v_lng,
    '人工已排除測試，所有變更交易結束即回滾');
  PERFORM public.safe_walk_map_report_submit(v_other, 'lighting', v_lat, v_lng,
    '人工對照回報，不能隨另一筆移除');
  v_first := public.safe_walk_map_report_resolve(v_selected);
  IF v_first IS DISTINCT FROM jsonb_build_object(
      'interfaceVersion', 1, 'reportId', v_selected, 'removed', true) THEN
    RAISE EXCEPTION 'resolution acknowledgement does not match selected report';
  END IF;
  v_retry := public.safe_walk_map_report_resolve(v_selected);
  IF v_retry IS DISTINCT FROM jsonb_build_object(
      'interfaceVersion', 1, 'reportId', v_selected, 'removed', false) THEN
    RAISE EXCEPTION 'repeated resolution is not idempotent';
  END IF;
  IF public.safe_walk_map_report_resolve(v_missing) IS DISTINCT FROM jsonb_build_object(
      'interfaceVersion', 1, 'reportId', v_missing, 'removed', false) THEN
    RAISE EXCEPTION 'absent report resolution is not acknowledged';
  END IF;
  v_page := public.safe_walk_map_report_query(v_lat, v_lng, v_lat, v_lng, 200, 0);
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_page->'records') r
             WHERE (r->>'id')::uuid = v_selected)
     OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_page->'records') r
                    WHERE (r->>'id')::uuid = v_other) THEN
    RAISE EXCEPTION 'resolution removed another report or selected report reloaded';
  END IF;
  BEGIN
    PERFORM public.safe_walk_map_report_submit(v_selected, 'other', v_lat, v_lng,
      '人工已排除測試，所有變更交易結束即回滾');
    RAISE EXCEPTION 'delayed submit recreated a resolved report';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
  BEGIN
    PERFORM public.safe_walk_map_report_resolve(NULL);
    RAISE EXCEPTION 'null report UUID was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  BEGIN
    PERFORM 1 FROM safe_walk_reports.resolved_ids;
    RAISE EXCEPTION 'anon can read private retired request IDs';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  IF current_setting('extra_float_digits') <> '0' THEN
    RAISE EXCEPTION 'RPC precision setting leaked to caller';
  END IF;
END;
$resolve$;

SET LOCAL ROLE authenticated;
DO $authenticated$
DECLARE
  v_other uuid := current_setting('safe_walk.test_resolve_other')::uuid;
BEGIN
  IF public.safe_walk_map_report_resolve(v_other) IS DISTINCT FROM jsonb_build_object(
      'interfaceVersion', 1, 'reportId', v_other, 'removed', true) THEN
    RAISE EXCEPTION 'authenticated community resolution failed';
  END IF;
  BEGIN
    PERFORM 1 FROM safe_walk_reports.resolved_ids;
    RAISE EXCEPTION 'authenticated can read private retired request IDs';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END;
$authenticated$;

RESET ROLE;
DO $physical_deletion$
DECLARE
  v_selected uuid := current_setting('safe_walk.test_resolve_selected')::uuid;
  v_other uuid := current_setting('safe_walk.test_resolve_other')::uuid;
  v_missing uuid := current_setting('safe_walk.test_resolve_missing')::uuid;
BEGIN
  IF EXISTS (SELECT 1 FROM safe_walk_reports.reports WHERE id IN (v_selected, v_other)) THEN
    RAISE EXCEPTION 'report data was not physically deleted';
  END IF;
  IF (SELECT count(*) FROM safe_walk_reports.resolved_ids WHERE id IN (v_selected, v_other)) <> 2
     OR EXISTS (SELECT 1 FROM safe_walk_reports.resolved_ids WHERE id = v_missing) THEN
    RAISE EXCEPTION 'retirement must track only physically removed reports';
  END IF;
  IF (SELECT array_agg(column_name::text ORDER BY ordinal_position)
      FROM information_schema.columns
      WHERE table_schema = 'safe_walk_reports' AND table_name = 'resolved_ids')
      IS DISTINCT FROM ARRAY['id', 'resolved_at']::text[] THEN
    RAISE EXCEPTION 'retired IDs must not retain report data';
  END IF;
END;
$physical_deletion$;

-- Fill only artificial retirement metadata inside this transaction to verify
-- the bounded mutation budget. No real report is selected or removed.
DO $cap_setup$
DECLARE
  v_capped uuid := gen_random_uuid();
BEGIN
  PERFORM set_config('safe_walk.test_resolve_capped', v_capped::text, true);
  PERFORM public.safe_walk_map_report_submit(v_capped, 'other', 0.01234, 0.05678,
    '人工限流測試，必須保留直到交易回滾');
  INSERT INTO safe_walk_reports.resolved_ids (id)
    SELECT gen_random_uuid() FROM generate_series(1, 60);
END;
$cap_setup$;
SET LOCAL ROLE anon;
DO $cap$
BEGIN
  BEGIN
    PERFORM public.safe_walk_map_report_resolve(
      current_setting('safe_walk.test_resolve_capped')::uuid);
    RAISE EXCEPTION 'resolution burst cap did not reject an additional mutation';
  EXCEPTION WHEN SQLSTATE 'PT429' THEN NULL;
  END;
END;
$cap$;
RESET ROLE;
DO $cap_preserves_report$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM safe_walk_reports.reports
                 WHERE id = current_setting('safe_walk.test_resolve_capped')::uuid) THEN
    RAISE EXCEPTION 'rate-limited resolution removed the report';
  END IF;
END;
$cap_preserves_report$;
ROLLBACK;
