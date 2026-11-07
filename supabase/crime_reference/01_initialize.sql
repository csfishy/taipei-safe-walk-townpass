-- MANUAL ONLY. Not a Supabase CLI migration, Demo seed, CI job or API setup.
-- New schema only: an existing schema is a hard failure, never an overwrite.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $guard$
BEGIN
  IF current_user <> 'postgres' THEN
    RAISE EXCEPTION 'Manual initialization requires the postgres role';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname='crime_reference') THEN
    RAISE EXCEPTION 'crime_reference already exists; inspect it, do not rerun initialization';
  END IF;
  IF 'crime_reference' = ANY(regexp_split_to_array(
       coalesce(current_setting('pgrst.db_schemas',true),''), '\s*,\s*')) THEN
    RAISE EXCEPTION 'crime_reference must not be an exposed PostgREST schema';
  END IF;
END;
$guard$;

CREATE SCHEMA crime_reference AUTHORIZATION postgres;
COMMENT ON SCHEMA crime_reference IS
  'TownPass private historical crime reference; manual append-only snapshots v1; not App/Demo/API';
REVOKE ALL ON SCHEMA crime_reference FROM PUBLIC, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA crime_reference
  REVOKE ALL ON TABLES FROM PUBLIC, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA crime_reference
  REVOKE ALL ON SEQUENCES FROM PUBLIC, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA crime_reference
  REVOKE ALL ON FUNCTIONS FROM PUBLIC, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA crime_reference
  REVOKE ALL ON TYPES FROM PUBLIC, anon, authenticated, service_role;

CREATE TABLE crime_reference.snapshots (
  snapshot_id uuid PRIMARY KEY,
  label text NOT NULL CHECK (length(btrim(label)) > 0),
  as_of_date date NOT NULL CHECK (as_of_date >= DATE '2026-01-01' AND as_of_date < DATE '2027-01-01'),
  expected_record_count integer NOT NULL CHECK (expected_record_count >= 0),
  expected_source_count integer NOT NULL CHECK (expected_source_count > 0),
  artifact_sha256 text NOT NULL CHECK (artifact_sha256 ~ '^[0-9a-f]{64}$'),
  manifest_sha256 text NOT NULL CHECK (manifest_sha256 ~ '^[0-9a-f]{64}$'),
  imported_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  metadata jsonb NOT NULL CHECK (jsonb_typeof(metadata)='object')
);
CREATE TABLE crime_reference.sources (
  snapshot_id uuid NOT NULL REFERENCES crime_reference.snapshots(snapshot_id),
  source_key text NOT NULL CHECK (length(btrim(source_key)) > 0),
  dataset_id text NOT NULL CHECK (length(btrim(dataset_id)) > 0),
  resource_id text,
  name text NOT NULL CHECK (length(btrim(name)) > 0),
  source_url text NOT NULL CHECK (source_url ~ '^https://'),
  resource_url text NOT NULL CHECK (resource_url ~ '^https://'),
  license text NOT NULL CHECK (length(btrim(license)) > 0),
  retrieved_at timestamptz NOT NULL,
  data_updated_at timestamptz,
  raw_sha256 text NOT NULL CHECK (raw_sha256 ~ '^[0-9a-f]{64}$'),
  original_encoding text NOT NULL,
  expected_record_count integer NOT NULL CHECK (expected_record_count >= 0),
  metadata jsonb NOT NULL CHECK (jsonb_typeof(metadata)='object'),
  PRIMARY KEY (snapshot_id,source_key)
);
CREATE TABLE crime_reference.records (
  snapshot_id uuid NOT NULL,
  source_key text NOT NULL,
  source_record_id text NOT NULL CHECK (length(btrim(source_record_id)) > 0),
  source_row bigint CHECK (source_row > 0),
  event_date date NOT NULL CHECK (event_date >= DATE '2026-01-01' AND event_date < DATE '2027-01-01'),
  city text NOT NULL CHECK (city IN ('臺北市','新北市','基隆市')),
  district text,
  category text NOT NULL CHECK (length(btrim(category)) > 0),
  location_text text NOT NULL CHECK (length(btrim(location_text)) > 0),
  latitude double precision,
  longitude double precision,
  spatial_precision text NOT NULL CHECK (spatial_precision IN (
    'public_place_reference','road_segment_reference','address_range_reference',
    'address_reference','district_only','blurred_text','unresolved')),
  confidence text NOT NULL CHECK (confidence IN ('high','medium','unknown')),
  coordinate_status text NOT NULL CHECK (coordinate_status IN (
    'not_provided','reference_geocoded','source_provided')),
  raw_payload jsonb NOT NULL CHECK (jsonb_typeof(raw_payload)='object'),
  record_payload jsonb NOT NULL CHECK (jsonb_typeof(record_payload)='object'),
  geocoding jsonb NOT NULL CHECK (jsonb_typeof(geocoding)='object'),
  evidence jsonb NOT NULL CHECK (jsonb_typeof(evidence)='object'),
  PRIMARY KEY (snapshot_id,source_key,source_record_id),
  FOREIGN KEY (snapshot_id,source_key) REFERENCES crime_reference.sources(snapshot_id,source_key),
  CONSTRAINT paired_wgs84 CHECK (
    (latitude IS NULL)=(longitude IS NULL)
    AND (latitude IS NULL OR (latitude >= -90 AND latitude <= 90 AND longitude >= -180 AND longitude <= 180))),
  CONSTRAINT precision_coordinates CHECK (
    spatial_precision NOT IN ('district_only','blurred_text','unresolved') OR latitude IS NULL),
  CONSTRAINT coordinate_status_matches CHECK (
    (coordinate_status='not_provided' AND latitude IS NULL)
    OR (coordinate_status IN ('reference_geocoded','source_provided') AND latitude IS NOT NULL)),
  CONSTRAINT unknown_confidence_no_invented_coordinate CHECK (
    confidence <> 'unknown' OR latitude IS NULL OR coordinate_status='source_provided'),
  CONSTRAINT geocoded_requires_evidence CHECK (
    coordinate_status <> 'reference_geocoded' OR (geocoding <> '{}'::jsonb AND evidence <> '{}'::jsonb))
);
COMMENT ON TABLE crime_reference.records IS
  'Historical source records, not deduplicated cases or road-risk scores. Reference coordinates are not precise crime locations.';
