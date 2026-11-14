-- MANUAL ONLY. Deployment prerequisite reviewed against the target's catalog.
-- No jobs are started, no Live window extended, no push enabled here.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog VERSION '1.6.4';
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions VERSION '0.20.4';
DO $check$ BEGIN
  IF (SELECT extversion FROM pg_extension WHERE extname='pg_cron')<>'1.6.4'
     OR (SELECT extversion FROM pg_extension WHERE extname='pg_net')<>'0.20.4'
     OR NOT EXISTS(SELECT 1 FROM pg_extension WHERE extname='supabase_vault') THEN
    RAISE EXCEPTION 'Unexpected scheduler prerequisites';
  END IF;
END $check$;
COMMIT;
