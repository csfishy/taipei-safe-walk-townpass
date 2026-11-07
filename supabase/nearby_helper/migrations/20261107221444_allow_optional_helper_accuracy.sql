-- Manual schema adjustment to the two Markdown specifications at 2661d02.
-- Generated with Supabase CLI migration new; kept outside auto-run migrations.
-- Changes no rows, API grants, policies, functions or other schemas.
-- For apply_migration, omit only the outer BEGIN/COMMIT; the tool owns the tx.
BEGIN;
SET LOCAL search_path = pg_catalog;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

LOCK TABLE safe_walk_nearby.helper_locations IN ACCESS EXCLUSIVE MODE;

DO $before$
DECLARE
  column_state record;
  current_check text;
BEGIN
  SELECT atttypid, attnotnull INTO column_state
  FROM pg_attribute
  WHERE attrelid = 'safe_walk_nearby.helper_locations'::regclass
    AND attname = 'accuracy_m' AND attnum > 0 AND NOT attisdropped;
  IF NOT FOUND OR column_state.atttypid <> 'real'::regtype
      OR NOT column_state.attnotnull THEN
    RAISE EXCEPTION 'Expected the original real NOT NULL accuracy_m column; stop on schema drift';
  END IF;

  SELECT lower(regexp_replace(regexp_replace(pg_get_expr(conbin, conrelid),
      '::(double precision|real|integer|numeric)', '', 'g'),
      '[[:space:]()]', '', 'g')) INTO current_check
  FROM pg_constraint
  WHERE conrelid = 'safe_walk_nearby.helper_locations'::regclass
    AND conname = 'helper_locations_accuracy_m_check'
    AND contype = 'c' AND convalidated;
  IF current_check IS DISTINCT FROM 'accuracy_m>=0' THEN
    RAISE EXCEPTION 'Expected the original validated accuracy_m >= 0 CHECK';
  END IF;
END
$before$;

ALTER TABLE safe_walk_nearby.helper_locations
  ALTER COLUMN accuracy_m DROP NOT NULL,
  DROP CONSTRAINT helper_locations_accuracy_m_check,
  ADD CONSTRAINT helper_locations_accuracy_m_check
    CHECK (accuracy_m IS NULL OR accuracy_m >= 0);

DO $after$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_attribute
    WHERE attrelid = 'safe_walk_nearby.helper_locations'::regclass
      AND attname = 'accuracy_m' AND NOT attnotnull AND NOT attisdropped
      AND atttypid = 'real'::regtype
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'safe_walk_nearby.helper_locations'::regclass
      AND conname = 'helper_locations_accuracy_m_check'
      AND contype = 'c' AND convalidated
      AND lower(regexp_replace(regexp_replace(pg_get_expr(conbin, conrelid),
        '::(double precision|real|integer|numeric)', '', 'g'),
        '[[:space:]()]', '', 'g')) = 'accuracy_misnulloraccuracy_m>=0'
  ) THEN
    RAISE EXCEPTION 'Optional accuracy_m postcondition failed';
  END IF;
END
$after$;
COMMIT;
