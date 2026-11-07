-- MANUAL, READ ONLY. Replace the UUID below with the reviewed imported snapshot.
BEGIN TRANSACTION READ ONLY;
SELECT set_config('crime_reference.verify_snapshot_id','REPLACE_WITH_SNAPSHOT_UUID',true);
DO $verify$
DECLARE sid uuid := current_setting('crime_reference.verify_snapshot_id')::uuid;
        s crime_reference.snapshots%ROWTYPE; actual bigint; t text; r text;
BEGIN
  SELECT * INTO STRICT s FROM crime_reference.snapshots WHERE snapshot_id=sid;
  SELECT count(*) INTO actual FROM crime_reference.records WHERE snapshot_id=sid;
  IF actual <> s.expected_record_count OR actual <> 2542 THEN
    RAISE EXCEPTION 'Record count mismatch: actual %, expected %, delivery 2542',actual,s.expected_record_count;
  END IF;
  SELECT count(*) INTO actual FROM crime_reference.sources WHERE snapshot_id=sid;
  IF actual <> s.expected_source_count OR actual <> 10 THEN
    RAISE EXCEPTION 'Source count mismatch: actual %, expected %, delivery 10',actual,s.expected_source_count;
  END IF;
  IF EXISTS (
    SELECT 1 FROM crime_reference.sources x LEFT JOIN crime_reference.records y
      ON y.snapshot_id=x.snapshot_id AND y.source_key=x.source_key
    WHERE x.snapshot_id=sid GROUP BY x.source_key,x.expected_record_count
    HAVING count(y.source_record_id) <> x.expected_record_count
  ) THEN RAISE EXCEPTION 'Per-source counts differ from reviewed manifest'; END IF;
  IF (SELECT count(*) FROM crime_reference.records WHERE snapshot_id=sid AND city='臺北市') <> 617
     OR (SELECT count(*) FROM crime_reference.records WHERE snapshot_id=sid AND city='新北市') <> 970
     OR (SELECT count(*) FROM crime_reference.records WHERE snapshot_id=sid AND city='基隆市') <> 955 THEN
    RAISE EXCEPTION 'City counts differ from 617 Taipei / 970 New Taipei / 955 Keelung';
  END IF;
  IF EXISTS (SELECT 1 FROM crime_reference.records WHERE snapshot_id=sid AND event_date>s.as_of_date) THEN
    RAISE EXCEPTION 'Future-to-snapshot records detected';
  END IF;
  FOREACH t IN ARRAY ARRAY['snapshots','sources','records'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='crime_reference' AND c.relname=t AND c.relrowsecurity AND c.relforcerowsecurity) THEN
      RAISE EXCEPTION 'RLS/FORCE missing on %',t;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger g WHERE g.tgrelid=format('crime_reference.%I',t)::regclass
      AND g.tgname='deny_update_delete_truncate' AND g.tgenabled='O') THEN
      RAISE EXCEPTION 'Append-only trigger missing/disabled on %',t;
    END IF;
    FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
      IF has_schema_privilege(r,'crime_reference','USAGE')
         OR has_schema_privilege(r,'crime_reference','CREATE')
         OR has_table_privilege(r,format('crime_reference.%I',t),'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') THEN
        RAISE EXCEPTION 'Unexpected application-role privilege for % on %',r,t;
      END IF;
    END LOOP;
  END LOOP;
END;
$verify$;
SELECT snapshot_id,label,as_of_date,expected_record_count,expected_source_count,
       artifact_sha256,manifest_sha256,imported_at
FROM crime_reference.snapshots WHERE snapshot_id=current_setting('crime_reference.verify_snapshot_id')::uuid;
SELECT city,count(*) AS source_records,count(*) FILTER (WHERE latitude IS NULL) AS coordinates_missing,
       count(*) FILTER (WHERE coordinate_status='reference_geocoded') AS reference_geocoded,
       min(event_date) AS first_event,max(event_date) AS last_event
FROM crime_reference.records WHERE snapshot_id=current_setting('crime_reference.verify_snapshot_id')::uuid
GROUP BY city ORDER BY city;
SELECT source_key,count(*) AS source_records FROM crime_reference.records
WHERE snapshot_id=current_setting('crime_reference.verify_snapshot_id')::uuid GROUP BY source_key ORDER BY source_key;
-- This database JSONB fingerprint has its own canonicalization. It is NOT the
-- artifact file SHA256 and must not be claimed equal to it. Save it in the receipt.
SELECT encode(sha256(convert_to(string_agg(record_payload::text,E'\n'
         ORDER BY source_key COLLATE "C",source_record_id COLLATE "C"),'UTF8')),'hex')
       AS database_jsonb_records_sha256
FROM crime_reference.records WHERE snapshot_id=current_setting('crime_reference.verify_snapshot_id')::uuid;
COMMIT;
