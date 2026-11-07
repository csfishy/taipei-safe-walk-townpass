-- Nearby helper alerts for TownPass Safe Walk (M1).
-- Identities are random anonymous UUIDs, not TownPass accounts.
-- Row-level security is enabled with no direct policies: the anon key can only
-- reach data through the security-definer functions below.

create extension if not exists postgis;

create table if not exists public.helpers (
  helper_id uuid primary key,
  enabled boolean not null default false,
  location geography(point, 4326),
  updated_at timestamptz not null default now()
);

create table if not exists public.emergency_alerts (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null,
  location geography(point, 4326) not null,
  radius_m integer not null check (radius_m between 50 and 3000),
  created_at timestamptz not null default now()
);

create table if not exists public.alert_recipients (
  alert_id uuid not null references public.emergency_alerts(id) on delete cascade,
  recipient_id uuid not null references public.helpers(helper_id) on delete cascade,
  seen boolean not null default false,
  primary key (alert_id, recipient_id)
);

alter table public.helpers enable row level security;
alter table public.emergency_alerts enable row level security;
alter table public.alert_recipients enable row level security;

create or replace function public.set_helper_opt_in(
  p_helper_id uuid,
  p_enabled boolean,
  p_lat double precision default null,
  p_lng double precision default null
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if p_enabled then
    if p_lat is null or p_lng is null
       or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
      raise exception 'valid location required to opt in';
    end if;
    insert into public.helpers (helper_id, enabled, location, updated_at)
    values (p_helper_id, true,
            st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography, now())
    on conflict (helper_id) do update
      set enabled = true, location = excluded.location, updated_at = now();
  else
    -- Opting out removes the stored location immediately.
    insert into public.helpers (helper_id, enabled, location, updated_at)
    values (p_helper_id, false, null, now())
    on conflict (helper_id) do update
      set enabled = false, location = null, updated_at = now();
  end if;
end;
$$;

create or replace function public.send_emergency_alert(
  p_sender_id uuid,
  p_lat double precision,
  p_lng double precision,
  p_radius_m integer
) returns integer
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_point geography;
  v_alert_id uuid;
  v_count integer;
begin
  if p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    raise exception 'invalid coordinates';
  end if;
  if p_radius_m not between 50 and 3000 then
    raise exception 'invalid radius';
  end if;

  v_point := st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography;

  insert into public.emergency_alerts (sender_id, location, radius_m)
  values (p_sender_id, v_point, p_radius_m)
  returning id into v_alert_id;

  insert into public.alert_recipients (alert_id, recipient_id)
  select v_alert_id, h.helper_id
  from public.helpers h
  where h.enabled
    and h.helper_id <> p_sender_id
    and h.location is not null
    and st_dwithin(h.location, v_point, p_radius_m);

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create or replace function public.fetch_pending_alerts(p_helper_id uuid)
returns table (
  alert_id uuid,
  sender_id uuid,
  lat double precision,
  lng double precision,
  radius_m integer,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  return query
  with due as (
    update public.alert_recipients r
    set seen = true
    where r.recipient_id = p_helper_id and not r.seen
    returning r.alert_id
  )
  select a.id, a.sender_id,
         st_y(a.location::geometry), st_x(a.location::geometry),
         a.radius_m, a.created_at
  from due
  join public.emergency_alerts a on a.id = due.alert_id
  order by a.created_at;
end;
$$;

revoke all on function public.set_helper_opt_in(uuid, boolean, double precision, double precision) from public;
revoke all on function public.send_emergency_alert(uuid, double precision, double precision, integer) from public;
revoke all on function public.fetch_pending_alerts(uuid) from public;
grant execute on function public.set_helper_opt_in(uuid, boolean, double precision, double precision) to anon;
grant execute on function public.send_emergency_alert(uuid, double precision, double precision, integer) to anon;
grant execute on function public.fetch_pending_alerts(uuid) to anon;