CREATE INDEX records_city_date_idx ON crime_reference.records(snapshot_id,city,event_date);
CREATE INDEX records_category_date_idx ON crime_reference.records(snapshot_id,category,event_date);
CREATE INDEX records_coordinates_idx ON crime_reference.records(snapshot_id,latitude,longitude)
  WHERE latitude IS NOT NULL;

CREATE FUNCTION crime_reference.deny_mutation() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $body$
BEGIN
  RAISE EXCEPTION 'crime_reference is append-only; create a new snapshot instead of %', TG_OP
    USING ERRCODE='42501';
END;
$body$;
CREATE FUNCTION crime_reference.validate_record_insert() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $body$
DECLARE cutoff date;
BEGIN
  IF current_user <> 'postgres' THEN
    RAISE EXCEPTION 'Only manual postgres imports are supported' USING ERRCODE='42501';
  END IF;
  SELECT s.as_of_date INTO cutoff FROM crime_reference.snapshots s WHERE s.snapshot_id=NEW.snapshot_id;
  IF cutoff IS NULL OR NEW.event_date > cutoff THEN
    RAISE EXCEPTION 'Record requires an existing snapshot and event_date <= snapshot as_of_date';
  END IF;
  RETURN NEW;
END;
$body$;
CREATE TRIGGER validate_record_insert BEFORE INSERT ON crime_reference.records
  FOR EACH ROW EXECUTE FUNCTION crime_reference.validate_record_insert();
DO $security$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['snapshots','sources','records'] LOOP
    EXECUTE format('ALTER TABLE crime_reference.%I ENABLE ROW LEVEL SECURITY',t);
    EXECUTE format('ALTER TABLE crime_reference.%I FORCE ROW LEVEL SECURITY',t);
    EXECUTE format('CREATE POLICY postgres_manual_read ON crime_reference.%I FOR SELECT TO postgres USING (true)',t);
    EXECUTE format('CREATE POLICY postgres_manual_insert ON crime_reference.%I FOR INSERT TO postgres WITH CHECK (current_user = ''postgres'')',t);
    EXECUTE format('CREATE TRIGGER deny_update_delete_truncate BEFORE UPDATE OR DELETE OR TRUNCATE ON crime_reference.%I FOR EACH STATEMENT EXECUTE FUNCTION crime_reference.deny_mutation()',t);
  END LOOP;
END;
$security$;
-- Explicit revocation is necessary for existing objects, including the normal
-- global PUBLIC EXECUTE default on functions. Per-schema defaults alone cannot
-- cancel a privilege inherited from a global default. Do not alter global defaults.
REVOKE ALL ON ALL TABLES IN SCHEMA crime_reference FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA crime_reference FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA crime_reference FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON SCHEMA crime_reference FROM PUBLIC, anon, authenticated, service_role;
COMMIT;
