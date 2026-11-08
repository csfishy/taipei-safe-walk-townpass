-- LOCAL TEST ONLY: assertions for 001_nearby_helper.sql.
-- Run after 00_bootstrap.sql and 001_nearby_helper.sql, as a superuser:
--   psql -v ON_ERROR_STOP=1 -f 10_test_nearby_helper.sql
-- Everything runs in one transaction and is rolled back; all users and
-- coordinates are artificial. A failed assertion aborts with a non-zero exit.
\set ON_ERROR_STOP on
begin;

create function pg_temp.check(p_ok boolean, p_msg text) returns void
language plpgsql as $$
begin
  if p_ok is not true then raise exception 'ASSERTION FAILED: %', p_msg; end if;
end $$;

create function pg_temp.as_user(p_uid uuid) returns void
language plpgsql as $$
begin
  reset role;
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  set local role authenticated;
end $$;

create function pg_temp.as_anon() returns void
language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claims', '', true);
  set local role anon;
end $$;

create function pg_temp.as_authenticated_without_session() returns void
language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claims', '', true);
  set local role authenticated;
end $$;

create function pg_temp.expect_state(p_sql text, p_state text) returns void
language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlstate <> p_state then
      raise exception 'expected SQLSTATE % but got % (%) for: %',
        p_state, sqlstate, sqlerrm, p_sql;
    end if;
    return;
  end;
  raise exception 'expected SQLSTATE % but statement succeeded: %', p_state, p_sql;
end $$;

create temp table pts (
  name text primary key, uid uuid not null, lat double precision, lng double precision
);
grant select on pts to public;

insert into auth.users (id) values
  ('00000000-0000-4000-8000-000000000001'),  -- sender (also a helper)
  ('00000000-0000-4000-8000-000000000002'),  -- near: 499 m
  ('00000000-0000-4000-8000-000000000003'),  -- far: 501 m
  ('00000000-0000-4000-8000-000000000004'),  -- optout
  ('00000000-0000-4000-8000-000000000005'),  -- expired location
  ('00000000-0000-4000-8000-000000000006'),  -- outside: 5 km
  ('00000000-0000-4000-8000-000000000007'),  -- same spot as sender
  ('00000000-0000-4000-8000-000000000008');  -- never opted in

insert into pts (name, uid, lat, lng)
select name, uid,
       extensions.st_y(g::extensions.geometry),
       extensions.st_x(g::extensions.geometry)
from (
  select v.name, v.uid,
         extensions.st_project(
           extensions.st_setsrid(extensions.st_makepoint(121.5654, 25.0330), 4326)::extensions.geography,
           v.dist, v.az) as g
  from (values
    ('sender',  '00000000-0000-4000-8000-000000000001'::uuid, 0.0, 0.0),
    ('near',    '00000000-0000-4000-8000-000000000002'::uuid, 499.0, 0.0),
    ('far',     '00000000-0000-4000-8000-000000000003'::uuid, 501.0, 1.5707963267948966),
    ('optout',  '00000000-0000-4000-8000-000000000004'::uuid, 100.0, 3.141592653589793),
    ('expired', '00000000-0000-4000-8000-000000000005'::uuid, 100.0, 4.71238898038469),
    ('outside', '00000000-0000-4000-8000-000000000006'::uuid, 5000.0, 3.141592653589793),
    ('same',    '00000000-0000-4000-8000-000000000007'::uuid, 0.0, 0.0)
  ) as v(name, uid, dist, az)
) s;

-- The fixtures really sit on the intended side of the 500 m line.
select pg_temp.check(
  (select extensions.st_distance(
     extensions.st_setsrid(extensions.st_makepoint(p.lng, p.lat), 4326)::extensions.geography,
     extensions.st_setsrid(extensions.st_makepoint(121.5654, 25.0330), 4326)::extensions.geography)
   from pts p where p.name = 'near') < 500, 'near fixture is under 500 m');
select pg_temp.check(
  (select extensions.st_distance(
     extensions.st_setsrid(extensions.st_makepoint(p.lng, p.lat), 4326)::extensions.geography,
     extensions.st_setsrid(extensions.st_makepoint(121.5654, 25.0330), 4326)::extensions.geography)
   from pts p where p.name = 'far') > 500, 'far fixture is over 500 m');

-- 1. Privileges and identity ------------------------------------------------
do $t$
declare
  fn text;
  tbl text;
  r text;
