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
    references auth.users (id) on delete cascade,
  delivered_at timestamptz not null default now(),
  seen_at timestamptz,
  primary key (alert_id, recipient_id)
);
create index if not exists alert_deliveries_recipient_idx
  on safe_walk_nearby.alert_deliveries (recipient_id);

-- Guard areas: places a helper asks to be notified about even when their live
-- position is unknown or expired. The centre is stored rounded to 3 decimals
-- (about 100 m), at most 3 per helper. The server cannot verify that a centre is
-- somewhere the helper really is; see docs/SAFE_WALK_NEARBY_HELPER_DESIGN.md.
create table if not exists safe_walk_nearby.helper_areas (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null
    references safe_walk_nearby.helper_profiles (user_id) on delete cascade,
  center extensions.geography (point, 4326) not null,
  radius_m integer not null check (radius_m between 500 and 1000),
  created_at timestamptz not null default now()
);
create index if not exists helper_areas_center_idx
  on safe_walk_nearby.helper_areas using gist (center);
create index if not exists helper_areas_user_idx
  on safe_walk_nearby.helper_areas (user_id);

-- Trusted contacts: people a person has paired with an invite code. When that
-- person sends an SOS, their contacts are notified in the app whatever the
-- distance, and see the name the person chose. The code is only ever stored as a
-- hash. Neither side learns the other's identity beyond that name.
create table if not exists safe_walk_nearby.contact_invites (
  code_hash text primary key,
  owner_id uuid not null references auth.users (id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 20),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null
);
create index if not exists contact_invites_owner_idx
  on safe_walk_nearby.contact_invites (owner_id);

create table if not exists safe_walk_nearby.trusted_contacts (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users (id) on delete cascade,
  contact_id uuid not null references auth.users (id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 20),
  created_at timestamptz not null default now(),
  unique (owner_id, contact_id),
  check (owner_id <> contact_id)
);
create index if not exists trusted_contacts_owner_idx
  on safe_walk_nearby.trusted_contacts (owner_id);
create index if not exists trusted_contacts_contact_idx
  on safe_walk_nearby.trusted_contacts (contact_id);

-- Every attempt to use a code, so guessing can be throttled. (A failed attempt
-- must not raise: the exception would roll the record back.)
create table if not exists safe_walk_nearby.contact_invite_attempts (
  user_id uuid not null references auth.users (id) on delete cascade,
  attempted_at timestamptz not null default now()
);
create index if not exists contact_invite_attempts_idx
  on safe_walk_nearby.contact_invite_attempts (user_id, attempted_at);

alter table safe_walk_nearby.helper_profiles enable row level security;
alter table safe_walk_nearby.helper_locations enable row level security;
alter table safe_walk_nearby.alerts enable row level security;
alter table safe_walk_nearby.alert_deliveries enable row level security;
alter table safe_walk_nearby.helper_areas enable row level security;
alter table safe_walk_nearby.contact_invites enable row level security;
alter table safe_walk_nearby.trusted_contacts enable row level security;
alter table safe_walk_nearby.contact_invite_attempts enable row level security;
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
  delete from safe_walk_nearby.helper_areas where user_id = v_uid;
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

  -- A helper is notified when their fresh live position is within 500 m, or
  -- when one of their guard areas covers the SOS position. Each helper once.
  insert into safe_walk_nearby.alert_deliveries (alert_id, recipient_id)
  select v_alert_id, nearest.user_id
  from (
    select c.user_id, min(c.dist) as dist
    from (
      select hl.user_id,
             extensions.st_distance(hl.geog, v_geog) as dist
      from safe_walk_nearby.helper_locations hl
      join safe_walk_nearby.helper_profiles hp on hp.user_id = hl.user_id
      where hp.revoked_at is null
        and hl.expires_at > now()
        and extensions.st_dwithin(hl.geog, v_geog, 500)
      union all
      select ha.user_id,
             extensions.st_distance(ha.center, v_geog) as dist
      from safe_walk_nearby.helper_areas ha
      join safe_walk_nearby.helper_profiles hp on hp.user_id = ha.user_id
      where hp.revoked_at is null
        and extensions.st_dwithin(ha.center, v_geog, ha.radius_m)
    ) c
    where c.user_id <> v_uid
    group by c.user_id
    order by min(c.dist)
    limit 50
  ) as nearest;

  -- The sender's trusted contacts, whatever the distance. They do not count
  -- against the 50 helper limit (a person has at most 5 contacts).
  insert into safe_walk_nearby.alert_deliveries (alert_id, recipient_id)
  select v_alert_id, tc.contact_id
  from safe_walk_nearby.trusted_contacts tc
  where tc.owner_id = v_uid
  on conflict (alert_id, recipient_id) do nothing;

  select count(*)::integer into v_count
    from safe_walk_nearby.alert_deliveries where alert_id = v_alert_id;
  return v_count;
