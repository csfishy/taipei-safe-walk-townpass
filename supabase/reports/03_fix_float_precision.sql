-- MANUAL ONLY / Level C. Restore lossless JSON output for existing map report
-- RPCs. Changes function-local formatting only: no data, grants, ownership,
-- RLS, signatures, or other schemas are modified.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
DO $guard$
BEGIN
  IF current_user <> 'postgres' THEN
    RAISE EXCEPTION 'Apply the map report precision fix as the postgres role';
  END IF;
  IF to_regprocedure('public.safe_walk_map_report_submit(uuid,text,double precision,double precision,text)') IS NULL
     OR to_regprocedure('public.safe_walk_map_report_query(double precision,double precision,double precision,double precision,integer,integer)') IS NULL THEN
    RAISE EXCEPTION 'Map report RPCs are missing; apply 01_map_report_api.sql first';
  END IF;
END;
$guard$;

-- Setting 3 selects PostgreSQL's shortest precise float8 representation and
-- overrides an API session's extra_float_digits=0 only during each RPC call.
ALTER FUNCTION public.safe_walk_map_report_submit(uuid,text,double precision,double precision,text)
  SET extra_float_digits = 3;
ALTER FUNCTION public.safe_walk_map_report_query(double precision,double precision,double precision,double precision,integer,integer)
  SET extra_float_digits = 3;

NOTIFY pgrst, 'reload schema';
COMMIT;