begin
  foreach fn in array array[
    'public.nearby_helper_opt_in(text)',
    'public.nearby_helper_opt_out()',
    'public.nearby_helper_report_location(double precision,double precision,real)',
    'public.nearby_sos_send(double precision,double precision,uuid)',
    'public.nearby_helper_fetch_alerts()',
    'public.nearby_helper_set_areas(jsonb)',
    'public.nearby_helper_get_areas()',
    'public.nearby_contact_invite_create(text)',
    'public.nearby_contact_invite_accept(text)',
    'public.nearby_contact_list_mine()',
    'public.nearby_contact_remove(uuid)',
    'public.nearby_contact_following()',
    'public.nearby_contact_unfollow(uuid)'
  ] loop
    perform pg_temp.check(not has_function_privilege('anon', fn, 'EXECUTE'), 'anon cannot execute ' || fn);
    perform pg_temp.check(has_function_privilege('authenticated', fn, 'EXECUTE'), 'authenticated can execute ' || fn);
    perform pg_temp.check(not has_function_privilege('service_role', fn, 'EXECUTE'), 'service_role is not granted ' || fn);
  end loop;
  perform pg_temp.check(
    not has_function_privilege('authenticated', 'safe_walk_nearby.purge_expired()', 'EXECUTE'),
    'authenticated cannot purge');
  foreach r in array array['anon', 'authenticated'] loop
    perform pg_temp.check(not has_schema_privilege(r, 'safe_walk_nearby', 'USAGE'), r || ' has no schema usage');
    foreach tbl in array array['helper_profiles', 'helper_locations', 'alerts', 'alert_deliveries', 'helper_areas', 'contact_invites', 'trusted_contacts', 'contact_invite_attempts'] loop
      perform pg_temp.check(
        not has_table_privilege(r, 'safe_walk_nearby.' || tbl, 'SELECT')
        and not has_table_privilege(r, 'safe_walk_nearby.' || tbl, 'INSERT')
        and not has_table_privilege(r, 'safe_walk_nearby.' || tbl, 'UPDATE')
        and not has_table_privilege(r, 'safe_walk_nearby.' || tbl, 'DELETE'),
        r || ' has no direct access to ' || tbl);
    end loop;
  end loop;
  perform pg_temp.check(
    (select bool_and(relrowsecurity) from pg_class
      where relnamespace = 'safe_walk_nearby'::regnamespace and relkind = 'r'),
    'RLS enabled on every private table');
  perform pg_temp.check(
    not exists (select 1 from pg_policies where schemaname = 'safe_walk_nearby'),
    'no RLS policies exist (deny by default)');
end $t$;

do $t$
begin
  perform pg_temp.as_anon();
  perform pg_temp.expect_state($q$select public.nearby_helper_opt_in('v1')$q$, '42501');
  perform pg_temp.expect_state($q$select public.nearby_sos_send(25.0, 121.5, gen_random_uuid())$q$, '42501');
  perform pg_temp.expect_state($q$select * from public.nearby_helper_fetch_alerts()$q$, '42501');

  perform pg_temp.as_authenticated_without_session();
  perform pg_temp.expect_state($q$select public.nearby_helper_opt_in('v1')$q$, '28000');
  perform pg_temp.expect_state($q$select public.nearby_helper_opt_out()$q$, '28000');
  perform pg_temp.expect_state($q$select public.nearby_helper_report_location(25.0, 121.5, 5)$q$, '28000');
  perform pg_temp.expect_state($q$select public.nearby_sos_send(25.0, 121.5, gen_random_uuid())$q$, '28000');
  perform pg_temp.expect_state($q$select * from public.nearby_helper_fetch_alerts()$q$, '28000');

  perform pg_temp.as_user('00000000-0000-4000-8000-000000000008');
  perform pg_temp.expect_state($q$select * from safe_walk_nearby.helper_locations$q$, '42501');
  perform pg_temp.expect_state($q$select * from safe_walk_nearby.alerts$q$, '42501');
  perform pg_temp.expect_state($q$select safe_walk_nearby.purge_expired()$q$, '42501');
  reset role;
end $t$;

-- 2. Non-helpers and invalid input -----------------------------------------
do $t$
begin
  perform pg_temp.as_user('00000000-0000-4000-8000-000000000008');
  perform pg_temp.expect_state($q$select public.nearby_helper_report_location(25.0, 121.5, 5)$q$, '42501');
  perform pg_temp.expect_state($q$select * from public.nearby_helper_fetch_alerts()$q$, '42501');
  perform pg_temp.expect_state($q$select public.nearby_helper_opt_in('')$q$, '22023');
  perform pg_temp.expect_state($q$select public.nearby_helper_opt_in(repeat('x', 65))$q$, '22023');
  perform public.nearby_helper_opt_in('test.v1');
  perform pg_temp.expect_state($q$select public.nearby_helper_report_location(91, 121.5, 5)$q$, '22023');
  perform pg_temp.expect_state($q$select public.nearby_helper_report_location(25, 181, 5)$q$, '22023');
  perform pg_temp.expect_state($q$select public.nearby_helper_report_location('NaN'::float8, 121.5, 5)$q$, '22023');
  perform pg_temp.expect_state($q$select public.nearby_helper_report_location(25, 121.5, 501)$q$, '22023');
  perform pg_temp.expect_state($q$select public.nearby_helper_report_location(25, 121.5, -1)$q$, '22023');
  perform pg_temp.expect_state($q$select public.nearby_sos_send(91, 121.5, gen_random_uuid())$q$, '22023');
  perform pg_temp.expect_state($q$select public.nearby_sos_send(25, 121.5, null)$q$, '22023');
  -- Undo this user's opt-in so the "never opted in" role stays meaningful.
  perform public.nearby_helper_opt_out();
  reset role;
