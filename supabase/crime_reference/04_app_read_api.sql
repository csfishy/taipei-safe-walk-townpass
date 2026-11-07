-- MANUAL ONLY, LEVEL C. Reviewed read-only App query interface for the private
-- crime_reference snapshot (PR #44). Not a Supabase CLI migration, Demo seed,
-- CI job or reset target. Nothing here writes, updates, deletes or truncates
-- crime_reference data, and no table/schema grant to anon/authenticated changes.
--
-- What it creates: one function, public.safe_walk_crime_reference_query, callable
-- by the public client key through PostgREST:
--   POST /rest/v1/rpc/safe_walk_crime_reference_query
--
-- Why SECURITY DEFINER: crime_reference tables keep RLS+FORCE and have no
-- anon/authenticated grants (verified by 02_verify_snapshot.sql). A SECURITY
-- INVOKER function would require loosening those grants. Instead this single
-- function runs as its owner (postgres) with an empty search_path, fully
-- qualified names, validated and bounded arguments, one pinned reviewed
-- snapshot and a fixed list of returned columns. raw_payload, record_payload,
-- geocoding, evidence and snapshot/source metadata JSON are never returned.
--
-- To publish a different snapshot later: review it, verify it with
-- 02_verify_snapshot.sql, then change c_snapshot below in a new reviewed PR.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
DO $guard$
BEGIN
  IF current_user <> 'postgres' THEN
    RAISE EXCEPTION 'Apply the App read interface as the postgres role';
  END IF;
  IF to_regclass('crime_reference.records') IS NULL
     OR to_regclass('crime_reference.sources') IS NULL
     OR to_regclass('crime_reference.snapshots') IS NULL THEN
    RAISE EXCEPTION 'crime_reference tables are missing; apply PR #44 manual SQL first';
  END IF;
  IF 'crime_reference' = ANY(regexp_split_to_array(
       coalesce(current_setting('pgrst.db_schemas', true), ''), '\s*,\s*')) THEN
    RAISE EXCEPTION 'crime_reference must not be an exposed PostgREST schema';
  END IF;
END;
$guard$;

CREATE OR REPLACE FUNCTION public.safe_walk_crime_reference_query(
  p_city text DEFAULT NULL,
  p_category text DEFAULT NULL,
  p_from date DEFAULT NULL,
  p_to date DEFAULT NULL,
  p_min_lat double precision DEFAULT NULL,
  p_min_lng double precision DEFAULT NULL,
  p_max_lat double precision DEFAULT NULL,
  p_max_lng double precision DEFAULT NULL,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $body$
DECLARE
  -- Reviewed snapshot imported 2026-11-07 (PR #44). Pinned on purpose: a newer
  -- or partially imported snapshot is never served without another review.
  c_snapshot constant uuid := '5ea3810c-5744-4b89-baad-0121c8fc951b';
  c_max_limit constant integer := 200;
  c_max_offset constant integer := 5000;
  c_max_bbox_span constant double precision := 0.5;
  v_bbox boolean;
  v_snapshot_label text;
  v_as_of date;
  v_imported timestamptz;
  v_expected integer;
  v_actual bigint;
  v_total bigint;
  v_records jsonb;
  v_sources jsonb;
BEGIN
  IF p_city IS NOT NULL AND p_city NOT IN ('臺北市', '新北市', '基隆市') THEN
    RAISE EXCEPTION 'crime_reference_invalid_argument'
      USING ERRCODE = '22023', DETAIL = 'city';
  END IF;
  IF p_category IS NOT NULL
     AND (length(btrim(p_category)) = 0 OR length(p_category) > 64) THEN
    RAISE EXCEPTION 'crime_reference_invalid_argument'
      USING ERRCODE = '22023', DETAIL = 'category';
  END IF;
  IF p_from IS NOT NULL AND p_to IS NOT NULL AND p_from > p_to THEN
    RAISE EXCEPTION 'crime_reference_invalid_argument'
      USING ERRCODE = '22023', DETAIL = 'date_range';
  END IF;
  IF p_limit IS NULL OR p_limit < 1 OR p_limit > c_max_limit THEN
    RAISE EXCEPTION 'crime_reference_invalid_argument'
      USING ERRCODE = '22023', DETAIL = 'limit';
  END IF;
  IF p_offset IS NULL OR p_offset < 0 OR p_offset > c_max_offset THEN
    RAISE EXCEPTION 'crime_reference_invalid_argument'
      USING ERRCODE = '22023', DETAIL = 'offset';
  END IF;
  v_bbox := p_min_lat IS NOT NULL OR p_min_lng IS NOT NULL
            OR p_max_lat IS NOT NULL OR p_max_lng IS NOT NULL;
  IF v_bbox AND (
       p_min_lat IS NULL OR p_min_lng IS NULL OR p_max_lat IS NULL OR p_max_lng IS NULL
       OR p_min_lat < -90 OR p_max_lat > 90 OR p_min_lng < -180 OR p_max_lng > 180
       OR p_min_lat > p_max_lat OR p_min_lng > p_max_lng
       OR p_max_lat - p_min_lat > c_max_bbox_span
       OR p_max_lng - p_min_lng > c_max_bbox_span) THEN
    RAISE EXCEPTION 'crime_reference_invalid_argument'
      USING ERRCODE = '22023', DETAIL = 'bbox';
  END IF;

  SELECT s.label, s.as_of_date, s.imported_at, s.expected_record_count
    INTO v_snapshot_label, v_as_of, v_imported, v_expected
  FROM crime_reference.snapshots s
  WHERE s.snapshot_id = c_snapshot;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'crime_reference_snapshot_unavailable'
      USING ERRCODE = 'P0001', DETAIL = 'missing';
  END IF;
  SELECT count(*) INTO v_actual
  FROM crime_reference.records r
  WHERE r.snapshot_id = c_snapshot;
  IF v_actual <> v_expected THEN
    RAISE EXCEPTION 'crime_reference_snapshot_unavailable'
      USING ERRCODE = 'P0001', DETAIL = 'incomplete';
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'sourceKey', x.source_key,
           'datasetId', x.dataset_id,
           'resourceId', x.resource_id,
           'name', x.name,
           'sourceUrl', x.source_url,
           'resourceUrl', x.resource_url,
           'license', x.license,
           'retrievedAt', x.retrieved_at,
           'dataUpdatedAt', x.data_updated_at,
           'recordCount', x.expected_record_count
         ) ORDER BY x.source_key COLLATE "C"), '[]'::jsonb)
    INTO v_sources
  FROM crime_reference.sources x
  WHERE x.snapshot_id = c_snapshot;

  WITH filtered AS (
    SELECT r.source_key, r.source_record_id, r.event_date, r.city, r.district,
           r.category, r.location_text, r.latitude, r.longitude,
           r.spatial_precision, r.confidence, r.coordinate_status
    FROM crime_reference.records r
    WHERE r.snapshot_id = c_snapshot
      AND (p_city IS NULL OR r.city = p_city)
      AND (p_category IS NULL OR r.category = p_category)
      AND (p_from IS NULL OR r.event_date >= p_from)
      AND (p_to IS NULL OR r.event_date <= p_to)
      AND (NOT v_bbox OR (
            r.latitude IS NOT NULL
            AND r.latitude BETWEEN p_min_lat AND p_max_lat
            AND r.longitude BETWEEN p_min_lng AND p_max_lng))
  ), page AS (
    SELECT f.* FROM filtered f
    ORDER BY f.event_date DESC, f.source_key COLLATE "C", f.source_record_id COLLATE "C"
    LIMIT p_limit OFFSET p_offset
  )
  SELECT (SELECT count(*) FROM filtered),
         coalesce((SELECT jsonb_agg(jsonb_build_object(
             'sourceKey', g.source_key,
             'sourceRecordId', g.source_record_id,
             'eventDate', g.event_date,
             'city', g.city,
             'district', g.district,
             'category', g.category,
             'locationText', g.location_text,
             'latitude', g.latitude,
             'longitude', g.longitude,
             'spatialPrecision', g.spatial_precision,
             'confidence', g.confidence,
             'coordinateStatus', g.coordinate_status
           ) ORDER BY g.event_date DESC, g.source_key COLLATE "C",
                      g.source_record_id COLLATE "C")
           FROM page g), '[]'::jsonb)
    INTO v_total, v_records;

  RETURN jsonb_build_object(
    'interfaceVersion', 1,
    'snapshot', jsonb_build_object(
      'snapshotId', c_snapshot,
      'label', v_snapshot_label,
      'asOfDate', v_as_of,
      'importedAt', v_imported,
      'recordCount', v_actual),
    'sources', v_sources,
    'query', jsonb_build_object(
      'city', p_city, 'category', p_category, 'from', p_from, 'to', p_to,
      'bbox', CASE WHEN v_bbox THEN jsonb_build_object(
        'minLat', p_min_lat, 'minLng', p_min_lng,
        'maxLat', p_max_lat, 'maxLng', p_max_lng) END,
      'limit', p_limit, 'offset', p_offset),
    'totalMatching', v_total,
    'records', v_records);
