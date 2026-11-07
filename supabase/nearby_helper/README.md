# Nearby-helper SOS backend (isolated, Level C)

Implements the design in [SAFE_WALK_NEARBY_HELPER_DESIGN.md](../../docs/SAFE_WALK_NEARBY_HELPER_DESIGN.md).
**Nothing here is deployed, wired into the app, or enabled.** Readiness for nearby
notification stays **BLOCKED** until the evidence listed in
[SAFE_WALK_NEARBY_SECURITY.md](../../docs/SAFE_WALK_NEARBY_SECURITY.md) exists and the
team lead authorizes it (Level C).

## What it does

- People who opt in as **helpers** have **one latest position** stored, replaced on
  each report, expiring after 10 minutes, never a history.
- A signed-in user's SOS creates an alert at the SOS position. The server finds
  opted-in helpers inside **500 m** with PostGIS, excluding the sender and anyone whose
  position is missing or expired, and notifies at most the 50 nearest.
- The SOS caller only gets back **how many** helpers were notified. A helper reads the
  alerts addressed to them (position, time, expiry). **Neither side ever receives the
  other's identity**, and no function returns other people's coordinates to a caller
  who is not the recipient.
- Identity is always `auth.uid()` from a verified session. No function accepts a user id.

## Files

| File | Purpose |
|---|---|
| `001_nearby_helper.sql` | Private schema `safe_walk_nearby`, tables with RLS (no policies), and the `public.nearby_*` RPCs, executable by `authenticated` only |
| `local_test/00_bootstrap.sql` | **Local test only.** Stubs Supabase roles, `extensions`, `auth.users` and `auth.uid()` |
| `local_test/10_test_nearby_helper.sql` | **Local test only.** Assertions for privileges, identity, 499 m / 501 m boundary, expiry, opt-out deletion, idempotency, rate limits, retention and cascade deletion |

RPCs: `nearby_helper_opt_in`, `nearby_helper_opt_out`, `nearby_helper_report_location`,
`nearby_sos_send`, `nearby_helper_fetch_alerts`. `safe_walk_nearby.purge_expired()` is
hygiene only (every read already filters on expiry) and is not exposed to API roles.

Limits built in: location reports at most every 10 s; SOS at most one per 15 s and 5 per
hour per sender; SOS is idempotent per `client_request_id`; reported accuracy above
500 m is rejected.

## Run the tests locally

Needs any PostgreSQL with PostGIS. With Docker, using only synthetic data:

```bash
docker run -d --name nearby-pg -e POSTGRES_PASSWORD=test -p 54329:5432 postgis/postgis:16-3.4
PSQL="docker exec -i nearby-pg psql -U postgres -v ON_ERROR_STOP=1"
$PSQL < supabase/nearby_helper/local_test/00_bootstrap.sql
$PSQL < supabase/nearby_helper/001_nearby_helper.sql
$PSQL < supabase/nearby_helper/local_test/10_test_nearby_helper.sql   # prints ALL ... PASSED
docker rm -f nearby-pg
```

The test file runs in one transaction and rolls back.

## Deploying (manual, after authorization)

1. Use an **isolated** Supabase project (or a schema the team lead has authorized).
   Not the `crime_reference` data, not `safe_walk_demo`, never from CI, builds, app
   startup or Demo reset.
2. Apply `001_nearby_helper.sql` manually as the project owner.
3. Schedule `safe_walk_nearby.purge_expired()` (for example every minute with
   `pg_cron`) after review.
4. Verify as real roles: `anon` cannot call any function, one account cannot read
   another's data, opt-out removes the position, rate limits return HTTP 429.

## Client

`AuthenticatedNearbyAlertTransport`
(`lib/features/safe_walk/platform/nearby_emergency/authenticated_nearby_alert_transport.dart`)
calls these RPCs with the user's session token. It needs a `NearbySession`, which only
exists once the team decides where user identity comes from (TownPass login or Supabase
Auth). Until a composition supplies one, the app keeps using the unavailable transport.