end $t$;

-- 3. Helpers opt in and report one position each ---------------------------
do $t$
declare
  p record;
begin
  for p in select * from pts where name <> 'optout' order by name loop
    perform pg_temp.as_user(p.uid);
    perform public.nearby_helper_opt_in('test.v1');
    perform public.nearby_helper_report_location(p.lat, p.lng, 10);
  end loop;
  -- optout reports, then withdraws consent: the stored position must vanish.
  select * into p from pts where name = 'optout';
  perform pg_temp.as_user(p.uid);
  perform public.nearby_helper_opt_in('test.v1');
  perform public.nearby_helper_report_location(p.lat, p.lng, 10);
  reset role;
  perform pg_temp.check(
    exists (select 1 from safe_walk_nearby.helper_locations where user_id = p.uid),
    'optout helper had a stored position');
  perform pg_temp.as_user(p.uid);
  perform public.nearby_helper_opt_out();
  reset role;
  perform pg_temp.check(
    not exists (select 1 from safe_walk_nearby.helper_locations where user_id = p.uid),
    'opt-out deletes the position immediately');
  perform pg_temp.check(
    (select revoked_at is not null from safe_walk_nearby.helper_profiles where user_id = p.uid),
    'opt-out records revocation');
  perform pg_temp.as_user(p.uid);
  perform pg_temp.expect_state($q$select public.nearby_helper_report_location(25.0, 121.5, 5)$q$, '42501');
  perform pg_temp.expect_state($q$select * from public.nearby_helper_fetch_alerts()$q$, '42501');
  reset role;

  -- A stale position is never used: expire it as the table owner.
  update safe_walk_nearby.helper_locations
    set expires_at = now() - interval '1 minute'
    where user_id = (select uid from pts where name = 'expired');

  -- Only one row per helper, ever.
  perform pg_temp.check(
    (select count(*) from safe_walk_nearby.helper_locations)
      = (select count(distinct user_id) from safe_walk_nearby.helper_locations),
    'at most one stored position per helper');

  -- Location reports are rate limited.
  select * into p from pts where name = 'sender';
  perform pg_temp.as_user(p.uid);
  perform pg_temp.expect_state(
    format('select public.nearby_helper_report_location(%s, %s, 10)', p.lat, p.lng), 'PT429');
  reset role;
  -- After the minimum interval the same row is replaced, not appended.
  update safe_walk_nearby.helper_locations
    set reported_at = now() - interval '1 minute' where user_id = p.uid;
  perform pg_temp.as_user(p.uid);
  perform public.nearby_helper_report_location(p.lat, p.lng, 10);
  reset role;
  perform pg_temp.check(
    (select count(*) from safe_walk_nearby.helper_locations where user_id = p.uid) = 1,
    'a new report replaces the previous row');
end $t$;

-- Repeating opt-in (a position refresh) keeps the original consent time; rejoining
-- after opting out records a new one.
do $t$
declare
  u uuid := (select uid from pts where name = 'same');
  before_ts timestamptz;
begin
  update safe_walk_nearby.helper_profiles
    set consented_at = now() - interval '1 hour' where user_id = u;
  select consented_at into before_ts from safe_walk_nearby.helper_profiles where user_id = u;
  perform pg_temp.as_user(u);
  perform public.nearby_helper_opt_in('test.v1');
  reset role;
  perform pg_temp.check(
    (select consented_at from safe_walk_nearby.helper_profiles where user_id = u) = before_ts,
    'repeating opt-in keeps the original consent time');
  perform pg_temp.as_user(u);
  perform public.nearby_helper_opt_in('test.v2');
  reset role;
  perform pg_temp.check(
    (select consented_at from safe_walk_nearby.helper_profiles where user_id = u) > before_ts,
    'a new consent version records a new consent time');
end $t$;

-- 4. SOS: only opted-in helpers inside 500 m with a fresh position ---------
do $t$
declare
  s record;
  n integer;
  req uuid := '10000000-0000-4000-8000-000000000001';
  recipients uuid[];
begin
  select * into s from pts where name = 'sender';
  perform pg_temp.as_user(s.uid);
  n := public.nearby_sos_send(s.lat, s.lng, req);
  reset role;
  perform pg_temp.check(n = 2, format('exactly the near and same-spot helpers are notified, got %s', n));
  select array_agg(recipient_id order by recipient_id) into recipients
    from safe_walk_nearby.alert_deliveries;
  perform pg_temp.check(
    recipients = (select array_agg(uid order by uid) from pts where name in ('near', 'same')),
    '499 m and 0 m helpers receive; 501 m, 5 km, expired, opted-out and the sender do not');

  -- Retrying the same request notifies no one again.
  perform pg_temp.as_user(s.uid);
  n := public.nearby_sos_send(s.lat, s.lng, req);
  reset role;
  perform pg_temp.check(n = 2, 'retry returns the original count');
  perform pg_temp.check((select count(*) from safe_walk_nearby.alerts) = 1, 'retry creates no second alert');
  perform pg_temp.check((select count(*) from safe_walk_nearby.alert_deliveries) = 2, 'retry creates no extra deliveries');

  -- A second, different request right away is rate limited.
  perform pg_temp.as_user(s.uid);
  perform pg_temp.expect_state(
    format('select public.nearby_sos_send(%s, %s, %L)', s.lat, s.lng, gen_random_uuid()), 'PT429');
  reset role;
