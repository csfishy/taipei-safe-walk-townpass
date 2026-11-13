-- MANUAL ONLY, after 03_verify and remote production locked verifier PASS.
-- Public email-label login: anyone knowing a test email can impersonate it.
-- Enabling is separate from installing and requires explicit activation review.
BEGIN;
DO $$ BEGIN
  IF (SELECT count(*) FROM safe_walk_nearby_live_test.control)<>1 THEN
    RAISE EXCEPTION 'Missing test control';
  END IF;
END $$;
UPDATE safe_walk_nearby_live_test.control
  SET enabled_until=now()+interval '48 hours',login_bucket=now(),login_count=0 WHERE id;
DO $$ BEGIN
  IF (SELECT enabled_until FROM safe_walk_nearby_live_test.control WHERE id) IS DISTINCT FROM now()+interval '48 hours' THEN
    RAISE EXCEPTION 'Expected exactly 48-hour deadline';
  END IF;
END $$;
SELECT 'LIVE_TEST_ENABLED_FOR_48_HOURS' AS status,now() AS enabled_at,enabled_until
FROM safe_walk_nearby_live_test.control WHERE id;
COMMIT;
-- To stop early (owner only):
-- UPDATE safe_walk_nearby_live_test.control SET enabled_until=NULL WHERE id;
-- TTL prevents expired data being read; physical cleanup after the window is
-- a separate reviewed owner operation. No cron or email service is configured.
