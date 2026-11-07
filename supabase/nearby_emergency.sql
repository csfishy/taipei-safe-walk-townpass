-- RETIRED: anonymous nearby-emergency RPCs are not safe to deploy.
-- A caller-supplied UUID is not an authenticated identity or recipient grant.
-- This manual, idempotent containment script only revokes the exact legacy
-- RPC signatures. It does not provision a replacement backend, delete stored
-- data, or touch crime_reference / safe_walk_demo. Never run this from CI,
-- builds, app startup, or demo reset against a real database.
--
-- The app independently refuses all legacy nearby requests, even before this
-- script is applied. Source changes do not establish remote deployment state.
-- See docs/SAFE_WALK_NEARBY_SECURITY.md for the remaining activation blockers.

begin;

do $retire_nearby_rpc$
declare
  legacy_signature text;
  legacy_function regprocedure;
  api_role text;
begin
  foreach legacy_signature in array array[
    'public.set_helper_opt_in(uuid,boolean,double precision,double precision)',
    'public.send_emergency_alert(uuid,double precision,double precision,integer)',
    'public.fetch_pending_alerts(uuid)'
  ] loop
    legacy_function := to_regprocedure(legacy_signature);
    if legacy_function is null then
      continue;
    end if;

    execute format(
      'revoke all privileges on function %s from public', legacy_function
    );
    foreach api_role in array array['anon', 'authenticated', 'service_role'] loop
      if exists (select 1 from pg_roles where rolname = api_role) then
        execute format(
          'revoke all privileges on function %s from %I',
          legacy_function, api_role
        );
      end if;
    end loop;

    -- Fail the transaction if inherited grants still permit an API role to
    -- execute a legacy function. Do not report containment when it is partial.
    foreach api_role in array array['anon', 'authenticated', 'service_role'] loop
      if exists (select 1 from pg_roles where rolname = api_role) then
        if has_function_privilege(api_role, legacy_function, 'EXECUTE') then
          raise exception 'Legacy nearby RPC remains executable by API role %',
            api_role;
        end if;
      end if;
    end loop;
  end loop;
end;
$retire_nearby_rpc$;

commit;