end $t$;

-- 5. Recipients read only their own, valid alerts ---------------------------
do $t$
declare
  p record;
  a record;
  cnt integer;
  nm text;
begin
  select * into p from pts where name = 'near';
  perform pg_temp.as_user(p.uid);
  select count(*) into cnt from public.nearby_helper_fetch_alerts();
  perform pg_temp.check(cnt = 1, 'near helper sees the alert');
  select * into a from public.nearby_helper_fetch_alerts();
  perform pg_temp.check(abs(a.lat - (select lat from pts where name = 'sender')) < 0.00001
                        and abs(a.lng - (select lng from pts where name = 'sender')) < 0.00001,
                        'alert carries the SOS position');
  perform pg_temp.check(a.radius_m = 500, 'alert radius is 500');
  select count(*) into cnt from public.nearby_helper_fetch_alerts();
  perform pg_temp.check(cnt = 1, 'fetch can repeat so a crash cannot lose an SOS');
  reset role;
  perform pg_temp.check(
    (select seen_at is not null from safe_walk_nearby.alert_deliveries where recipient_id = p.uid),
    'first fetch records seen_at');
  perform pg_temp.check(
    pg_get_function_result('public.nearby_helper_fetch_alerts()'::regprocedure) !~* 'sender',
    'fetch result has no sender column');

  foreach nm in array array['far', 'sender', 'expired', 'outside'] loop
    perform pg_temp.as_user((select uid from pts where name = nm));
    select count(*) into cnt from public.nearby_helper_fetch_alerts();
    perform pg_temp.check(cnt = 0, nm || ' sees no alert');
    reset role;
  end loop;

  perform pg_temp.as_user((select uid from pts where name = 'same'));
  select count(*) into cnt from public.nearby_helper_fetch_alerts();
  perform pg_temp.check(cnt = 1, 'same-spot helper sees the alert');
  reset role;

  -- Expired alerts are not returned.
  update safe_walk_nearby.alerts set expires_at = now() - interval '1 second';
  perform pg_temp.as_user((select uid from pts where name = 'near'));
  select count(*) into cnt from public.nearby_helper_fetch_alerts();
  perform pg_temp.check(cnt = 0, 'expired alert is not returned');
  reset role;
end $t$;

-- 6. Sender rate limits -----------------------------------------------------
do $t$
declare
  s record;
  i integer;
begin
  select * into s from pts where name = 'sender';
  -- Alert 1 exists. Add four more with a gap each, then the hourly cap hits.
  for i in 1..4 loop
    update safe_walk_nearby.alerts set created_at = now() - interval '1 minute';
    perform pg_temp.as_user(s.uid);
    perform public.nearby_sos_send(s.lat, s.lng, gen_random_uuid());
    reset role;
  end loop;
  perform pg_temp.check((select count(*) from safe_walk_nearby.alerts) = 5, 'five alerts in the hour');
  update safe_walk_nearby.alerts set created_at = now() - interval '1 minute';
  perform pg_temp.as_user(s.uid);
  perform pg_temp.expect_state(
    format('select public.nearby_sos_send(%s, %s, %L)', s.lat, s.lng, gen_random_uuid()), 'PT429');
  reset role;
end $t$;

-- 6b. Guard areas ----------------------------------------------------------
do $t$
declare
  b record;
  n integer;
  sender uuid := '00000000-0000-4000-8000-000000000008';
  a_in uuid := '00000000-0000-4000-8000-000000000009';   -- area covers the SOS
  a_out uuid := '00000000-0000-4000-8000-00000000000a';  -- area just misses it
  n_in record;
  n_out record;
  got uuid[];
  want uuid[];
  r record;
  base extensions.geography :=
    extensions.st_setsrid(extensions.st_makepoint(121.5654, 25.0330), 4326)::extensions.geography;