END;
$body$;

COMMENT ON FUNCTION public.safe_walk_crime_reference_query(
  text, text, date, date, double precision, double precision,
  double precision, double precision, integer, integer) IS
  'Read-only App query of the pinned reviewed crime_reference snapshot. Reference coordinates are not precise crime locations.';
ALTER FUNCTION public.safe_walk_crime_reference_query(
  text, text, date, date, double precision, double precision,
  double precision, double precision, integer, integer) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.safe_walk_crime_reference_query(
  text, text, date, date, double precision, double precision,
  double precision, double precision, integer, integer)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.safe_walk_crime_reference_query(
  text, text, date, date, double precision, double precision,
  double precision, double precision, integer, integer)
  TO anon, authenticated;
COMMIT;

-- READ-ONLY CHECKS after COMMIT (run as postgres; no data is changed):
-- 1. The function is SECURITY DEFINER with an empty search_path.
--    SELECT p.prosecdef, p.proconfig, p.provolatile
--    FROM pg_proc p WHERE p.oid =
--      'public.safe_walk_crime_reference_query(text,text,date,date,double precision,double precision,double precision,double precision,integer,integer)'::regprocedure;
-- 2. EXECUTE only for anon/authenticated; tables stay closed to them.
--    SELECT has_function_privilege('anon', 'public.safe_walk_crime_reference_query(text,text,date,date,double precision,double precision,double precision,double precision,integer,integer)', 'EXECUTE');
--    SELECT has_schema_privilege('anon', 'crime_reference', 'USAGE'),
--           has_table_privilege('anon', 'crime_reference.records', 'SELECT');  -- both false
-- 3. Rerun 02_verify_snapshot.sql: it must still pass unchanged.
-- 4. Sample call: SELECT jsonb_pretty(public.safe_walk_crime_reference_query(p_city => '臺北市', p_limit => 3));
