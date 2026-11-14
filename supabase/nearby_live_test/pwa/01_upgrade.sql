-- MANUAL ONLY. v1 must already be installed. Does NOT activate push or extend Live.
BEGIN;
-- Abort on v1 schema/function/ACL drift, within the same transaction.
DO $verify$
DECLARE r record; f record; role_name text; t text; allowed boolean;
BEGIN
  IF (SELECT extversion FROM pg_extension WHERE extname='postgis')<>'3.3.7' THEN
    RAISE EXCEPTION 'Expected PostGIS 3.3.7';
  END IF;
  IF (SELECT count(*) FROM pg_class WHERE relnamespace='safe_walk_nearby_live_test'::regnamespace AND relkind='r')<>6
     OR (SELECT count(*) FROM pg_proc WHERE pronamespace='safe_walk_nearby_live_test'::regnamespace)<>2
     OR (SELECT count(*) FROM pg_proc WHERE pronamespace='public'::regnamespace AND left(proname,7)='swtest_')<>7 THEN
    RAISE EXCEPTION 'Unexpected Live-test objects';
  END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid IN(SELECT oid FROM pg_class WHERE relnamespace='safe_walk_nearby_live_test'::regnamespace)) THEN
    RAISE EXCEPTION 'Unexpected policies';
  END IF;
  FOREACH t IN ARRAY ARRAY['control','accounts','sessions','locations','alerts','deliveries'] LOOP
    IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid=('safe_walk_nearby_live_test.'||t)::regclass
                  AND relrowsecurity AND relowner='postgres'::regrole) THEN
      RAISE EXCEPTION 'Table security mismatch';
    END IF;
    IF EXISTS(SELECT 1 FROM pg_class c CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a
              WHERE c.oid=('safe_walk_nearby_live_test.'||t)::regclass AND a.grantee<>c.relowner) THEN
      RAISE EXCEPTION 'Unexpected table grant';
    END IF;
    FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
      IF has_schema_privilege(role_name,'safe_walk_nearby_live_test','USAGE')
         OR has_table_privilege(role_name,'safe_walk_nearby_live_test.'||t,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') THEN
        RAISE EXCEPTION 'Direct test-data privilege mismatch';
      END IF;
    END LOOP;
  END LOOP;
  FOR r IN SELECT * FROM (VALUES
    ('safe_walk_nearby_live_test.require_enabled()','25c562f5321b6d27626be2abe2debdbf'),
    ('safe_walk_nearby_live_test.session_user(text)','77745397e67ea724b204c8d203186077'),
    ('public.swtest_login(text)','15cc0a58610c8cd344ef83a9ea5983a7'),
    ('public.swtest_logout(text)','aac5766b127f26b9646d47a08aaec37d'),
    ('public.swtest_opt_in(text,text)','a61411f2b38469cff099d03235f2f416'),
    ('public.swtest_opt_out(text)','eedc4fe4a62a94e758b4fcc30c363cfe'),
    ('public.swtest_report_location(text,double precision,double precision)','682e5de8b88b4de47315a5d97341e2eb'),
    ('public.swtest_send(text,double precision,double precision,uuid)','83e86fde358aadbad2717ff65ccc06ac'),
    ('public.swtest_fetch(text)','903a55067919d14a3e20f75bd0f65478')
  ) AS expected(signature,digest) LOOP
    SELECT * INTO f FROM pg_proc WHERE oid=to_regprocedure(r.signature);
    IF NOT FOUND OR NOT f.prosecdef OR f.proowner<>'postgres'::regrole
       OR f.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
       OR md5(replace(f.prosrc,E'\r\n',E'\n'))<>r.digest THEN
      RAISE EXCEPTION 'Function contract mismatch: %',r.signature;
    END IF;
    IF EXISTS(SELECT 1 FROM aclexplode(coalesce(f.proacl,acldefault('f',f.proowner))) WHERE grantee=0 AND privilege_type='EXECUTE') THEN
      RAISE EXCEPTION 'PUBLIC function grant';
    END IF;
    IF EXISTS(SELECT 1 FROM aclexplode(coalesce(f.proacl,acldefault('f',f.proowner))) a
              WHERE a.grantee<>f.proowner AND
                (left(r.signature,14)<>'public.swtest_' OR a.grantee NOT IN('anon'::regrole,'authenticated'::regrole))) THEN
      RAISE EXCEPTION 'Unexpected function grantee';
    END IF;
    FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
      allowed:=left(r.signature,14)='public.swtest_' AND role_name IN('anon','authenticated');
      IF has_function_privilege(role_name,f.oid,'EXECUTE') IS DISTINCT FROM allowed THEN
        RAISE EXCEPTION 'Function ACL mismatch';
      END IF;
    END LOOP;
  END LOOP;
END $verify$;
ALTER TABLE safe_walk_nearby_live_test.control ADD COLUMN push_enabled boolean NOT NULL DEFAULT false;
CREATE TABLE safe_walk_nearby_live_test.push_devices (
  token_hash bytea PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES safe_walk_nearby_live_test.accounts ON DELETE CASCADE,
  session_hash bytea NOT NULL REFERENCES safe_walk_nearby_live_test.sessions ON DELETE CASCADE,
  endpoint text NOT NULL UNIQUE,
  p256dh text NOT NULL,
  auth text NOT NULL,
  geog public.geography(Point,4326),
  accuracy_m double precision,
  observed_at timestamptz,
  reported_at timestamptz,
  lease_until timestamptz,
  started_at timestamptz
);
CREATE INDEX ON safe_walk_nearby_live_test.push_devices USING gist(geog);
CREATE TABLE safe_walk_nearby_live_test.push_outbox (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  alert_id uuid NOT NULL REFERENCES safe_walk_nearby_live_test.alerts ON DELETE CASCADE,
  device_hash bytea NOT NULL REFERENCES safe_walk_nearby_live_test.push_devices ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','leased','accepted','dead','cancelled')),
  attempts integer NOT NULL DEFAULT 0 CHECK(attempts BETWEEN 0 AND 4),
  next_attempt timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  claim_token uuid,
  claimed_until timestamptz,
  UNIQUE(alert_id,device_hash)
);
CREATE INDEX ON safe_walk_nearby_live_test.push_outbox(status,next_attempt);
ALTER TABLE safe_walk_nearby_live_test.push_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE safe_walk_nearby_live_test.push_outbox ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON safe_walk_nearby_live_test.push_devices,safe_walk_nearby_live_test.push_outbox FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION safe_walk_nearby_live_test.device(p_test_session text,p_device_token text) RETURNS bytea
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE uid uuid; h bytea; BEGIN
  uid:=safe_walk_nearby_live_test.session_user(p_test_session);
  IF p_device_token IS NULL OR p_device_token !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'invalid_device' USING ERRCODE='28000';
  END IF;
  h:=extensions.digest(p_device_token,'sha256');
  IF NOT EXISTS(SELECT 1 FROM safe_walk_nearby_live_test.push_devices
    WHERE token_hash=h AND account_id=uid AND session_hash=extensions.digest(p_test_session,'sha256')) THEN
    RAISE EXCEPTION 'invalid_device' USING ERRCODE='28000';
  END IF;
  RETURN h;
END $$;
CREATE FUNCTION safe_walk_nearby_live_test.check_fix(p_lat double precision,p_lng double precision,p_accuracy double precision,p_observed_at timestamptz) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF p_lat IS NULL OR p_lng IS NULL OR p_lat NOT BETWEEN -90 AND 90 OR p_lng NOT BETWEEN -180 AND 180
     OR p_accuracy IS NULL OR p_accuracy NOT BETWEEN 0 AND 30
     OR p_observed_at IS NULL OR p_observed_at<now()-interval '15 seconds' OR p_observed_at>now()+interval '5 seconds' THEN
    RAISE EXCEPTION 'invalid_fix' USING ERRCODE='22023';
  END IF;
END $$;
CREATE FUNCTION public.swtest_receiver_register(p_test_session text,p_device_token text,p_endpoint text,p_p256dh text,p_auth text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE uid uuid; h bytea; BEGIN
  uid:=safe_walk_nearby_live_test.session_user(p_test_session);
  IF p_device_token IS NULL OR p_device_token !~ '^[0-9a-f]{64}$'
    OR p_endpoint IS NULL OR length(p_endpoint)>2048
    OR p_endpoint !~ '^https://([a-z0-9-]+[.])*push[.]apple[.]com/[^?#[:space:]]+$'
       AND p_endpoint !~ '^https://fcm[.]googleapis[.]com/fcm/send/[^?#[:space:]]+$'
       AND p_endpoint !~ '^https://updates[.]push[.]services[.]mozilla[.]com/wpush/v2/[^?#[:space:]]+$'
    OR p_p256dh IS NULL OR p_p256dh !~ '^[A-Za-z0-9_-]{87}={0,1}$'
    OR p_auth IS NULL OR p_auth !~ '^[A-Za-z0-9_-]{22}={0,2}$' THEN
    RAISE EXCEPTION 'invalid_subscription' USING ERRCODE='22023';
  END IF;
  h:=extensions.digest(p_device_token,'sha256');
  IF EXISTS(SELECT 1 FROM safe_walk_nearby_live_test.push_devices WHERE token_hash=h AND account_id<>uid) THEN
    RAISE EXCEPTION 'invalid_device' USING ERRCODE='28000';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM safe_walk_nearby_live_test.push_devices WHERE token_hash=h)
     AND (SELECT count(*) FROM safe_walk_nearby_live_test.push_devices WHERE account_id=uid)>=5 THEN
    RAISE EXCEPTION 'device_limit' USING ERRCODE='PT429';
  END IF;
  INSERT INTO safe_walk_nearby_live_test.push_devices(token_hash,account_id,session_hash,endpoint,p256dh,auth)
    VALUES(h,uid,extensions.digest(p_test_session,'sha256'),p_endpoint,p_p256dh,p_auth)
    ON CONFLICT(token_hash) DO UPDATE SET session_hash=excluded.session_hash,
      endpoint=excluded.endpoint,p256dh=excluded.p256dh,auth=excluded.auth,
      lease_until=least(push_devices.lease_until,(SELECT expires_at FROM safe_walk_nearby_live_test.sessions WHERE token_hash=excluded.session_hash));
END $$;
CREATE FUNCTION public.swtest_receiver_start(p_test_session text,p_device_token text,p_lat double precision,p_lng double precision,p_accuracy double precision,p_observed_at timestamptz) RETURNS timestamptz
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE h bytea; deadline timestamptz; BEGIN
  h:=safe_walk_nearby_live_test.device(p_test_session,p_device_token);
  PERFORM safe_walk_nearby_live_test.check_fix(p_lat,p_lng,p_accuracy,p_observed_at);
  deadline:=least(now()+interval '30 minutes',safe_walk_nearby_live_test.require_enabled(),
    (SELECT expires_at FROM safe_walk_nearby_live_test.sessions WHERE token_hash=extensions.digest(p_test_session,'sha256')));
  UPDATE safe_walk_nearby_live_test.accounts SET helper_enabled=true,consent_version='pwa-receiver-v1',consented_at=now()
    WHERE id=(SELECT account_id FROM safe_walk_nearby_live_test.push_devices WHERE token_hash=h);
  -- Renew starts a new reception period; old queued alerts must not revive.
  UPDATE safe_walk_nearby_live_test.push_outbox SET status='cancelled' WHERE device_hash=h AND status IN('pending','leased');
  UPDATE safe_walk_nearby_live_test.push_devices SET geog=public.st_setsrid(public.st_makepoint(p_lng,p_lat),4326)::public.geography,
    accuracy_m=p_accuracy,observed_at=p_observed_at,reported_at=now(),lease_until=deadline,started_at=now() WHERE token_hash=h;
  RETURN deadline;
END $$;
CREATE FUNCTION public.swtest_receiver_location(p_test_session text,p_device_token text,p_lat double precision,p_lng double precision,p_accuracy double precision,p_observed_at timestamptz) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE h bytea; BEGIN
  h:=safe_walk_nearby_live_test.device(p_test_session,p_device_token);
  PERFORM safe_walk_nearby_live_test.check_fix(p_lat,p_lng,p_accuracy,p_observed_at);
  IF NOT EXISTS(SELECT 1 FROM safe_walk_nearby_live_test.push_devices d JOIN safe_walk_nearby_live_test.accounts a ON a.id=d.account_id
    WHERE d.token_hash=h AND d.lease_until>now() AND a.helper_enabled) THEN
    RAISE EXCEPTION 'receiver_expired' USING ERRCODE='42501';
  END IF;
  IF EXISTS(SELECT 1 FROM safe_walk_nearby_live_test.push_devices WHERE token_hash=h AND reported_at>now()-interval '10 seconds') THEN
    RAISE EXCEPTION 'rate_limited' USING ERRCODE='PT429';
  END IF;
  UPDATE safe_walk_nearby_live_test.push_devices SET geog=public.st_setsrid(public.st_makepoint(p_lng,p_lat),4326)::public.geography,
    accuracy_m=p_accuracy,observed_at=p_observed_at,reported_at=now() WHERE token_hash=h;
END $$;
CREATE FUNCTION public.swtest_receiver_stop(p_test_session text,p_device_token text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE h bytea; BEGIN
  h:=safe_walk_nearby_live_test.device(p_test_session,p_device_token);
  UPDATE safe_walk_nearby_live_test.push_devices SET lease_until=NULL,geog=NULL,accuracy_m=NULL,observed_at=NULL,reported_at=NULL WHERE token_hash=h;
  UPDATE safe_walk_nearby_live_test.push_outbox SET status='cancelled' WHERE device_hash=h AND status IN('pending','leased');
END $$;
CREATE FUNCTION public.swtest_receiver_status(p_test_session text,p_device_token text)
RETURNS TABLE(lease_until timestamptz,reported_at timestamptz,lat double precision,lng double precision,push_enabled boolean,live_until timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE h bytea; BEGIN
  h:=safe_walk_nearby_live_test.device(p_test_session,p_device_token);
  RETURN QUERY SELECT CASE WHEN a.helper_enabled THEN d.lease_until ELSE NULL END,d.reported_at,
    public.st_y(d.geog::public.geometry),public.st_x(d.geog::public.geometry),c.push_enabled,c.enabled_until
    FROM safe_walk_nearby_live_test.push_devices d JOIN safe_walk_nearby_live_test.accounts a ON a.id=d.account_id
    CROSS JOIN safe_walk_nearby_live_test.control c WHERE d.token_hash=h;
END $$;
CREATE FUNCTION public.swtest_receiver_fetch(p_test_session text,p_device_token text)
RETURNS TABLE(alert_id uuid,lat double precision,lng double precision,created_at timestamptz,expires_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE h bytea; BEGIN
  h:=safe_walk_nearby_live_test.device(p_test_session,p_device_token);
  RETURN QUERY SELECT a.id,public.st_y(a.geog::public.geometry),public.st_x(a.geog::public.geometry),a.created_at,a.expires_at
    FROM safe_walk_nearby_live_test.push_outbox o JOIN safe_walk_nearby_live_test.alerts a ON a.id=o.alert_id
    JOIN safe_walk_nearby_live_test.push_devices d ON d.token_hash=o.device_hash
    JOIN safe_walk_nearby_live_test.accounts u ON u.id=d.account_id
    WHERE d.token_hash=h AND d.lease_until>now() AND u.helper_enabled AND a.expires_at>now()
      AND a.created_at>=d.started_at AND o.status<>'cancelled'
    ORDER BY a.created_at DESC LIMIT 100;
END $$;

-- Worker API: service_role ONLY, no direct table grants. Atomic, bounded claims.
CREATE FUNCTION public.swtest_push_claim() RETURNS TABLE(job_id uuid,claim_token uuid,alert_id uuid,endpoint text,p256dh text,auth text,expires_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF NOT EXISTS(SELECT 1 FROM safe_walk_nearby_live_test.control WHERE push_enabled AND enabled_until>now()) THEN RETURN; END IF;
  UPDATE safe_walk_nearby_live_test.push_outbox o SET status='cancelled'
    WHERE status IN('pending','leased') AND (o.expires_at<=now() OR NOT EXISTS(
      SELECT 1 FROM safe_walk_nearby_live_test.push_devices d JOIN safe_walk_nearby_live_test.accounts a ON a.id=d.account_id
      JOIN safe_walk_nearby_live_test.sessions s ON s.token_hash=d.session_hash
      WHERE d.token_hash=o.device_hash AND d.lease_until>now() AND s.expires_at>now() AND a.helper_enabled));
  UPDATE safe_walk_nearby_live_test.push_outbox SET status='dead'
    WHERE status='leased' AND attempts>=4 AND claimed_until<=now();
  RETURN QUERY WITH picked AS (
    SELECT o.id FROM safe_walk_nearby_live_test.push_outbox o
    WHERE o.expires_at>now() AND o.attempts<4 AND ((o.status='pending' AND o.next_attempt<=now()) OR (o.status='leased' AND o.claimed_until<=now()))
    ORDER BY o.next_attempt,o.id LIMIT 20 FOR UPDATE SKIP LOCKED
  ), claimed AS (
    UPDATE safe_walk_nearby_live_test.push_outbox o SET status='leased',attempts=o.attempts+1,
      claim_token=gen_random_uuid(),claimed_until=now()+interval '30 seconds'
      FROM picked p WHERE o.id=p.id RETURNING o.*
  ) SELECT o.id,o.claim_token,o.alert_id,d.endpoint,d.p256dh,d.auth,
      least(o.expires_at,d.lease_until,s.expires_at,c.enabled_until)
    FROM claimed o JOIN safe_walk_nearby_live_test.push_devices d ON d.token_hash=o.device_hash
    JOIN safe_walk_nearby_live_test.sessions s ON s.token_hash=d.session_hash CROSS JOIN safe_walk_nearby_live_test.control c;
END $$;
CREATE FUNCTION public.swtest_push_finish(p_job_id uuid,p_claim_token uuid,p_result text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE h bytea; BEGIN
  IF p_result NOT IN('accepted','retry','gone','dead') OR p_result IS NULL THEN RAISE EXCEPTION 'invalid_result' USING ERRCODE='22023'; END IF;
  UPDATE safe_walk_nearby_live_test.push_outbox SET
    status=CASE WHEN p_result='accepted' THEN 'accepted' WHEN p_result='retry' AND attempts<4 AND expires_at>now() THEN 'pending' ELSE 'dead' END,
    next_attempt=now()+interval '5 seconds'*power(2,attempts),claimed_until=NULL
    WHERE id=p_job_id AND claim_token=p_claim_token AND status='leased' RETURNING device_hash INTO h;
  IF p_result='gone' AND h IS NOT NULL THEN
    UPDATE safe_walk_nearby_live_test.push_devices SET lease_until=NULL,geog=NULL WHERE token_hash=h;
    UPDATE safe_walk_nearby_live_test.push_outbox SET status='cancelled' WHERE device_hash=h AND status IN('pending','leased');
  END IF;
END $$;
-- Existing send / opt-out / logout replacements are appended below.

CREATE OR REPLACE FUNCTION public.swtest_send(p_test_session text,p_lat double precision,p_lng double precision,p_request_id uuid)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE uid uuid; aid uuid; pos public.geography; n integer; recent timestamptz[]; BEGIN
  uid:=safe_walk_nearby_live_test.session_user(p_test_session);
  IF p_lat IS NULL OR p_lng IS NULL OR p_request_id IS NULL OR p_lat NOT BETWEEN -90 AND 90 OR p_lng NOT BETWEEN -180 AND 180 THEN
    RAISE EXCEPTION 'invalid_input' USING ERRCODE='22023';
  END IF;
  SELECT id INTO aid FROM safe_walk_nearby_live_test.alerts WHERE sender_id=uid AND request_id=p_request_id;
  IF aid IS NULL THEN
    SELECT coalesce(array_agg(t),'{}'::timestamptz[]) INTO recent
      FROM safe_walk_nearby_live_test.accounts a,unnest(a.send_times) t WHERE a.id=uid AND t>now()-interval '1 hour';
    IF cardinality(recent)>=5 OR EXISTS(SELECT 1 FROM unnest(recent) t WHERE t>now()-interval '15 seconds') THEN
      RAISE EXCEPTION 'rate_limited' USING ERRCODE='PT429';
    END IF;
    UPDATE safe_walk_nearby_live_test.accounts SET send_times=array_append(recent,now()) WHERE id=uid;
    pos:=public.st_setsrid(public.st_makepoint(p_lng,p_lat),4326)::public.geography;
    INSERT INTO safe_walk_nearby_live_test.alerts(sender_id,request_id,geog) VALUES(uid,p_request_id,pos) RETURNING id INTO aid;
    INSERT INTO safe_walk_nearby_live_test.deliveries
      SELECT aid,nearby.account_id FROM (
        SELECT candidates.account_id,min(candidates.distance) AS distance FROM (
          SELECT l.account_id,public.st_distance(l.geog,pos) AS distance
          FROM safe_walk_nearby_live_test.locations l JOIN safe_walk_nearby_live_test.accounts a ON a.id=l.account_id
          WHERE a.helper_enabled AND l.account_id<>uid AND l.expires_at>now() AND public.st_dwithin(l.geog,pos,500)
          UNION ALL
          SELECT d.account_id,public.st_distance(d.geog,pos) FROM safe_walk_nearby_live_test.push_devices d
          JOIN safe_walk_nearby_live_test.accounts a ON a.id=d.account_id
          JOIN safe_walk_nearby_live_test.sessions s ON s.token_hash=d.session_hash
          WHERE a.helper_enabled AND d.account_id<>uid AND d.lease_until>now() AND s.expires_at>now() AND public.st_dwithin(d.geog,pos,500)
        ) candidates GROUP BY candidates.account_id
      ) nearby ORDER BY nearby.distance,nearby.account_id LIMIT 50;
    INSERT INTO safe_walk_nearby_live_test.push_outbox(alert_id,device_hash,expires_at)
      SELECT aid,d.token_hash,least(now()+interval '60 seconds',d.lease_until,s.expires_at,c.enabled_until)
      FROM safe_walk_nearby_live_test.push_devices d JOIN safe_walk_nearby_live_test.accounts a ON a.id=d.account_id
      JOIN safe_walk_nearby_live_test.sessions s ON s.token_hash=d.session_hash
      JOIN safe_walk_nearby_live_test.deliveries v ON v.recipient_id=d.account_id AND v.alert_id=aid
      CROSS JOIN safe_walk_nearby_live_test.control c
      WHERE a.helper_enabled AND d.account_id<>uid AND d.lease_until>now() AND s.expires_at>now()
        AND public.st_dwithin(d.geog,pos,500);
  END IF;
  SELECT count(*)::integer INTO n FROM safe_walk_nearby_live_test.deliveries WHERE alert_id=aid;
  RETURN n;
END $$;
CREATE OR REPLACE FUNCTION public.swtest_opt_out(p_test_session text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE uid uuid; BEGIN
  uid:=safe_walk_nearby_live_test.session_user(p_test_session);
  UPDATE safe_walk_nearby_live_test.accounts SET helper_enabled=false WHERE id=uid;
  UPDATE safe_walk_nearby_live_test.push_devices SET lease_until=NULL,geog=NULL WHERE account_id=uid;
  UPDATE safe_walk_nearby_live_test.push_outbox SET status='cancelled' WHERE device_hash IN
    (SELECT token_hash FROM safe_walk_nearby_live_test.push_devices WHERE account_id=uid) AND status IN('pending','leased');
  DELETE FROM safe_walk_nearby_live_test.locations WHERE account_id=uid;
  DELETE FROM safe_walk_nearby_live_test.deliveries WHERE recipient_id=uid;
END $$;
CREATE OR REPLACE FUNCTION public.swtest_logout(p_test_session text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE uid uuid; BEGIN
  uid:=safe_walk_nearby_live_test.session_user(p_test_session);
  DELETE FROM safe_walk_nearby_live_test.sessions WHERE token_hash=extensions.digest(p_test_session,'sha256');
  IF NOT EXISTS(SELECT 1 FROM safe_walk_nearby_live_test.sessions WHERE account_id=uid AND expires_at>now()) THEN
    DELETE FROM safe_walk_nearby_live_test.locations WHERE account_id=uid;
  END IF;
END $$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA safe_walk_nearby_live_test FROM PUBLIC,anon,authenticated,service_role;
DO $acl$ DECLARE f regprocedure; worker boolean; BEGIN
  FOR f IN SELECT p.oid::regprocedure FROM pg_proc p WHERE p.pronamespace='public'::regnamespace
    AND (left(p.proname,16)='swtest_receiver_' OR p.proname IN('swtest_push_claim','swtest_push_finish')) LOOP
    worker:=f::text LIKE 'swtest_push_%' OR f::text LIKE 'public.swtest_push_%';
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',f);
    IF worker THEN EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role',f);
    ELSE EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO anon,authenticated',f); END IF;
  END LOOP;
END $acl$;
NOTIFY pgrst,'reload schema';
COMMIT;
