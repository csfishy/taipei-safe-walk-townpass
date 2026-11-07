-- LOCAL TEST ONLY. Stubs the parts of a Supabase project that
-- 001_nearby_helper.sql expects (roles, extensions schema, auth.users, auth.uid).
-- Never run this against a real Supabase project.
create schema if not exists extensions;
create extension if not exists postgis with schema extensions;
create extension if not exists pgcrypto with schema extensions;

do $roles$
declare r text;
begin
  foreach r in array array['anon', 'authenticated', 'service_role'] loop
    if not exists (select 1 from pg_roles where rolname = r) then
      execute format('create role %I nologin', r);
    end if;
  end loop;
end
$roles$;

create schema if not exists auth;
create table if not exists auth.users (id uuid primary key);

-- Same behaviour as Supabase's auth.uid(): the sub claim of the verified JWT.
create or replace function auth.uid() returns uuid
language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;

grant usage on schema auth, extensions, public to anon, authenticated;
grant execute on function auth.uid() to anon, authenticated;
grant usage on schema extensions to anon, authenticated;
