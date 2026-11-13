-- MANUAL ONLY. Separate Live-test namespace; does not unlock nearby_* RPCs.
-- An email is an UNVERIFIED test-account label. Anyone knowing it can log in.
-- Install locked. Activation is a separate, time-limited owner operation.
BEGIN;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc WHERE pronamespace='public'::regnamespace
             AND left(proname,7)='swtest_') THEN
    RAISE EXCEPTION 'Live-test RPC namespace already exists';
  END IF;
END $$;
CREATE SCHEMA safe_walk_nearby_live_test;
REVOKE ALL ON SCHEMA safe_walk_nearby_live_test FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE safe_walk_nearby_live_test.control (
  id boolean PRIMARY KEY DEFAULT true CHECK(id),
  enabled_until timestamptz,
  email_salt bytea NOT NULL DEFAULT extensions.gen_random_bytes(32),
  login_bucket timestamptz NOT NULL DEFAULT now(),
  login_count integer NOT NULL DEFAULT 0
);
INSERT INTO safe_walk_nearby_live_test.control(id) VALUES(true);
CREATE TABLE safe_walk_nearby_live_test.accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email_digest bytea NOT NULL UNIQUE,
  helper_enabled boolean NOT NULL DEFAULT false,
  consent_version text,
  consented_at timestamptz,
  send_times timestamptz[] NOT NULL DEFAULT '{}'
);
CREATE TABLE safe_walk_nearby_live_test.sessions (
  token_hash bytea PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES safe_walk_nearby_live_test.accounts ON DELETE CASCADE,
  expires_at timestamptz NOT NULL
);
CREATE INDEX ON safe_walk_nearby_live_test.sessions(account_id);
CREATE TABLE safe_walk_nearby_live_test.locations (
  account_id uuid PRIMARY KEY REFERENCES safe_walk_nearby_live_test.accounts ON DELETE CASCADE,
  geog public.geography(Point,4326) NOT NULL,
  reported_at timestamptz NOT NULL,
  expires_at timestamptz NOT NULL
);
CREATE INDEX ON safe_walk_nearby_live_test.locations USING gist(geog);
CREATE TABLE safe_walk_nearby_live_test.alerts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_id uuid NOT NULL REFERENCES safe_walk_nearby_live_test.accounts ON DELETE CASCADE,
  request_id uuid NOT NULL,
  geog public.geography(Point,4326) NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL DEFAULT now()+interval '30 minutes',
  UNIQUE(sender_id,request_id)
);
CREATE TABLE safe_walk_nearby_live_test.deliveries (
  alert_id uuid NOT NULL REFERENCES safe_walk_nearby_live_test.alerts ON DELETE CASCADE,
  recipient_id uuid NOT NULL REFERENCES safe_walk_nearby_live_test.accounts ON DELETE CASCADE,
  PRIMARY KEY(alert_id,recipient_id)
);
DO $$ DECLARE t text; BEGIN
  FOREACH t IN ARRAY ARRAY['control','accounts','sessions','locations','alerts','deliveries'] LOOP
    EXECUTE format('ALTER TABLE safe_walk_nearby_live_test.%I ENABLE ROW LEVEL SECURITY',t);
  END LOOP;
END $$;
REVOKE ALL ON ALL TABLES IN SCHEMA safe_walk_nearby_live_test FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION safe_walk_nearby_live_test.require_enabled() RETURNS timestamptz
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE deadline timestamptz; BEGIN
  SELECT enabled_until INTO deadline FROM safe_walk_nearby_live_test.control WHERE id;
  IF deadline IS NULL OR deadline<=now() THEN
    RAISE EXCEPTION 'live_test_disabled' USING ERRCODE='42501';
  END IF;
  RETURN deadline;