begin
  select * into b from pts where name = 'sender';
  insert into auth.users (id) values (a_in), (a_out);

  select extensions.st_y(q.g::extensions.geometry) as lat,
         extensions.st_x(q.g::extensions.geometry) as lng into n_in
    from (select extensions.st_project(base, 900, 0) as g) q;
  select extensions.st_y(q.g::extensions.geometry) as lat,
         extensions.st_x(q.g::extensions.geometry) as lng into n_out
    from (select extensions.st_project(base, 1100, 0) as g) q;

  -- Helpers set areas. a_in's covers the SOS (about 0.9 km away, radius 1 km);
  -- a_out's does not (1.1 km). 'outside' and 'expired' have no usable live
  -- position, 'same' also has one (it must still be notified only once).
  perform pg_temp.as_user(a_in);
  perform public.nearby_helper_opt_in('test.v1');
  perform public.nearby_helper_set_areas(jsonb_build_array(
    jsonb_build_object('lat', n_in.lat, 'lng', n_in.lng, 'radius_m', 1000)));
  perform pg_temp.as_user(a_out);
  perform public.nearby_helper_opt_in('test.v1');
  perform public.nearby_helper_set_areas(jsonb_build_array(
    jsonb_build_object('lat', n_out.lat, 'lng', n_out.lng, 'radius_m', 1000)));
  for r in select * from pts where name in ('outside', 'expired', 'same') loop
    perform pg_temp.as_user(r.uid);
    perform public.nearby_helper_set_areas(jsonb_build_array(
      jsonb_build_object('lat', b.lat, 'lng', b.lng, 'radius_m', 500)));
  end loop;
  -- far (501 m) has an area elsewhere that does not cover the SOS.
  select * into r from pts where name = 'far';
  perform pg_temp.as_user(r.uid);
  perform public.nearby_helper_set_areas(jsonb_build_array(
    jsonb_build_object('lat', b.lat - 0.03, 'lng', b.lng, 'radius_m', 1000)));
  -- A helper who opted out cannot set areas.
  perform pg_temp.as_user((select uid from pts where name = 'optout'));
  perform pg_temp.expect_state($q$select public.nearby_helper_set_areas('[]'::jsonb)$q$, '42501');
  perform pg_temp.expect_state($q$select * from public.nearby_helper_get_areas()$q$, '42501');
  reset role;

  -- Input checks (areas were just written, so move their timestamps back first).
  update safe_walk_nearby.helper_areas set created_at = now() - interval '1 minute';
  perform pg_temp.as_user(a_in);
  perform pg_temp.expect_state($q$select public.nearby_helper_set_areas('{}'::jsonb)$q$, '22023');
  perform pg_temp.expect_state($q$select public.nearby_helper_set_areas(null)$q$, '22023');
  perform pg_temp.expect_state($q$select public.nearby_helper_set_areas('[{"lat":25,"lng":121,"radius_m":499}]')$q$, '22023');
  perform pg_temp.expect_state($q$select public.nearby_helper_set_areas('[{"lat":25,"lng":121,"radius_m":1001}]')$q$, '22023');
  -- 2 km was allowed once; the cap is now 1 km.
  perform pg_temp.expect_state($q$select public.nearby_helper_set_areas('[{"lat":25,"lng":121,"radius_m":2000}]')$q$, '22023');
  perform pg_temp.expect_state($q$select public.nearby_helper_set_areas('[{"lat":25,"lng":121,"radius_m":500.5}]')$q$, '22023');
  perform pg_temp.expect_state($q$select public.nearby_helper_set_areas('[{"lat":91,"lng":121,"radius_m":500}]')$q$, '22023');
  perform pg_temp.expect_state($q$select public.nearby_helper_set_areas('[{"lat":25,"lng":181,"radius_m":500}]')$q$, '22023');
  perform pg_temp.expect_state($q$select public.nearby_helper_set_areas('[{"lat":25,"radius_m":500}]')$q$, '22023');
  perform pg_temp.expect_state($q$select public.nearby_helper_set_areas('[{"lat":"25","lng":121,"radius_m":500}]')$q$, '22023');
  perform pg_temp.expect_state($q$select public.nearby_helper_set_areas('[1]')$q$, '22023');
  perform pg_temp.expect_state(
    $q$select public.nearby_helper_set_areas('[{"lat":25,"lng":121,"radius_m":500},{"lat":25,"lng":121,"radius_m":500},{"lat":25,"lng":121,"radius_m":500},{"lat":25,"lng":121,"radius_m":500}]')$q$,
    '22023');
  reset role;
  perform pg_temp.check(
    (select count(*) from safe_walk_nearby.helper_areas where user_id = a_in) = 1,
    'rejected input leaves the stored areas untouched');

  -- Centres are rounded to 3 decimals by the server; radius is kept.
  perform pg_temp.as_user(a_in);
  perform public.nearby_helper_set_areas(jsonb_build_array(
    jsonb_build_object('lat', 25.03349, 'lng', 121.56551, 'radius_m', 1000)));
  reset role;
  select * into r from safe_walk_nearby.helper_areas where user_id = a_in;
  perform pg_temp.check(
    abs(extensions.st_y(r.center::extensions.geometry) - 25.033) < 1e-6
    and abs(extensions.st_x(r.center::extensions.geometry) - 121.566) < 1e-6
    and r.radius_m = 1000,
    'centre is rounded to about 100 m and the radius is kept');
  -- A second change right away is rate limited; later it replaces, not appends.
  perform pg_temp.as_user(a_in);
  perform pg_temp.expect_state(
    $q$select public.nearby_helper_set_areas('[]'::jsonb)$q$, 'PT429');
  reset role;
  update safe_walk_nearby.helper_areas set created_at = now() - interval '1 minute';
  perform pg_temp.as_user(a_in);
  perform public.nearby_helper_set_areas(jsonb_build_array(
    jsonb_build_object('lat', n_in.lat, 'lng', n_in.lng, 'radius_m', 1000)));
  reset role;
  perform pg_temp.check(
    (select count(*) from safe_walk_nearby.helper_areas where user_id = a_in) = 1,
    'setting areas replaces the previous ones');

  -- Each person reads only their own areas.
  perform pg_temp.as_user(a_out);
  select count(*) into n from public.nearby_helper_get_areas();
  perform pg_temp.check(n = 1, 'a helper reads only their own area');
  reset role;

  -- SOS from a non-helper at the base point.
  perform pg_temp.as_user(sender);
  n := public.nearby_sos_send(b.lat, b.lng, '20000000-0000-4000-8000-000000000001');
  reset role;
  select array_agg(recipient_id order by recipient_id) into got
    from safe_walk_nearby.alert_deliveries d
    join safe_walk_nearby.alerts a on a.id = d.alert_id
    where a.client_request_id = '20000000-0000-4000-8000-000000000001';
  select array_agg(uid order by uid) into want from (
    select uid from pts where name in ('sender', 'near', 'same', 'outside', 'expired')
    union all select a_in
  ) w;
  perform pg_temp.check(n = 6, format('six helpers are notified, got %s', n));
  perform pg_temp.check(got = want,
    'live-position helpers within 500 m and helpers whose guard area covers the SOS are notified; '
    'far, the opted-out helper and the area that just misses are not');
  perform pg_temp.check(
    (select count(*) from safe_walk_nearby.alert_deliveries d
       join safe_walk_nearby.alerts a on a.id = d.alert_id
      where a.client_request_id = '20000000-0000-4000-8000-000000000001'
        and d.recipient_id = (select uid from pts where name = 'same')) = 1,
    'a helper matched by position and by area is notified once');

  -- A helper reached only through a guard area can read the alert.
  perform pg_temp.as_user(a_in);
  select count(*) into n from public.nearby_helper_fetch_alerts();
  perform pg_temp.check(n = 1, 'the guard-area helper sees the alert');
  reset role;
  perform pg_temp.as_user(a_out);
  select count(*) into n from public.nearby_helper_fetch_alerts();
  perform pg_temp.check(n = 0, 'the helper whose area misses sees nothing');
  reset role;

  -- Leaving deletes the guard areas along with the position.
  perform pg_temp.as_user(a_in);
  perform public.nearby_helper_opt_out();
  reset role;
  perform pg_temp.check(
    not exists (select 1 from safe_walk_nearby.helper_areas where user_id = a_in),
    'opting out deletes the guard areas');
  perform pg_temp.as_user(a_in);
  perform pg_temp.expect_state($q$select * from public.nearby_helper_get_areas()$q$, '42501');
  reset role;
