-- MANUAL READ-ONLY EXAMPLES. Select a reviewed snapshot UUID explicitly.
BEGIN TRANSACTION READ ONLY;
SELECT snapshot_id,label,as_of_date,expected_record_count,artifact_sha256
FROM crime_reference.snapshots ORDER BY imported_at DESC;
-- Cross-source counts are records, not deduplicated cases or comparable crime rates.
SELECT snapshot_id,city,category,count(*) AS source_records,min(event_date),max(event_date)
FROM crime_reference.records GROUP BY snapshot_id,city,category ORDER BY snapshot_id,city,category;
SELECT snapshot_id,spatial_precision,confidence,coordinate_status,count(*) AS source_records
FROM crime_reference.records GROUP BY snapshot_id,spatial_precision,confidence,coordinate_status;
-- Null coordinates remain queryable and are never replaced with district centroids.
SELECT snapshot_id,source_key,source_record_id,event_date,city,district,category,
       location_text,spatial_precision,coordinate_status
FROM crime_reference.records WHERE latitude IS NULL ORDER BY snapshot_id,event_date,source_key LIMIT 100;
-- Inspect provenance of reference coordinates, which are NOT exact crime locations.
SELECT snapshot_id,source_key,source_record_id,location_text,latitude,longitude,
       spatial_precision,confidence,geocoding,evidence
FROM crime_reference.records WHERE coordinate_status='reference_geocoded' LIMIT 100;
COMMIT;
