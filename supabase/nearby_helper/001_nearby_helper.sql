-- Nearby-helper SOS backend (isolated, reviewable, NOT deployed anywhere).
--
-- Design: docs/SAFE_WALK_NEARBY_HELPER_DESIGN.md. Level C: run manually, only
-- against an ISOLATED Supabase project or schema that the team lead has
-- authorized. Never from CI, builds, app startup or Demo reset, and never
-- against the crime_reference project data. This script creates no seed data.
--
-- Identity is always auth.uid() from a verified session. No function accepts a
-- caller-supplied user id. Tables are private (RLS on, no policies, no grants);
-- clients only reach thin SECURITY DEFINER wrappers in public, and those are
-- executable by `authenticated` only.

begin;

create schema if not exists safe_walk_nearby;

-- ---------------------------------------------------------------- tables

create table if not exists safe_walk_nearby.helper_profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  consent_version text not null check (char_length(consent_version) between 1 and 64),
  consented_at timestamptz not null,
  revoked_at timestamptz
);

-- At most one row per helper: the latest position only, never a history.
create table if not exists safe_walk_nearby.helper_locations (
  user_id uuid primary key
    references safe_walk_nearby.helper_profiles (user_id) on delete cascade,
  geog extensions.geography (point, 4326) not null,
  accuracy_m real check (accuracy_m is null or accuracy_m >= 0),
  reported_at timestamptz not null,
  expires_at timestamptz not null
);
create index if not exists helper_locations_geog_idx
  on safe_walk_nearby.helper_locations using gist (geog);
create index if not exists helper_locations_expires_idx
  on safe_walk_nearby.helper_locations (expires_at);

create table if not exists safe_walk_nearby.alerts (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references auth.users (id) on delete cascade,
  client_request_id uuid not null,
  geog extensions.geography (point, 4326) not null,
  radius_m integer not null default 500 check (radius_m = 500),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  unique (sender_id, client_request_id)
);
create index if not exists alerts_sender_created_idx
  on safe_walk_nearby.alerts (sender_id, created_at desc);
create index if not exists alerts_expires_idx
  on safe_walk_nearby.alerts (expires_at);

create table if not exists safe_walk_nearby.alert_deliveries (
  alert_id uuid not null
    references safe_walk_nearby.alerts (id) on delete cascade,
  recipient_id uuid not null
    references safe_walk_nearby.helper_profiles (user_id) on delete cascade,
  delivered_at timestamptz not null default now(),
  seen_at timestamptz,
  primary key (alert_id, recipient_id)
);
create index if not exists alert_deliveries_recipient_idx
  on safe_walk_nearby.alert_deliveries (recipient_id);

alter table safe_walk_nearby.helper_profiles enable row level security;
alter table safe_walk_nearby.helper_locations enable row level security;
alter table safe_walk_nearby.alerts enable row level security;
alter table safe_walk_nearby.alert_deliveries enable row level security;
-- Deliberately no policies: deny by default. Only the SECURITY DEFINER
-- functions below (owned by the migration owner) touch these tables.

revoke all on schema safe_walk_nearby from public;
revoke all on all tables in schema safe_walk_nearby from public;
alter default privileges in schema safe_walk_nearby revoke all on tables from public;

do $revoke_api_roles$
declare
  api_role text;
begin
  foreach api_role in array array['anon', 'authenticated'] loop
    if exists (select 1 from pg_catalog.pg_roles where rolname = api_role) then
      execute format('revoke all on schema safe_walk_nearby from %I', api_role);
      execute format(
        'revoke all on all tables in schema safe_walk_nearby from %I', api_role
      );
    end if;
  end loop;
end
$revoke_api_roles$;

-- ------------------------------------------------------------- functions
-- Error codes map to HTTP through PostgREST: 28000 -> 403, 42501 -> 401/403,
-- 22023 -> 400, PT429 -> 429.