end $t$;

-- 6c. Trusted contacts -----------------------------------------------------
do $t$
declare
  owner_u uuid := '00000000-0000-4000-8000-00000000000b';
  c1 uuid := '00000000-0000-4000-8000-00000000000c';
  c2 uuid := '00000000-0000-4000-8000-00000000000d';
  stranger uuid := '00000000-0000-4000-8000-00000000000e';
  helper_u uuid := (select uid from pts where name = 'same');
  code text;
  code2 text;
  res text;
  n integer;
  r record;
  b record;
  link1 uuid;
  extra uuid;
  i integer;
begin
  select * into b from pts where name = 'sender';
  insert into auth.users (id) values (owner_u), (c1), (c2), (stranger);

  -- A code: 8 unambiguous characters, stored only as a hash.
  perform pg_temp.as_user(owner_u);
  perform pg_temp.expect_state($q$select * from public.nearby_contact_invite_create('')$q$, '22023');
  perform pg_temp.expect_state($q$select * from public.nearby_contact_invite_create(repeat('x', 21))$q$, '22023');
  select i2.code into code from public.nearby_contact_invite_create('小明') i2;
  reset role;
  perform pg_temp.check(code ~ '^[A-HJKMNP-Z2-9]{8}$', 'an invite code is 8 unambiguous characters');
  perform pg_temp.check(
    exists (select 1 from safe_walk_nearby.contact_invites
             where owner_id = owner_u
               and code_hash = encode(extensions.digest(code, 'sha256'), 'hex'))
    and not exists (select 1 from safe_walk_nearby.contact_invites where code_hash = code),
    'only a hash of the code is stored');
  -- Creating again right away is rate limited.
  perform pg_temp.as_user(owner_u);
  perform pg_temp.expect_state($q$select * from public.nearby_contact_invite_create('小明')$q$, 'PT429');
  reset role;

  -- A wrong code is refused with a status (and recorded), a right one pairs.
  perform pg_temp.as_user(c1);
  res := public.nearby_contact_invite_accept('ABCDEFGH');
  perform pg_temp.check(res = 'invalid', 'a wrong code is invalid');
  res := public.nearby_contact_invite_accept('');
  perform pg_temp.check(res = 'invalid', 'an empty code is invalid');
  res := public.nearby_contact_invite_accept(lower(substr(code, 1, 4) || ' - ' || substr(code, 5)));
  perform pg_temp.check(res = 'ok', 'case and separators in a code are ignored');
  res := public.nearby_contact_invite_accept(code);
  perform pg_temp.check(res = 'invalid', 'a code works only once');
  reset role;

  -- Your own code does not pair you with yourself and is not consumed.
  update safe_walk_nearby.contact_invites set created_at = now() - interval '1 minute';
  perform pg_temp.as_user(owner_u);
  select i2.code into code2 from public.nearby_contact_invite_create('小明') i2;
  res := public.nearby_contact_invite_accept(code2);
  perform pg_temp.check(res = 'self', 'cannot pair with your own code');
  reset role;
  perform pg_temp.check(
    exists (select 1 from safe_walk_nearby.contact_invites
             where code_hash = encode(extensions.digest(code2, 'sha256'), 'hex')),
    'your own code is not consumed');

  -- An expired code is invalid.
  update safe_walk_nearby.contact_invites set expires_at = now() - interval '1 second';
  perform pg_temp.as_user(c2);
  res := public.nearby_contact_invite_accept(code2);
  perform pg_temp.check(res = 'invalid', 'an expired code is invalid');
  reset role;

  -- Guessing is throttled: ten tries an hour, then a 429. Failed tries count.
  perform pg_temp.as_user(stranger);
  for i in 1..10 loop
    res := public.nearby_contact_invite_accept('ZZZZZZZ' || (2 + i % 8)::text);
    perform pg_temp.check(res = 'invalid', 'wrong guess ' || i);
  end loop;
  perform pg_temp.expect_state($q$select public.nearby_contact_invite_accept('ABCDEFGH')$q$, 'PT429');
  reset role;
  perform pg_temp.check(
    (select count(*) from safe_walk_nearby.contact_invite_attempts where user_id = stranger) = 10,
    'every failed try was recorded');

  -- Each side sees only its own side of the link.
  perform pg_temp.as_user(owner_u);
  select count(*) into n from public.nearby_contact_list_mine();
  perform pg_temp.check(n = 1, 'the owner has one contact');
  select count(*) into n from public.nearby_contact_following();
  perform pg_temp.check(n = 0, 'the owner follows nobody');
  reset role;
  perform pg_temp.as_user(c1);
  select * into r from public.nearby_contact_following();
  perform pg_temp.check(r.display_name = '小明', 'the contact sees the name the owner chose');
  select count(*) into n from public.nearby_contact_list_mine();
  perform pg_temp.check(n = 0, 'the contact has no contacts of their own');
  reset role;
  perform pg_temp.as_user(stranger);
  select count(*) into n from public.nearby_contact_list_mine();
  perform pg_temp.check(n = 0, 'a stranger sees no contacts');
  select count(*) into n from public.nearby_contact_following();
  perform pg_temp.check(n = 0, 'a stranger follows nobody');
  reset role;
  select id into link1 from safe_walk_nearby.trusted_contacts where owner_id = owner_u and contact_id = c1;

  -- Up to five contacts; the sixth is refused, and so is a sixth invite.
  for i in 1..4 loop
    extra := gen_random_uuid();
    insert into auth.users (id) values (extra);
    update safe_walk_nearby.contact_invites set created_at = now() - interval '1 minute';
    perform pg_temp.as_user(owner_u);
    select i2.code into code2 from public.nearby_contact_invite_create('小明') i2;
    reset role;
    perform pg_temp.as_user(extra);
    res := public.nearby_contact_invite_accept(code2);
    reset role;
    perform pg_temp.check(res = 'ok', 'contact ' || (i + 1) || ' pairs');
  end loop;
  extra := gen_random_uuid();
  insert into auth.users (id) values (extra);
  update safe_walk_nearby.contact_invites set created_at = now() - interval '1 minute';
  perform pg_temp.as_user(owner_u);
  perform pg_temp.expect_state($q$select * from public.nearby_contact_invite_create('小明')$q$, 'PT409');
  reset role;
  -- A full owner cannot take a sixth contact even with a valid code.
  insert into safe_walk_nearby.contact_invites (code_hash, owner_id, display_name, expires_at)
  values (encode(extensions.digest('ZYXWVUTS', 'sha256'), 'hex'), owner_u, '小明', now() + interval '1 hour');
  perform pg_temp.as_user(extra);
  res := public.nearby_contact_invite_accept('ZYXWVUTS');
  perform pg_temp.check(res = 'owner_full', 'a sixth contact is refused');
  reset role;

  -- Following is capped at 20.
  for i in 1..20 loop
    extra := gen_random_uuid();
    insert into auth.users (id) values (extra);
    insert into safe_walk_nearby.trusted_contacts (owner_id, contact_id, display_name)
    values (extra, c2, 'x');
  end loop;
  insert into safe_walk_nearby.contact_invites (code_hash, owner_id, display_name, expires_at)
  values (encode(extensions.digest('ZYXWVU22', 'sha256'), 'hex'), stranger, '路人', now() + interval '1 hour');
  perform pg_temp.as_user(c2);
  res := public.nearby_contact_invite_accept('ZYXWVU22');
  perform pg_temp.check(res = 'following_full', 'following more than 20 people is refused');
  reset role;
  delete from safe_walk_nearby.trusted_contacts where contact_id = c2;

  -- SOS reaches the contacts whatever the distance, and tells them who.
  perform pg_temp.as_user(owner_u);
  n := public.nearby_sos_send(b.lat, b.lng, '30000000-0000-4000-8000-000000000001');
  reset role;
  perform pg_temp.check(
    n = (select count(*) from safe_walk_nearby.alert_deliveries d
           join safe_walk_nearby.alerts a on a.id = d.alert_id
          where a.client_request_id = '30000000-0000-4000-8000-000000000001'),
    'the count includes contacts');
  perform pg_temp.check(
    (select count(*) from safe_walk_nearby.alert_deliveries d
       join safe_walk_nearby.alerts a on a.id = d.alert_id
       join safe_walk_nearby.trusted_contacts tc
         on tc.owner_id = a.sender_id and tc.contact_id = d.recipient_id
      where a.client_request_id = '30000000-0000-4000-8000-000000000001') = 5,
    'all five contacts are notified although none shared a position');

  perform pg_temp.as_user(c1);
  select * into r from public.nearby_helper_fetch_alerts();
  perform pg_temp.check(r.from_contact and r.sender_name = '小明',
    'the contact sees it came from their contact, by name');
  perform pg_temp.check(abs(r.lat - b.lat) < 0.00001, 'the contact sees the SOS position');
  reset role;
  -- A helper who is not a contact never learns who sent it.
  perform pg_temp.as_user(helper_u);
  select * into r from public.nearby_helper_fetch_alerts();
  perform pg_temp.check(not r.from_contact and r.sender_name is null,
    'a nearby helper gets no sender name');
  reset role;
  -- Neither a helper nor a contact: nothing.
  perform pg_temp.as_user(stranger);
  perform pg_temp.expect_state($q$select * from public.nearby_helper_fetch_alerts()$q$, '42501');
  reset role;

  -- Removing a contact takes effect at once, and only the right person can.
  perform pg_temp.as_user(stranger);
  perform public.nearby_contact_remove(link1);
  perform public.nearby_contact_unfollow(link1);
  reset role;
  perform pg_temp.as_user(c2);
  perform public.nearby_contact_remove(link1);
  perform public.nearby_contact_unfollow(link1);
  reset role;
  perform pg_temp.check(
    exists (select 1 from safe_walk_nearby.trusted_contacts where id = link1),
    'other people cannot remove or leave someone else''s link');
  perform pg_temp.as_user(owner_u);
  perform public.nearby_contact_remove(link1);
  reset role;
  perform pg_temp.check(
    not exists (select 1 from safe_walk_nearby.trusted_contacts where id = link1),
    'the owner removes a contact');
  perform pg_temp.as_user(c1);
  perform pg_temp.expect_state($q$select * from public.nearby_helper_fetch_alerts()$q$, '42501');
  reset role;

  -- A contact can also leave on their own.
  select id into link1 from safe_walk_nearby.trusted_contacts where owner_id = owner_u limit 1;
  perform pg_temp.as_user((select contact_id from safe_walk_nearby.trusted_contacts where id = link1));
  perform public.nearby_contact_unfollow(link1);
  reset role;
  perform pg_temp.check(
    not exists (select 1 from safe_walk_nearby.trusted_contacts where id = link1),
    'a contact can stop following');

  -- Deleting an account removes its links and invites.
  delete from auth.users where id = owner_u;
  perform pg_temp.check(
    not exists (select 1 from safe_walk_nearby.trusted_contacts where owner_id = owner_u)
    and not exists (select 1 from safe_walk_nearby.contact_invites where owner_id = owner_u),
    'deleting the owner removes their contacts and invites');
end $t$;

-- 7. Retention and account deletion ----------------------------------------
do $t$
declare
  p record;
begin
  update safe_walk_nearby.alerts set expires_at = now() - interval '2 hours';
  perform safe_walk_nearby.purge_expired();
  perform pg_temp.check((select count(*) from safe_walk_nearby.alerts) = 0, 'purge removes old alerts');
  perform pg_temp.check(
    not exists (select 1 from safe_walk_nearby.helper_locations where expires_at <= now()),
    'purge removes expired positions');
  perform pg_temp.check((select count(*) from safe_walk_nearby.alert_deliveries) = 0, 'deliveries cascade with alerts');

  select * into p from pts where name = 'near';
  delete from auth.users where id = p.uid;
  perform pg_temp.check(
    not exists (select 1 from safe_walk_nearby.helper_profiles where user_id = p.uid)
    and not exists (select 1 from safe_walk_nearby.helper_locations where user_id = p.uid)
    and not exists (select 1 from safe_walk_nearby.helper_areas where user_id = p.uid),
    'deleting the account removes the profile, position and guard areas');
end $t$;

select 'ALL NEARBY HELPER SQL TESTS PASSED' as result;
rollback;
