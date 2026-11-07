-- All IDs, locations, and timestamps are synthetic deterministic fixtures.
-- The public landmark is an artificial example, not a device or user location.
-- These INSERTs do not invoke any notification/RPC or touch Supabase Auth.
INSERT INTO safe_walk_demo.helpers (helper_id, enabled, location, updated_at)
VALUES
  ('11111111-1111-4111-8111-111111111111', true,
    extensions.st_setsrid(extensions.st_makepoint(121.5654, 25.033), 4326)::extensions.geography,
    '2000-01-01T00:00:00Z'),
  ('22222222-2222-4222-8222-222222222222', false, NULL,
    '2000-01-01T00:00:00Z');

INSERT INTO safe_walk_demo.emergency_alerts
  (id, sender_id, location, radius_m, created_at)
VALUES
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    '33333333-3333-4333-8333-333333333333',
    extensions.st_setsrid(extensions.st_makepoint(121.5654, 25.033), 4326)::extensions.geography,
    500, '2000-01-01T00:00:00Z');

INSERT INTO safe_walk_demo.alert_recipients (alert_id, recipient_id, seen)
VALUES
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    '11111111-1111-4111-8111-111111111111', false);