END $$;
CREATE FUNCTION safe_walk_nearby_live_test.session_user(p_session text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE uid uuid; BEGIN
  PERFORM safe_walk_nearby_live_test.require_enabled();
  IF p_session IS NULL OR p_session !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'invalid_test_session' USING ERRCODE='28000';
  END IF;
  SELECT a.id INTO uid FROM safe_walk_nearby_live_test.sessions s
    JOIN safe_walk_nearby_live_test.accounts a ON a.id=s.account_id
    WHERE s.token_hash=extensions.digest(p_session,'sha256') AND s.expires_at>now()
    FOR UPDATE OF a;
  IF uid IS NULL THEN RAISE EXCEPTION 'invalid_test_session' USING ERRCODE='28000'; END IF;
  RETURN uid;
END $$;

CREATE FUNCTION public.swtest_login(p_email text)
RETURNS TABLE(account_id uuid,test_session text,expires_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE email text:=lower(btrim(p_email)); salt bytea; uid uuid; token text;
  deadline timestamptz; bucket timestamptz; n integer;
BEGIN
  deadline:=safe_walk_nearby_live_test.require_enabled();
  IF email IS NULL OR length(email)>254 OR email !~ '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' THEN
    RAISE EXCEPTION 'invalid_email' USING ERRCODE='22023';
  END IF;
  SELECT email_salt,login_bucket,login_count INTO salt,bucket,n
    FROM safe_walk_nearby_live_test.control WHERE id FOR UPDATE;
  IF bucket<=now()-interval '1 minute' THEN bucket:=now(); n:=0; END IF;
  IF n>=30 THEN RAISE EXCEPTION 'rate_limited' USING ERRCODE='PT429'; END IF;
  UPDATE safe_walk_nearby_live_test.control SET login_bucket=bucket,login_count=n+1 WHERE id;
  DELETE FROM safe_walk_nearby_live_test.locations WHERE locations.expires_at<=now();
  DELETE FROM safe_walk_nearby_live_test.alerts WHERE alerts.expires_at<=now();
  DELETE FROM safe_walk_nearby_live_test.sessions WHERE sessions.expires_at<=now();
  SELECT a.id INTO uid FROM safe_walk_nearby_live_test.accounts a
    WHERE a.email_digest=extensions.hmac(convert_to(email,'UTF8'),salt,'sha256');
  IF uid IS NULL THEN
    IF (SELECT count(*) FROM safe_walk_nearby_live_test.accounts)>=200 THEN
      RAISE EXCEPTION 'test_account_limit' USING ERRCODE='PT429';
    END IF;
    INSERT INTO safe_walk_nearby_live_test.accounts(email_digest)
      VALUES(extensions.hmac(convert_to(email,'UTF8'),salt,'sha256')) RETURNING id INTO uid;
  END IF;
  token:=encode(extensions.gen_random_bytes(32),'hex');
  deadline:=least(deadline,now()+interval '1 hour');
  INSERT INTO safe_walk_nearby_live_test.sessions VALUES(extensions.digest(token,'sha256'),uid,deadline);
  RETURN QUERY SELECT uid,token,deadline;
END $$;
CREATE FUNCTION public.swtest_logout(p_test_session text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE uid uuid; BEGIN
  uid:=safe_walk_nearby_live_test.session_user(p_test_session);
  DELETE FROM safe_walk_nearby_live_test.sessions WHERE token_hash=extensions.digest(p_test_session,'sha256');
  IF NOT EXISTS(SELECT 1 FROM safe_walk_nearby_live_test.sessions WHERE account_id=uid AND expires_at>now()) THEN
    DELETE FROM safe_walk_nearby_live_test.locations WHERE account_id=uid;
  END IF;
END $$;
CREATE FUNCTION public.swtest_opt_in(p_test_session text,p_consent_version text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE uid uuid; BEGIN
  uid:=safe_walk_nearby_live_test.session_user(p_test_session);
  IF p_consent_version IS NULL OR length(p_consent_version) NOT BETWEEN 1 AND 64 THEN
    RAISE EXCEPTION 'invalid_input' USING ERRCODE='22023';
  END IF;
  UPDATE safe_walk_nearby_live_test.accounts SET helper_enabled=true,
    consent_version=p_consent_version,consented_at=now() WHERE id=uid;
END $$;
CREATE FUNCTION public.swtest_opt_out(p_test_session text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE uid uuid; BEGIN
  uid:=safe_walk_nearby_live_test.session_user(p_test_session);
  UPDATE safe_walk_nearby_live_test.accounts SET helper_enabled=false WHERE id=uid;
  DELETE FROM safe_walk_nearby_live_test.locations WHERE account_id=uid;
  DELETE FROM safe_walk_nearby_live_test.deliveries WHERE recipient_id=uid;
END $$;
CREATE FUNCTION public.swtest_report_location(p_test_session text,p_lat double precision,p_lng double precision)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE uid uuid; BEGIN
  uid:=safe_walk_nearby_live_test.session_user(p_test_session);
  IF p_lat IS NULL OR p_lng IS NULL OR p_lat NOT BETWEEN -90 AND 90 OR p_lng NOT BETWEEN -180 AND 180 THEN
    RAISE EXCEPTION 'invalid_input' USING ERRCODE='22023';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM safe_walk_nearby_live_test.accounts WHERE id=uid AND helper_enabled) THEN
    RAISE EXCEPTION 'not_a_helper' USING ERRCODE='42501';
  END IF;
  IF EXISTS(SELECT 1 FROM safe_walk_nearby_live_test.locations WHERE account_id=uid AND reported_at>now()-interval '10 seconds') THEN
    RAISE EXCEPTION 'rate_limited' USING ERRCODE='PT429';
  END IF;
  INSERT INTO safe_walk_nearby_live_test.locations VALUES(uid,
    public.st_setsrid(public.st_makepoint(p_lng,p_lat),4326)::public.geography,now(),now()+interval '10 minutes')
    ON CONFLICT(account_id) DO UPDATE SET geog=excluded.geog,reported_at=excluded.reported_at,expires_at=excluded.expires_at;
END $$;
CREATE FUNCTION public.swtest_send(p_test_session text,p_lat double precision,p_lng double precision,p_request_id uuid)
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
      SELECT aid,l.account_id FROM safe_walk_nearby_live_test.locations l
      JOIN safe_walk_nearby_live_test.accounts a ON a.id=l.account_id
      WHERE a.helper_enabled AND l.account_id<>uid AND l.expires_at>now()
        AND public.st_dwithin(l.geog,pos,500)
      ORDER BY public.st_distance(l.geog,pos) LIMIT 50;
  END IF;
  SELECT count(*)::integer INTO n FROM safe_walk_nearby_live_test.deliveries WHERE alert_id=aid;
  RETURN n;
END $$;
CREATE FUNCTION public.swtest_fetch(p_test_session text)
RETURNS TABLE(alert_id uuid,lat double precision,lng double precision,radius_m integer,created_at timestamptz,expires_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE uid uuid; BEGIN
  uid:=safe_walk_nearby_live_test.session_user(p_test_session);
  IF NOT EXISTS(SELECT 1 FROM safe_walk_nearby_live_test.accounts WHERE id=uid AND helper_enabled) THEN
    RAISE EXCEPTION 'not_a_helper' USING ERRCODE='42501';
  END IF;
  RETURN QUERY SELECT a.id,public.st_y(a.geog::public.geometry),public.st_x(a.geog::public.geometry),500,a.created_at,a.expires_at
    FROM safe_walk_nearby_live_test.deliveries d JOIN safe_walk_nearby_live_test.alerts a ON a.id=d.alert_id
    WHERE d.recipient_id=uid AND a.expires_at>now() ORDER BY a.created_at DESC LIMIT 100;
END $$;
-- Remove automatic grants from every new helper/public wrapper, then allow
-- only the explicit test API. The owner-controlled deadline still denies all
-- business operations until activation. Production functions are untouched.
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA safe_walk_nearby_live_test FROM PUBLIC,anon,authenticated,service_role;
DO $$ DECLARE f regprocedure; BEGIN
  FOR f IN SELECT p.oid::regprocedure FROM pg_proc p WHERE p.pronamespace='public'::regnamespace AND left(p.proname,7)='swtest_' LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',f);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO anon,authenticated',f);
  END LOOP;
END $$;
COMMIT;
