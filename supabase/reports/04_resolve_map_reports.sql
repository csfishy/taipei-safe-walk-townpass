-- MANUAL ONLY / Level C. User-requested community "已排除" action.
-- A public client can resolve one UUID, physically deleting only that report.
-- No ownership identity is claimed. No batch deletion or table access is added.
-- This schema stays separate from crime_reference, nearby and Demo reset.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
DO $guard$
BEGIN
  IF current_user <> 'postgres' THEN
    RAISE EXCEPTION 'Apply map report resolution as the postgres role';
  END IF;
  IF to_regclass('safe_walk_reports.reports') IS NULL
     OR to_regprocedure('public.safe_walk_map_report_submit(uuid,text,double precision,double precision,text)') IS NULL
     OR to_regprocedure('public.safe_walk_map_report_query(double precision,double precision,double precision,double precision,integer,integer)') IS NULL THEN
    RAISE EXCEPTION 'Map report interface missing; apply 01_map_report_api.sql first';
  END IF;
  IF 'safe_walk_reports' = ANY(regexp_split_to_array(
       coalesce(current_setting('pgrst.db_schemas', true), ''), '\s*,\s*')) THEN
    RAISE EXCEPTION 'safe_walk_reports must remain a private schema';
  END IF;
END;
$guard$;

-- No report coordinates, category, description or caller identity are kept
-- after deletion. Retain only retired request UUIDs to prevent delayed submit
-- retries from recreating reports that the community already removed.
CREATE TABLE IF NOT EXISTS safe_walk_reports.resolved_ids (
  id uuid PRIMARY KEY,
  resolved_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX IF NOT EXISTS map_reports_resolved_at_idx
  ON safe_walk_reports.resolved_ids (resolved_at DESC);
ALTER TABLE safe_walk_reports.resolved_ids ENABLE ROW LEVEL SECURITY;
ALTER TABLE safe_walk_reports.resolved_ids FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE safe_walk_reports.resolved_ids
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.safe_walk_map_report_submit(
  p_request_id uuid,
  p_category text,
  p_latitude double precision,
  p_longitude double precision,
  p_description text DEFAULT ''
) RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
-- Preserve float8 coordinates through JSON even when the caller uses rounded
-- output (extra_float_digits=0). The App checks the saved point exactly.
SET extra_float_digits = 3
AS $body$
DECLARE
  v_report safe_walk_reports.reports%ROWTYPE;
  v_description text;
BEGIN
  IF p_request_id IS NULL OR p_category IS NULL
     OR p_category NOT IN ('fight', 'suspicious', 'lighting', 'construction', 'other')
     OR p_latitude IS NULL OR NOT (p_latitude BETWEEN -90 AND 90)
     OR p_longitude IS NULL OR NOT (p_longitude BETWEEN -180 AND 180)
     OR p_description IS NULL OR length(p_description) > 500 THEN
    RAISE EXCEPTION 'map_report_invalid_argument' USING ERRCODE = '22023';
  END IF;
  v_description := btrim(p_description);

  -- Serialize the short insert/check section: concurrent repeated taps and
  -- retries cannot create duplicate rows or race through the global cap.
  PERFORM pg_catalog.pg_advisory_xact_lock(20261108, 1972);
  IF EXISTS (SELECT 1 FROM safe_walk_reports.resolved_ids r
             WHERE r.id = p_request_id) THEN
    RAISE EXCEPTION 'map_report_already_resolved' USING ERRCODE = '23505';
  END IF;
  SELECT r.* INTO v_report FROM safe_walk_reports.reports r
    WHERE r.id = p_request_id;
  IF FOUND THEN
    IF v_report.category <> p_category OR v_report.latitude <> p_latitude
       OR v_report.longitude <> p_longitude
       OR v_report.description <> v_description THEN
      RAISE EXCEPTION 'map_report_request_conflict' USING ERRCODE = '23505';
    END IF;
  ELSE
    -- Capacity/burst protection only; this is not a verified per-person rate
    -- limit. No spoofable client UUID/IP is treated as an authenticated user.
    IF (SELECT count(*) FROM safe_walk_reports.reports r
        WHERE r.reported_at > clock_timestamp() - interval '1 minute') >= 60
       OR (SELECT count(*) FROM safe_walk_reports.reports) >= 100000 THEN
      RAISE EXCEPTION 'map_report_rate_limited' USING ERRCODE = 'PT429';
    END IF;
    INSERT INTO safe_walk_reports.reports (
      id, category, latitude, longitude, description)
      VALUES (p_request_id, p_category, p_latitude, p_longitude, v_description)
      RETURNING * INTO v_report;
  END IF;
  RETURN jsonb_build_object(
    'interfaceVersion', 1,
    'report', jsonb_build_object(
      'id', v_report.id, 'category', v_report.category,
      'latitude', v_report.latitude, 'longitude', v_report.longitude,
      'description', v_report.description, 'reportedAt', v_report.reported_at));
END;
$body$;

CREATE OR REPLACE FUNCTION public.safe_walk_map_report_resolve(
  p_report_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
SET extra_float_digits = 3
SET lock_timeout = '5s'
AS $body$
DECLARE
  v_removed integer := 0;
BEGIN
  IF p_report_id IS NULL THEN
    RAISE EXCEPTION 'map_report_invalid_argument' USING ERRCODE = '22023';
  END IF;

  -- The same lock as submit prevents a retry from racing with retirement.
  PERFORM pg_catalog.pg_advisory_xact_lock(20261108, 1972);
  IF EXISTS (SELECT 1 FROM safe_walk_reports.reports r
             WHERE r.id = p_report_id) THEN
    -- Capacity/burst protection, not a per-person authorization claim. Missing
    -- and already-removed UUID retries never consume this mutation budget.
    IF (SELECT count(*) FROM safe_walk_reports.resolved_ids r
        WHERE r.resolved_at > clock_timestamp() - interval '1 minute') >= 60
       OR (SELECT count(*) FROM safe_walk_reports.resolved_ids) >= 1000000 THEN
      RAISE EXCEPTION 'map_report_rate_limited' USING ERRCODE = 'PT429';
    END IF;
    DELETE FROM safe_walk_reports.reports WHERE id = p_report_id;
    GET DIAGNOSTICS v_removed = ROW_COUNT;
    IF v_removed = 1 THEN
      INSERT INTO safe_walk_reports.resolved_ids (id) VALUES (p_report_id)
        ON CONFLICT (id) DO NOTHING;
    END IF;
  END IF;
  RETURN jsonb_build_object(
    'interfaceVersion', 1, 'reportId', p_report_id, 'removed', v_removed = 1);
END;
$body$;

ALTER FUNCTION public.safe_walk_map_report_resolve(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.safe_walk_map_report_resolve(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.safe_walk_map_report_resolve(uuid)
  TO anon, authenticated;
COMMENT ON TABLE safe_walk_reports.resolved_ids IS
  'Retired map-report UUIDs only; no coordinates, category, description, user or device data. Prevents delayed submit retries recreating deleted reports.';
NOTIFY pgrst, 'reload schema';
COMMIT;
