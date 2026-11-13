-- Generator fragment; run 04_verify_backend.sql, not this fragment on its own.
DO $backend$
DECLARE
  expected record;
  actual record;
  api_role text;
  relation record;
  expression text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension e JOIN pg_namespace n ON n.oid=e.extnamespace
      WHERE e.extname='postgis' AND n.nspname='public') OR NOT EXISTS (
      SELECT 1 FROM pg_extension e JOIN pg_namespace n ON n.oid=e.extnamespace
      WHERE e.extname='pgcrypto' AND n.nspname='extensions') THEN
    RAISE EXCEPTION 'Extension schema mismatch';
  END IF;
  IF (SELECT count(*) FROM pg_proc WHERE pronamespace='public'::regnamespace
      AND left(proname,7)='nearby_') <> 13 THEN
    RAISE EXCEPTION 'Expected exactly 13 nearby RPCs; unexpected overloads fail';
  END IF;
  FOR expected IN SELECT * FROM (VALUES
-- FUNCTION_MANIFEST
  ) AS functions(signature, body_md5, client_callable, result, argument_names)
  LOOP
    SELECT p.*, pg_get_function_result(p.oid) AS result,
      pg_get_userbyid(p.proowner) AS owner,
      l.lanname AS language
    INTO actual FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang
    WHERE p.oid=to_regprocedure(expected.signature);
    IF NOT FOUND OR NOT actual.prosecdef OR actual.prokind <> 'f'
        OR actual.provolatile <> 'v' OR actual.proisstrict
        OR actual.proleakproof OR actual.proparallel <> 'u'
        OR actual.proconfig IS DISTINCT FROM ARRAY['search_path=""']
        OR md5(actual.prosrc) <> expected.body_md5
        OR lower(regexp_replace(regexp_replace(replace(actual.result, 'timestamp with time zone', 'timestamptz'),
             '\s+', ' ', 'g'), '\s*([(),])\s*', '\1', 'g')) <> expected.result
        OR coalesce(actual.proargnames[1:actual.pronargs], ARRAY[]::text[]) <> expected.argument_names
        OR actual.owner <> pg_get_userbyid((SELECT nspowner FROM pg_namespace
             WHERE oid='safe_walk_nearby'::regnamespace))
        OR actual.language <> (CASE WHEN expected.client_callable THEN 'plpgsql' ELSE 'sql' END) THEN
      RAISE EXCEPTION 'RPC signature/body/security metadata mismatch: %', expected.signature;
    END IF;
    IF (actual.pronargdefaults <> CASE WHEN actual.proname='nearby_helper_report_location' THEN 1 ELSE 0 END)
        OR (actual.pronargdefaults=1 AND
            pg_get_expr(actual.proargdefaults, 0) IS DISTINCT FROM 'NULL::real') THEN
      RAISE EXCEPTION 'Unexpected RPC defaults: %', expected.signature;
    END IF;
    IF EXISTS (SELECT 1 FROM aclexplode(coalesce(actual.proacl,
        acldefault('f', actual.proowner))) a WHERE a.grantee <> actual.proowner
        AND (NOT expected.client_callable OR a.grantee <> 'authenticated'::regrole
             OR a.privilege_type <> 'EXECUTE' OR a.is_grantable)) THEN
      RAISE EXCEPTION 'Unexpected explicit function ACL: %', expected.signature;
    END IF;
    FOREACH api_role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
      IF has_function_privilege(api_role, actual.oid, 'EXECUTE') IS DISTINCT FROM
          (expected.client_callable AND api_role='authenticated') THEN
        RAISE EXCEPTION 'Effective RPC ACL mismatch: % / %', expected.signature, api_role;
      END IF;
    END LOOP;
  END LOOP;

  IF (SELECT array_agg(lower(regexp_replace(pg_get_expr(conbin,conrelid),
          '[[:space:]()]', '', 'g')) ORDER BY lower(pg_get_expr(conbin,conrelid)))
      FROM pg_constraint WHERE conrelid='safe_walk_nearby.trusted_contacts'::regclass AND contype='c')
      IS DISTINCT FROM ARRAY['char_lengthdisplay_name>=1andchar_lengthdisplay_name<=20',
                             'owner_id<>contact_id'] THEN
    RAISE EXCEPTION 'Trusted contacts CHECK mismatch';
  END IF;
  FOR expected IN SELECT * FROM (VALUES
    ('helper_locations','geog','gist',ARRAY['geog']),
    ('helper_locations','expires','btree',ARRAY['expires_at']),
    ('alerts','sender','btree',ARRAY['sender_id','created_at']),
    ('alerts','expires','btree',ARRAY['expires_at']),
    ('alert_deliveries','recipient','btree',ARRAY['recipient_id']),
    ('helper_areas','center','gist',ARRAY['center']),
    ('helper_areas','user','btree',ARRAY['user_id']),
    ('contact_invites','owner','btree',ARRAY['owner_id']),
    ('trusted_contacts','owner','btree',ARRAY['owner_id']),
    ('trusted_contacts','contact','btree',ARRAY['contact_id']),
    ('contact_invite_attempts','attempts','btree',ARRAY['user_id','attempted_at'])
  ) AS indexes(table_name, label, method, columns)
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_index i JOIN pg_class idx ON idx.oid=i.indexrelid
      JOIN pg_am am ON am.oid=idx.relam
      WHERE i.indrelid=to_regclass(format('safe_walk_nearby.%I',expected.table_name))
        AND i.indisvalid AND i.indisready AND i.indpred IS NULL AND i.indexprs IS NULL
        AND am.amname=expected.method AND i.indnkeyatts=cardinality(expected.columns)
        AND i.indnatts=i.indnkeyatts
        AND (SELECT array_agg(a.attname::text ORDER BY k.position)
          FROM unnest(i.indkey) WITH ORDINALITY k(attnum,position)
          JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=k.attnum) = expected.columns
    ) THEN
      RAISE EXCEPTION 'Missing valid unconditional index: % / %', expected.table_name, expected.label;
    END IF;
  END LOOP;
  -- PUBLIC column grants can be hidden by schema denial; reject those too.
  IF EXISTS (SELECT 1 FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid,
      LATERAL aclexplode(a.attacl) acl WHERE c.relnamespace='safe_walk_nearby'::regnamespace
      AND acl.grantee <> c.relowner) THEN
    RAISE EXCEPTION 'Unexpected non-owner column ACL';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_namespace n,
      LATERAL aclexplode(coalesce(n.nspacl,acldefault('n',n.nspowner))) a
      WHERE n.oid='safe_walk_nearby'::regnamespace AND a.grantee <> n.nspowner)
      OR EXISTS (SELECT 1 FROM pg_class c,
      LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a
      WHERE c.relnamespace='safe_walk_nearby'::regnamespace AND c.relkind='r'
      AND a.grantee <> c.relowner) THEN
    RAISE EXCEPTION 'Unexpected non-owner schema/table ACL';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_class c WHERE c.relnamespace='safe_walk_nearby'::regnamespace
      AND c.relowner <> (SELECT nspowner FROM pg_namespace WHERE oid=c.relnamespace)) THEN
    RAISE EXCEPTION 'Unexpected relation owner';
  END IF;
END $backend$;
