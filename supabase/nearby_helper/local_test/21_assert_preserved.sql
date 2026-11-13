-- LOCAL DISPOSABLE DATABASE ONLY. No real users or positions.
\set ON_ERROR_STOP on
DO $local_only$
BEGIN
 IF current_database() !~ '^nearby_upgrade_[a-f0-9]{12}$' OR host(inet_server_addr()) <> '127.0.0.1' THEN
  RAISE EXCEPTION 'Only a disposable local upgrade-test database is allowed';
 END IF;
END $local_only$;
DO $test$
DECLARE mismatch boolean;
BEGIN
 SELECT EXISTS (
  (SELECT 'profiles' AS name,md5(jsonb_agg(to_jsonb(t) ORDER BY user_id)::text) AS digest
   FROM safe_walk_nearby.helper_profiles t
   UNION ALL SELECT 'locations',md5(jsonb_agg(to_jsonb(t) ORDER BY user_id)::text)
   FROM safe_walk_nearby.helper_locations t
   UNION ALL SELECT 'alerts',md5(jsonb_agg(to_jsonb(t) ORDER BY id)::text)
   FROM safe_walk_nearby.alerts t
   UNION ALL SELECT 'deliveries',md5(jsonb_agg(to_jsonb(t) ORDER BY alert_id,recipient_id)::text)
   FROM safe_walk_nearby.alert_deliveries t
   UNION ALL SELECT 'sentinel',md5(jsonb_agg(to_jsonb(t))::text) FROM nearby_upgrade_sentinel.keep t
   UNION ALL SELECT 'legacy',md5(string_agg(pg_get_functiondef(oid)||coalesce(proacl::text,''),'' ORDER BY proname))
   FROM pg_proc WHERE pronamespace='public'::regnamespace
   AND proname IN ('set_helper_opt_in','send_emergency_alert','fetch_pending_alerts'))
  EXCEPT TABLE public._nearby_upgrade_snapshot) INTO mismatch;
 IF mismatch THEN RAISE EXCEPTION 'Upgrade changed rows or legacy RPCs'; END IF;
 -- A recipient can now be an auth user who has never opted in as a helper.
 INSERT INTO auth.users(id) VALUES ('eeeeeeee-0000-4000-8000-000000000005');
 INSERT INTO safe_walk_nearby.alert_deliveries(alert_id,recipient_id)
 VALUES ('eeeeeeee-0000-4000-8000-000000000003','eeeeeeee-0000-4000-8000-000000000005');
 DELETE FROM auth.users WHERE id='eeeeeeee-0000-4000-8000-000000000005';
 IF EXISTS (SELECT 1 FROM safe_walk_nearby.alert_deliveries
   WHERE recipient_id='eeeeeeee-0000-4000-8000-000000000005') THEN
   RAISE EXCEPTION 'New auth FK did not cascade';
 END IF;
END $test$;
-- Remove only the named artificial fixture users before the behavior suite.
DELETE FROM auth.users WHERE id IN ('eeeeeeee-0000-4000-8000-000000000001',
 'eeeeeeee-0000-4000-8000-000000000002');
SELECT 'Nonempty upgrade preserved rows, unrelated data and legacy RPCs' AS result;
