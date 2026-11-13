-- LOCAL DISPOSABLE DATABASE ONLY. Artificial rows exercise a nonempty upgrade.
\set ON_ERROR_STOP on
DO $local_only$
BEGIN
 IF current_database() !~ '^nearby_upgrade_[a-f0-9]{12}$' OR host(inet_server_addr()) <> '127.0.0.1' THEN
  RAISE EXCEPTION 'Only a disposable local upgrade-test database is allowed';
 END IF;
END $local_only$;
INSERT INTO auth.users(id) VALUES
 ('eeeeeeee-0000-4000-8000-000000000001'),
 ('eeeeeeee-0000-4000-8000-000000000002');
INSERT INTO safe_walk_nearby.helper_profiles(user_id,consent_version,consented_at)
 SELECT id, 'upgrade.v1', now()-interval '1 hour' FROM auth.users;
INSERT INTO safe_walk_nearby.helper_locations(user_id,geog,accuracy_m,reported_at,expires_at)
 SELECT id, public.st_setsrid(public.st_makepoint(0,0),4326)::public.geography,
 NULL, now()-interval '1 minute', now()+interval '9 minutes' FROM auth.users;
INSERT INTO safe_walk_nearby.alerts(id,sender_id,client_request_id,geog,expires_at)
 VALUES ('eeeeeeee-0000-4000-8000-000000000003','eeeeeeee-0000-4000-8000-000000000001',
 'eeeeeeee-0000-4000-8000-000000000004',
 public.st_setsrid(public.st_makepoint(0,0),4326)::public.geography,now()+interval '30 minutes');
INSERT INTO safe_walk_nearby.alert_deliveries(alert_id,recipient_id,seen_at)
 VALUES ('eeeeeeee-0000-4000-8000-000000000003','eeeeeeee-0000-4000-8000-000000000002',now());

-- Local stand-ins for existing legacy RPCs. Their exact definitions/ACLs must
-- remain unchanged by the migration. They are never called by this test.
CREATE FUNCTION public.set_helper_opt_in(uuid,boolean,double precision,double precision)
 RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path=public,extensions AS $$ SELECT NULL::void $$;
CREATE FUNCTION public.send_emergency_alert(uuid,double precision,double precision,integer)
 RETURNS integer LANGUAGE sql SECURITY DEFINER SET search_path=public,extensions AS $$ SELECT 0 $$;
CREATE FUNCTION public.fetch_pending_alerts(uuid)
 RETURNS TABLE(alert_id uuid,sender_id uuid,lat double precision,lng double precision,
 radius_m integer,created_at timestamptz) LANGUAGE sql SECURITY DEFINER SET search_path=public,extensions
 AS $$ SELECT NULL::uuid,NULL::uuid,NULL::double precision,NULL::double precision,NULL::integer,NULL::timestamptz WHERE false $$;
REVOKE ALL ON FUNCTION public.set_helper_opt_in(uuid,boolean,double precision,double precision),
 public.send_emergency_alert(uuid,double precision,double precision,integer),
 public.fetch_pending_alerts(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_helper_opt_in(uuid,boolean,double precision,double precision),
 public.send_emergency_alert(uuid,double precision,double precision,integer),
 public.fetch_pending_alerts(uuid) TO anon,authenticated;
CREATE SCHEMA nearby_upgrade_sentinel;
CREATE TABLE nearby_upgrade_sentinel.keep(id integer PRIMARY KEY, value text);
INSERT INTO nearby_upgrade_sentinel.keep VALUES (1,'unrelated artificial data');
CREATE TABLE public._nearby_upgrade_snapshot AS
 SELECT 'profiles' AS name, md5(jsonb_agg(to_jsonb(t) ORDER BY user_id)::text) AS digest
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
 AND proname IN ('set_helper_opt_in','send_emergency_alert','fetch_pending_alerts');
