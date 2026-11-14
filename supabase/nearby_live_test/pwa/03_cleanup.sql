-- MANUAL / trusted scheduler only, suggested every minute after deployment approval.
-- Effective access/delivery expiry is immediate in RPCs; this is physical cleanup.
-- No formal nearby / auth / crime-reference objects touched. Never enables anything.
BEGIN;
DELETE FROM safe_walk_nearby_live_test.push_outbox o
WHERE NOT EXISTS(SELECT 1 FROM safe_walk_nearby_live_test.push_devices d
  JOIN safe_walk_nearby_live_test.sessions s ON s.token_hash=d.session_hash
  JOIN safe_walk_nearby_live_test.alerts a ON a.id=o.alert_id
  CROSS JOIN safe_walk_nearby_live_test.control c
  WHERE d.token_hash=o.device_hash AND d.lease_until>now() AND s.expires_at>now()
    AND a.expires_at>now() AND c.enabled_until>now());
UPDATE safe_walk_nearby_live_test.push_devices SET geog=NULL,accuracy_m=NULL,
  observed_at=NULL,reported_at=NULL,lease_until=NULL
WHERE lease_until<=now() OR NOT EXISTS(SELECT 1 FROM safe_walk_nearby_live_test.control WHERE enabled_until>now());
DELETE FROM safe_walk_nearby_live_test.push_devices d
WHERE NOT EXISTS(SELECT 1 FROM safe_walk_nearby_live_test.sessions s
  CROSS JOIN safe_walk_nearby_live_test.control c
  WHERE s.token_hash=d.session_hash AND s.expires_at>now() AND c.enabled_until>now());
COMMIT;