create or replace function public.nearby_helper_opt_in(p_consent_version text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_consent_version is null
     or char_length(p_consent_version) not between 1 and 64 then
    raise exception 'invalid_input' using errcode = '22023';
  end if;
  -- Repeating this call while already joined (the app refreshes a helper's
  -- position this way) keeps the original consent time; a new consent version or
  -- rejoining after opting out records a new one.
  insert into safe_walk_nearby.helper_profiles as hp
    (user_id, consent_version, consented_at, revoked_at)
  values (v_uid, p_consent_version, now(), null)
  on conflict (user_id) do update
    set consented_at = case
          when hp.revoked_at is null
               and hp.consent_version = excluded.consent_version
            then hp.consented_at
          else excluded.consented_at
        end,
        consent_version = excluded.consent_version,
        revoked_at = null;
end;
$$;

-- Withdrawing consent deletes the stored position immediately.
create or replace function public.nearby_helper_opt_out()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  delete from safe_walk_nearby.helper_locations where user_id = v_uid;
  update safe_walk_nearby.helper_profiles
    set revoked_at = now()
    where user_id = v_uid and revoked_at is null;
end;
$$;

create or replace function public.nearby_helper_report_location(
  p_lat double precision,
  p_lng double precision,
  p_accuracy_m real default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_last timestamptz;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_lat is null or p_lng is null
     or p_lat <> p_lat or p_lng <> p_lng
     or p_lat not between -90 and 90 or p_lng not between -180 and 180
     or (p_accuracy_m is not null
         and (p_accuracy_m <> p_accuracy_m or p_accuracy_m < 0
              or p_accuracy_m > 500)) then
    raise exception 'invalid_input' using errcode = '22023';
  end if;
  if not exists (
    select 1 from safe_walk_nearby.helper_profiles
    where user_id = v_uid and revoked_at is null
  ) then
    raise exception 'not_a_helper' using errcode = '42501';
  end if;
  select reported_at into v_last
    from safe_walk_nearby.helper_locations where user_id = v_uid;
  if v_last is not null and v_last > now() - interval '10 seconds' then
    raise exception 'rate_limited' using errcode = 'PT429';
  end if;
  insert into safe_walk_nearby.helper_locations
    (user_id, geog, accuracy_m, reported_at, expires_at)
  values (
    v_uid,
    extensions.st_setsrid(extensions.st_makepoint(p_lng, p_lat), 4326)::extensions.geography,
    p_accuracy_m,
    now(),
    now() + interval '10 minutes'
  )
  on conflict (user_id) do update
    set geog = excluded.geog,
        accuracy_m = excluded.accuracy_m,
        reported_at = excluded.reported_at,
        expires_at = excluded.expires_at;
end;
$$;

-- Returns only the number of helpers notified. It never returns identities or
-- coordinates of other people.
create or replace function public.nearby_sos_send(
  p_lat double precision,
  p_lng double precision,
  p_client_request_id uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_alert_id uuid;
  v_geog extensions.geography;
  v_count integer;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_lat is null or p_lng is null or p_client_request_id is null
     or p_lat <> p_lat or p_lng <> p_lng
     or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    raise exception 'invalid_input' using errcode = '22023';
  end if;

  -- A retry of the same request returns the original result and notifies no one.
  select id into v_alert_id
    from safe_walk_nearby.alerts
    where sender_id = v_uid and client_request_id = p_client_request_id;
  if v_alert_id is not null then
    select count(*)::integer into v_count
      from safe_walk_nearby.alert_deliveries where alert_id = v_alert_id;
    return v_count;
  end if;

  if exists (
    select 1 from safe_walk_nearby.alerts
    where sender_id = v_uid and created_at > now() - interval '15 seconds'
  ) or (
    select count(*) from safe_walk_nearby.alerts
    where sender_id = v_uid and created_at > now() - interval '1 hour'
  ) >= 5 then
    raise exception 'rate_limited' using errcode = 'PT429';
  end if;

  v_geog := extensions.st_setsrid(
    extensions.st_makepoint(p_lng, p_lat), 4326
  )::extensions.geography;

  insert into safe_walk_nearby.alerts
    (sender_id, client_request_id, geog, radius_m, expires_at)
  values (v_uid, p_client_request_id, v_geog, 500, now() + interval '30 minutes')
  on conflict (sender_id, client_request_id) do nothing
  returning id into v_alert_id;
  if v_alert_id is null then
    select id into v_alert_id
      from safe_walk_nearby.alerts
      where sender_id = v_uid and client_request_id = p_client_request_id;
    select count(*)::integer into v_count
      from safe_walk_nearby.alert_deliveries where alert_id = v_alert_id;
    return v_count;
  end if;

  insert into safe_walk_nearby.alert_deliveries (alert_id, recipient_id)
  select v_alert_id, nearest.user_id
  from (
    select hl.user_id
    from safe_walk_nearby.helper_locations hl
    join safe_walk_nearby.helper_profiles hp on hp.user_id = hl.user_id
    where hp.revoked_at is null
      and hl.expires_at > now()
      and hl.user_id <> v_uid
      and extensions.st_dwithin(hl.geog, v_geog, 500)
    order by extensions.st_distance(hl.geog, v_geog)
    limit 50
  ) as nearest;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Alerts addressed to the caller that are still valid. The sender's identity is
-- never returned. Calls may repeat results; clients de-duplicate by alert_id so
-- a crash after fetching cannot lose an SOS.
create or replace function public.nearby_helper_fetch_alerts()
returns table (
  alert_id uuid,
  lat double precision,
  lng double precision,
  radius_m integer,
  created_at timestamptz,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if not exists (
    select 1 from safe_walk_nearby.helper_profiles
    where user_id = v_uid and revoked_at is null
  ) then
    raise exception 'not_a_helper' using errcode = '42501';
  end if;
  return query
  with touched as (
    update safe_walk_nearby.alert_deliveries d
      set seen_at = coalesce(d.seen_at, now())
      from safe_walk_nearby.alerts a
      where d.alert_id = a.id
        and d.recipient_id = v_uid
        and a.expires_at > now()
      returning a.id, a.geog, a.radius_m, a.created_at, a.expires_at
  )
  select t.id,
         extensions.st_y(t.geog::extensions.geometry),
         extensions.st_x(t.geog::extensions.geometry),
         t.radius_m, t.created_at, t.expires_at
  from touched t
  order by t.created_at desc;
end;
$$;

-- Hygiene only: every read already filters on expiry. Not exposed to API roles;
-- schedule it manually (for example with pg_cron) after review.
create or replace function safe_walk_nearby.purge_expired()
returns void
language sql
security definer
set search_path = ''
as $$
  delete from safe_walk_nearby.helper_locations where expires_at <= now();
  delete from safe_walk_nearby.alerts where expires_at <= now() - interval '1 hour';
$$;

-- ---------------------------------------------------------------- grants

do $grants$
declare
  fn regprocedure;
  api_role text;
begin
  foreach fn in array array[
    'public.nearby_helper_opt_in(text)'::regprocedure,
    'public.nearby_helper_opt_out()'::regprocedure,
    'public.nearby_helper_report_location(double precision,double precision,real)'::regprocedure,
    'public.nearby_sos_send(double precision,double precision,uuid)'::regprocedure,
    'public.nearby_helper_fetch_alerts()'::regprocedure,
    'safe_walk_nearby.purge_expired()'::regprocedure
  ] loop
    execute format('revoke all on function %s from public', fn);
    foreach api_role in array array['anon', 'authenticated', 'service_role'] loop
      if exists (select 1 from pg_catalog.pg_roles where rolname = api_role) then
        execute format('revoke all on function %s from %I', fn, api_role);
      end if;
    end loop;
  end loop;

  if exists (select 1 from pg_catalog.pg_roles where rolname = 'authenticated') then
    grant execute on function public.nearby_helper_opt_in(text) to authenticated;
    grant execute on function public.nearby_helper_opt_out() to authenticated;
    grant execute on function
      public.nearby_helper_report_location(double precision, double precision, real)
      to authenticated;
    grant execute on function
      public.nearby_sos_send(double precision, double precision, uuid)
      to authenticated;
    grant execute on function public.nearby_helper_fetch_alerts() to authenticated;
  end if;
end
$grants$;

commit;