end;
$$;

-- Alerts addressed to the caller that are still valid, for an active helper or a
-- trusted contact. A helper never learns who sent one. A trusted contact sees the
-- name the sender chose for them (from_contact, sender_name). Calls may repeat
-- results; clients de-duplicate by alert_id so a crash after fetching cannot lose
-- an SOS.
create or replace function public.nearby_helper_fetch_alerts()
returns table (
  alert_id uuid,
  lat double precision,
  lng double precision,
  radius_m integer,
  created_at timestamptz,
  expires_at timestamptz,
  from_contact boolean,
  sender_name text
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
     )
     and not exists (
       select 1 from safe_walk_nearby.trusted_contacts
       where contact_id = v_uid
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
      returning a.id, a.geog, a.radius_m, a.created_at, a.expires_at, a.sender_id
  )
  select t.id,
         extensions.st_y(t.geog::extensions.geometry),
         extensions.st_x(t.geog::extensions.geometry),
         t.radius_m, t.created_at, t.expires_at,
         tc.id is not null,
         tc.display_name
  from touched t
  left join safe_walk_nearby.trusted_contacts tc
    on tc.owner_id = t.sender_id and tc.contact_id = v_uid
  order by t.created_at desc;
end;
$$;

-- Replaces the caller's guard areas (at most 3). Centres are rounded to about
-- 100 m here, whatever the client sent.
create or replace function public.nearby_helper_set_areas(p_areas jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_item jsonb;
  v_lat numeric;
  v_lng numeric;
  v_radius numeric;
  v_last timestamptz;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_areas is null or jsonb_typeof(p_areas) <> 'array'
     or jsonb_array_length(p_areas) > 3 then
    raise exception 'invalid_input' using errcode = '22023';
  end if;
  if not exists (
    select 1 from safe_walk_nearby.helper_profiles
    where user_id = v_uid and revoked_at is null
  ) then
    raise exception 'not_a_helper' using errcode = '42501';
  end if;
  select max(created_at) into v_last
    from safe_walk_nearby.helper_areas where user_id = v_uid;
  if v_last is not null and v_last > now() - interval '10 seconds' then
    raise exception 'rate_limited' using errcode = 'PT429';
  end if;

  -- Validate everything before changing anything.
  for v_item in select value from jsonb_array_elements(p_areas) loop
    if jsonb_typeof(v_item) <> 'object'
       or jsonb_typeof(v_item -> 'lat') is distinct from 'number'
       or jsonb_typeof(v_item -> 'lng') is distinct from 'number'
       or jsonb_typeof(v_item -> 'radius_m') is distinct from 'number' then
      raise exception 'invalid_input' using errcode = '22023';
    end if;
    v_lat := (v_item ->> 'lat')::numeric;
    v_lng := (v_item ->> 'lng')::numeric;
    v_radius := (v_item ->> 'radius_m')::numeric;
    if v_lat not between -90 and 90 or v_lng not between -180 and 180
       or v_radius <> trunc(v_radius) or v_radius not between 500 and 1000 then
      raise exception 'invalid_input' using errcode = '22023';
    end if;
  end loop;

  delete from safe_walk_nearby.helper_areas where user_id = v_uid;
  insert into safe_walk_nearby.helper_areas (user_id, center, radius_m)
  select v_uid,
         extensions.st_setsrid(
           extensions.st_makepoint(
             round((e ->> 'lng')::numeric, 3)::double precision,
             round((e ->> 'lat')::numeric, 3)::double precision),
           4326)::extensions.geography,
         (e ->> 'radius_m')::integer
  from jsonb_array_elements(p_areas) as e;
end;
$$;

-- The caller's own guard areas, as stored (already rounded).
create or replace function public.nearby_helper_get_areas()
returns table (lat double precision, lng double precision, radius_m integer)
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
  select extensions.st_y(ha.center::extensions.geometry),
         extensions.st_x(ha.center::extensions.geometry),
         ha.radius_m
  from safe_walk_nearby.helper_areas ha
  where ha.user_id = v_uid
  order by ha.created_at, ha.id;
end;
$$;

-- Creates a one-time invite code (24 h) for pairing a trusted contact. The code
-- is returned once and stored only as a hash. [p_display_name] is how this
-- person will appear to the contact.
create or replace function public.nearby_contact_invite_create(p_display_name text)
returns table (code text, expires_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid uuid := auth.uid();
  v_name text;
  v_code text := '';
  v_expires timestamptz := now() + interval '24 hours';
  v_last timestamptz;
  i integer;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  v_name := btrim(coalesce(p_display_name, ''));
  if char_length(v_name) not between 1 and 20 then
    raise exception 'invalid_input' using errcode = '22023';
  end if;
  delete from safe_walk_nearby.contact_invites ci
    where ci.owner_id = v_uid and ci.expires_at <= now();
  select max(ci.created_at) into v_last
    from safe_walk_nearby.contact_invites ci where ci.owner_id = v_uid;
  if v_last is not null and v_last > now() - interval '5 seconds' then
    raise exception 'rate_limited' using errcode = 'PT429';
  end if;
  if (select count(*) from safe_walk_nearby.contact_invites ci
        where ci.owner_id = v_uid) >= 3 then
    raise exception 'too_many_invites' using errcode = 'PT429';
  end if;
  if (select count(*) from safe_walk_nearby.trusted_contacts tc
        where tc.owner_id = v_uid) >= 5 then
    raise exception 'contact_limit' using errcode = 'PT409';
  end if;
  -- 8 characters from 31 unambiguous ones (no I, L, O, 0, 1).
  for i in 1..8 loop
    v_code := v_code || substr(
      'ABCDEFGHJKMNPQRSTUVWXYZ23456789',
      (get_byte(extensions.gen_random_bytes(1), 0) % 31) + 1, 1);
  end loop;
  insert into safe_walk_nearby.contact_invites
    (code_hash, owner_id, display_name, expires_at)
  values (encode(extensions.digest(v_code, 'sha256'), 'hex'),
          v_uid, v_name, v_expires);
  return query select v_code, v_expires;
end;
$$;

-- Uses a code to become someone's trusted contact. Returns a status instead of
-- raising on a bad code, so every attempt stays recorded and guessing is
-- throttled (10 attempts an hour): 'ok', 'invalid' (wrong, expired or already
-- used), 'self', 'owner_full' (they already have 5 contacts) or 'following_full'
-- (this person already follows 20).
create or replace function public.nearby_contact_invite_accept(p_code text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_code text;
  v_hash text;
  v_invite record;
  v_paired boolean;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if (select count(*) from safe_walk_nearby.contact_invite_attempts a
        where a.user_id = v_uid
          and a.attempted_at > now() - interval '1 hour') >= 10 then
    raise exception 'rate_limited' using errcode = 'PT429';
  end if;
  insert into safe_walk_nearby.contact_invite_attempts (user_id) values (v_uid);

  v_code := upper(regexp_replace(coalesce(p_code, ''), '[\s-]', '', 'g'));
  if v_code !~ '^[A-HJKMNP-Z2-9]{8}$' then
    return 'invalid';
  end if;
  v_hash := encode(extensions.digest(v_code, 'sha256'), 'hex');
  select * into v_invite from safe_walk_nearby.contact_invites ci
    where ci.code_hash = v_hash and ci.expires_at > now();
  if not found then
    return 'invalid';
  end if;
  if v_invite.owner_id = v_uid then
    return 'self';
  end if;
  v_paired := exists (
    select 1 from safe_walk_nearby.trusted_contacts tc
    where tc.owner_id = v_invite.owner_id and tc.contact_id = v_uid);
  if not v_paired
     and (select count(*) from safe_walk_nearby.trusted_contacts tc
            where tc.owner_id = v_invite.owner_id) >= 5 then
    return 'owner_full';
  end if;
  if not v_paired
     and (select count(*) from safe_walk_nearby.trusted_contacts tc
            where tc.contact_id = v_uid) >= 20 then
    return 'following_full';
  end if;
  insert into safe_walk_nearby.trusted_contacts (owner_id, contact_id, display_name)
  values (v_invite.owner_id, v_uid, v_invite.display_name)
  on conflict (owner_id, contact_id) do update
    set display_name = excluded.display_name;
  delete from safe_walk_nearby.contact_invites ci where ci.code_hash = v_hash;
  return 'ok';
end;
$$;

-- The caller's own trusted contacts: only link ids and dates, never who they are.
create or replace function public.nearby_contact_list_mine()
returns table (link_id uuid, since timestamptz)
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
  return query
  select tc.id, tc.created_at
  from safe_walk_nearby.trusted_contacts tc
  where tc.owner_id = v_uid
  order by tc.created_at, tc.id;
end;
$$;

-- Removes one of the caller's own contacts. Someone else's link is untouched.
create or replace function public.nearby_contact_remove(p_link_id uuid)
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
  delete from safe_walk_nearby.trusted_contacts tc
    where tc.id = p_link_id and tc.owner_id = v_uid;
end;
$$;

-- The people the caller is a trusted contact of, by the name they chose.
create or replace function public.nearby_contact_following()
returns table (link_id uuid, display_name text, since timestamptz)
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
  return query
  select tc.id, tc.display_name, tc.created_at
  from safe_walk_nearby.trusted_contacts tc
  where tc.contact_id = v_uid
  order by tc.created_at, tc.id;
end;
$$;

-- The caller stops being someone's trusted contact.
create or replace function public.nearby_contact_unfollow(p_link_id uuid)
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
  delete from safe_walk_nearby.trusted_contacts tc
    where tc.id = p_link_id and tc.contact_id = v_uid;
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
  delete from safe_walk_nearby.contact_invites where expires_at <= now();
  delete from safe_walk_nearby.contact_invite_attempts
    where attempted_at <= now() - interval '1 day';
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
    'public.nearby_helper_set_areas(jsonb)'::regprocedure,
    'public.nearby_helper_get_areas()'::regprocedure,
    'public.nearby_contact_invite_create(text)'::regprocedure,
    'public.nearby_contact_invite_accept(text)'::regprocedure,
    'public.nearby_contact_list_mine()'::regprocedure,
    'public.nearby_contact_remove(uuid)'::regprocedure,
    'public.nearby_contact_following()'::regprocedure,
    'public.nearby_contact_unfollow(uuid)'::regprocedure,
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
    grant execute on function public.nearby_helper_set_areas(jsonb) to authenticated;
    grant execute on function public.nearby_helper_get_areas() to authenticated;
    grant execute on function public.nearby_contact_invite_create(text) to authenticated;
    grant execute on function public.nearby_contact_invite_accept(text) to authenticated;
    grant execute on function public.nearby_contact_list_mine() to authenticated;
    grant execute on function public.nearby_contact_remove(uuid) to authenticated;
    grant execute on function public.nearby_contact_following() to authenticated;
    grant execute on function public.nearby_contact_unfollow(uuid) to authenticated;
  end if;
end
$grants$;

commit;
