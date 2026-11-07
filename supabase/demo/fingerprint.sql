-- TEST ONLY: synthetic fixture fingerprint. Do not write actual database rows
-- to workflow logs; the integration test compares this result in memory.
SELECT jsonb_build_object(
  'helpers', (SELECT jsonb_agg(jsonb_build_array(helper_id, enabled,
    CASE WHEN location IS NULL THEN NULL ELSE extensions.st_asewkt(location::extensions.geometry) END,
    to_char(updated_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')) ORDER BY helper_id)
    FROM safe_walk_demo.helpers),
  'emergency_alerts', (SELECT jsonb_agg(jsonb_build_array(id, sender_id,
    extensions.st_asewkt(location::extensions.geometry), radius_m,
    to_char(created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')) ORDER BY id)
    FROM safe_walk_demo.emergency_alerts),
  'alert_recipients', (SELECT jsonb_agg(jsonb_build_array(alert_id, recipient_id, seen)
    ORDER BY alert_id, recipient_id) FROM safe_walk_demo.alert_recipients)
);
