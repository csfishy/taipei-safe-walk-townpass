// Local PostgreSQL + PostGIS integration tests. Never accepts a remote host/DSN.
// Supply an external pg installation to keep application dependencies unchanged:
// node run_upgrade_tests.cjs --pg-module /absolute/path/node_modules/pg --port 55439
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const args = process.argv.slice(2);
const option = (name, fallback) => args.includes(name) ? args[args.indexOf(name) + 1] : fallback;
if (args.length % 2 || args.some((arg, i) => i % 2 === 0 &&
    !['--pg-module', '--port', '--expect-postgis', '--report'].includes(arg))) {
  throw Error('Supported options: --pg-module, --port, --expect-postgis, --report; no remote host or DSN');
}
const expectedPostgis = option('--expect-postgis', null);
if (expectedPostgis) assert(/^\d+\.\d+\.\d+$/.test(expectedPostgis), 'Expected an exact PostGIS version');
const reportPath = option('--report', null);
const { Client } = require(path.resolve(option('--pg-module', 'node_modules/pg')));
const port = Number(option('--port', '55439'));
assert(Number.isInteger(port) && port > 1024 && port < 65536);
const root = path.resolve(__dirname, '..');
const migration = fs.readFileSync(path.join(root, 'migrations/20261113000000_upgrade_nearby_backend.sql'), 'utf8');
const verifier = fs.readFileSync(path.join(root, '04_verify_backend.sql'), 'utf8');
const read = name => fs.readFileSync(path.join(root, name), 'utf8').replace(/^\\[^\n]*$/gm, '');
const config = database => ({ host: '127.0.0.1', port, user: 'postgres', password: '',
  database, ssl: false, options: '', connectionTimeoutMillis: 5000, query_timeout: 90000 });
const admin = new Client(config('postgres'));
const databases = [];
const clients = new Set();
let passed = 0;
let versions = null;
const groups = [];
const startedAt = new Date().toISOString();
async function connect(database) {
  const client = new Client(config(database));
  await client.connect();
  clients.add(client);
  const { rows } = await client.query('SELECT host(inet_server_addr()) AS host, current_database() AS db');
  assert.equal(rows[0].host, '127.0.0.1');
  assert.equal(rows[0].db, database);
  return client;
}
async function test(name, fn) {
  try {
    await fn();
    groups.push({ name, status: 'PASS' });
    console.log(`PASS ${++passed}: ${name}`);
  } catch (error) {
    groups.push({ name, status: 'FAIL', message: error.message });
    throw error;
  }
}
async function rejects(client, sql, pattern) {
  await assert.rejects(client.query(sql), pattern);
  await client.query('ROLLBACK');
}
async function fixture() {
  const database = 'nearby_upgrade_' + crypto.randomBytes(6).toString('hex');
  assert(/^nearby_upgrade_[a-f0-9]{12}$/.test(database));
  await admin.query(`CREATE DATABASE "${database}"`);
  databases.push(database);
  const client = await connect(database);
  let bootstrap = read('local_test/00_bootstrap.sql').replace(
    'create extension if not exists postgis with schema extensions;',
    'create extension if not exists postgis with schema public;');
  await client.query(bootstrap);
  if (expectedPostgis) {
    const runtime = (await client.query(`SELECT public.postgis_lib_version() AS library,
      public.postgis_scripts_installed() AS scripts,
      (SELECT extversion FROM pg_extension WHERE extname='postgis') AS extension`)).rows[0];
    for (const [component, actual] of Object.entries(runtime)) {
      // PostGIS 3.3 embeds its source revision in scripts_installed(), e.g.
      // "3.3.7 a0c7967". Keep the raw value in the report, but compare the exact
      // release; dev/prerelease/unknown suffixes and other releases still fail.
      const release = component === 'scripts'
        ? actual.match(/^(\d+\.\d+\.\d+)(?: [0-9a-f]+)?$/i)?.[1] ?? actual
        : actual;
      assert.equal(release, expectedPostgis, `PostGIS ${component} must match the requested version`);
    }
  }
  await client.query(read('01_create_tables.sql'));
  await client.query(read('migrations/20261107221444_allow_optional_helper_accuracy.sql'));
  await client.query(read('02_verify.sql'));
  return { client, database };
}
async function session(database, uid) {
  const client = await connect(database);
  await client.query("SELECT set_config('request.jwt.claims', $1, false)",
    [JSON.stringify({ sub: uid, role: 'authenticated' })]);
  await client.query('SET ROLE authenticated');
  return client;
}
async function close(client) { clients.delete(client); await client.end(); }

(async () => {
  await admin.connect();
  assert.equal((await admin.query('SELECT host(inet_server_addr()) AS host')).rows[0].host, '127.0.0.1');
  const main = await fixture();
  const c = main.client;
  versions = (await c.query(`SELECT version() AS postgres,
    public.postgis_lib_version() AS postgis_library,
    public.postgis_scripts_installed() AS postgis_scripts,
    public.postgis_full_version() AS postgis_full_version,
    (SELECT extversion FROM pg_extension WHERE extname='postgis') AS postgis_extension,
    (SELECT extversion FROM pg_extension WHERE extname='pgcrypto') AS pgcrypto`)).rows[0];
  console.log('Local versions:', versions);
  await test('metadata inventory runs read-only before upgrade', () => c.query(read('03_inventory.sql')));
  await c.query(read('local_test/20_upgrade_fixture.sql'));
  await test('nonempty four-table baseline upgrades atomically', () => c.query(migration));
  await test('post-upgrade verifier runs in a read-only transaction', () => c.query(verifier));
  await test('rows, unrelated data, legacy definitions/ACLs and auth CASCADE are preserved',
    () => c.query(read('local_test/21_assert_preserved.sql')));
  await test('second application fails without changing the installed backend', async () => {
    await rejects(c, migration, /Expected four ordinary tables|already exists|repeat application/);
    await c.query(verifier);
  });
  await test('full upgraded behavior suite: permissions, 499/501m, TTL, contacts, limits and deletion',
    () => c.query(read('local_test/30_test_upgraded_backend.sql')));
  await test('all 13 RPCs reject anon and authenticated-without-session', async () => {
    const calls = (await c.query(`SELECT format('SELECT * FROM public.%I(%s)',p.proname,
      coalesce((SELECT string_agg('NULL::'||format_type(t,NULL),',')
        FROM unnest(p.proargtypes) t),'')) AS sql FROM pg_proc p
      WHERE p.pronamespace='public'::regnamespace AND left(p.proname,7)='nearby_'`)).rows;
    assert.equal(calls.length, 13);
    const denied = await connect(main.database);
    for (const [role, state] of [['anon','42501'],['authenticated','28000']]) {
      await denied.query(`SET ROLE ${role}`);
      for (const call of calls) {
        await assert.rejects(denied.query(call.sql), error => error.code === state);
      }
      await denied.query('RESET ROLE');
    }
    await close(denied);
  });
  // The historical suite rolls back; its identities and alerts are gone here.
  await test('verifier rejects body/default/ACL/index/FK/CHECK drift', async () => {
    const corruptions = [
      'ALTER FUNCTION public.nearby_sos_send(double precision,double precision,uuid) SECURITY INVOKER',
      "ALTER FUNCTION public.nearby_helper_opt_out() SET search_path=public",
      'GRANT EXECUTE ON FUNCTION public.nearby_sos_send(double precision,double precision,uuid) TO anon',
      'GRANT SELECT(user_id) ON safe_walk_nearby.helper_profiles TO PUBLIC',
      'DROP INDEX safe_walk_nearby.alerts_expires_idx',
      'ALTER TABLE safe_walk_nearby.alert_deliveries DROP CONSTRAINT alert_deliveries_recipient_id_fkey',
      'ALTER TABLE safe_walk_nearby.trusted_contacts DROP CONSTRAINT trusted_contacts_check',
      "CREATE OR REPLACE FUNCTION public.nearby_helper_opt_out() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$ BEGIN NULL; END $$",
      "CREATE OR REPLACE FUNCTION public.nearby_helper_report_location(p_lat double precision,p_lng double precision,p_accuracy_m real DEFAULT 99) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$ BEGIN NULL; END $$",
    ];
    // Strip only the verifier's outer transaction so the mutation and check share
    // one disposable transaction; any failed assertion rolls the mutation back.
    const inside = verifier.replace('BEGIN TRANSACTION READ ONLY;', '').replace(/ROLLBACK;\s*$/, '');
    for (const sql of corruptions) {
      await c.query('BEGIN');
      await c.query(sql);
      await assert.rejects(c.query(inside));
      await c.query('ROLLBACK');
      await c.query(verifier);
    }
  });

  const sender = 'dddddddd-0000-4000-8000-000000000001';
  const recipient = 'dddddddd-0000-4000-8000-000000000002';
  const stranger = 'dddddddd-0000-4000-8000-000000000003';
  await c.query('INSERT INTO auth.users(id) VALUES ($1),($2),($3)', [sender,recipient,stranger]);
  const a = await session(main.database, sender);
  const b = await session(main.database, sender);
  await test('concurrent identical SOS requests return the same completed result once', async () => {
    const request = 'dddddddd-0000-4000-8000-000000000004';
    const results = await Promise.all([a,b].map(s => s.query('SELECT public.nearby_sos_send(0,0,$1) AS n', [request])));
    assert.equal(results[0].rows[0].n, results[1].rows[0].n);
    assert.equal((await c.query('SELECT count(*)::int AS n FROM safe_walk_nearby.alerts WHERE sender_id=$1', [sender])).rows[0].n, 1);
  });
  await c.query('DELETE FROM safe_walk_nearby.alerts WHERE sender_id=$1', [sender]);
  await test('concurrent different SOS requests cannot bypass sender rate limit', async () => {
    const results = await Promise.allSettled([a,b].map(s => s.query('SELECT public.nearby_sos_send(0,0,$1)', [crypto.randomUUID()])));
    assert.equal(results.filter(r => r.status==='fulfilled').length, 1);
    assert.equal(results.find(r => r.status==='rejected').reason.code, 'PT429');
  });
  await test('concurrent initial location reports cannot bypass 10-second limit', async () => {
    await a.query("SELECT public.nearby_helper_opt_in('test.v1')");
    const results = await Promise.allSettled([a,b].map(s => s.query('SELECT public.nearby_helper_report_location(0,0)')));
    assert.equal(results.filter(r => r.status==='fulfilled').length, 1);
    assert.equal(results.find(r => r.status==='rejected').reason.code, 'PT429');
  });
  const r = await session(main.database, recipient);
  const s = await session(main.database, stranger);
  await test('two accounts cannot consume the same invite code', async () => {
    const code = (await a.query("SELECT code FROM public.nearby_contact_invite_create('test')")).rows[0].code;
    const results = await Promise.all([r,s].map(x => x.query('SELECT public.nearby_contact_invite_accept($1) AS status', [code])));
    assert.deepEqual(results.map(x => x.rows[0].status).sort(), ['invalid','ok']);
    assert.equal((await c.query('SELECT count(*)::int AS n FROM safe_walk_nearby.trusted_contacts WHERE owner_id=$1', [sender])).rows[0].n, 1);
  });
  await test('50-helper cap includes contacts separately and deduplicates an overlapping contact', async () => {
    await c.query('BEGIN');
    await c.query(`INSERT INTO auth.users(id)
      SELECT ('cccccccc-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid FROM generate_series(1,55) i;
      INSERT INTO auth.users(id) VALUES ('cccccccc-0000-4000-8000-000000000099');
      INSERT INTO safe_walk_nearby.helper_profiles(user_id,consent_version,consented_at)
        SELECT id,'test.v1',now() FROM auth.users WHERE id::text LIKE 'cccccccc%' AND id::text NOT LIKE '%000000000099';
      INSERT INTO safe_walk_nearby.helper_locations(user_id,geog,reported_at,expires_at)
        SELECT ('cccccccc-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,
          public.st_setsrid(public.st_makepoint(0,i*0.000001),4326)::public.geography,
          now(),now()+interval '10 minutes' FROM generate_series(1,55) i;
      INSERT INTO safe_walk_nearby.trusted_contacts(owner_id,contact_id,display_name) VALUES
        ('cccccccc-0000-4000-8000-000000000099','cccccccc-0000-4000-8000-000000000001','test'),
        ('cccccccc-0000-4000-8000-000000000099','dddddddd-0000-4000-8000-000000000002','test');
      SELECT set_config('request.jwt.claims','{"sub":"cccccccc-0000-4000-8000-000000000099","role":"authenticated"}',true);
      SET LOCAL ROLE authenticated;`);
    const result = await c.query('SELECT public.nearby_sos_send(0,0,$1) AS n', [crypto.randomUUID()]);
    assert.equal(result.rows[0].n, 51);
    await c.query('ROLLBACK');
  });
  await Promise.all([a,b,r,s].map(close));

  for (const [label, mutation, error] of [
    ['unexpected column', 'ALTER TABLE safe_walk_nearby.alerts ADD COLUMN unexpected text', /20 design columns/],
    ['wrong extension schema', 'ALTER EXTENSION pgcrypto SET SCHEMA public', /extensions pgcrypto/],
    ['unexpected existing RPC', 'CREATE FUNCTION public.nearby_unknown() RETURNS int LANGUAGE sql AS $$ SELECT 1 $$', /already exists/],
    ['invalid existing consent', "INSERT INTO auth.users(id) VALUES ('eeeeeeee-0000-4000-8000-000000000099'); INSERT INTO safe_walk_nearby.helper_profiles VALUES ('eeeeeeee-0000-4000-8000-000000000099','',now(),NULL)", /check constraint/],
    ['unsafe default table grant (late postcondition failure)', 'ALTER DEFAULT PRIVILEGES IN SCHEMA safe_walk_nearby GRANT SELECT ON TABLES TO pg_monitor', /Unexpected non-owner schema\/table ACL/],
  ]) {
    await test(`upgrade rejects ${label} and leaves four-table baseline intact`, async () => {
      const { client } = await fixture();
      await client.query(mutation);
      await rejects(client, migration, error);
      assert.equal((await client.query("SELECT count(*)::int AS n FROM pg_class WHERE relnamespace='safe_walk_nearby'::regnamespace AND relkind='r'")).rows[0].n, 4);
      assert.equal((await client.query("SELECT count(*)::int AS n FROM pg_proc WHERE pronamespace='safe_walk_nearby'::regnamespace")).rows[0].n, 0);
      assert.equal((await client.query("SELECT confrelid::regclass::text AS target FROM pg_constraint WHERE conrelid='safe_walk_nearby.alert_deliveries'::regclass AND conname='alert_deliveries_recipient_id_fkey'")).rows[0].target, 'safe_walk_nearby.helper_profiles');
      await close(client);
    });
  }
  console.log(`ALL ${passed} UPGRADE TEST GROUPS PASSED; no remote database used.`);
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(async () => {
  await Promise.allSettled([...clients].map(close));
  for (const db of databases) {
    assert(/^nearby_upgrade_[a-f0-9]{12}$/.test(db));
    await admin.query(`DROP DATABASE IF EXISTS "${db}"`);
  }
  await admin.end();
  if (reportPath) {
    const inputs = ['01_create_tables.sql', '02_verify.sql', '03_inventory.sql',
      '04_verify_backend.sql', 'migrations/20261107221444_allow_optional_helper_accuracy.sql',
      'migrations/20261113000000_upgrade_nearby_backend.sql', 'local_test/00_bootstrap.sql',
      'local_test/20_upgrade_fixture.sql', 'local_test/21_assert_preserved.sql',
      'local_test/30_test_upgraded_backend.sql', 'local_test/run_upgrade_tests.cjs'];
    const sha256 = Object.fromEntries(inputs.map(name => [name,
      crypto.createHash('sha256').update(fs.readFileSync(path.join(root,name))).digest('hex')]));
    fs.writeFileSync(reportPath, JSON.stringify({
      status: process.exitCode ? 'FAIL' : 'PASS', started_at_utc: startedAt,
      completed_at_utc: new Date().toISOString(), expected_postgis: expectedPostgis,
      versions, passed_groups: passed, groups, sha256,
      scope: 'Disposable loopback databases with synthetic Auth/positions only; no remote deployment',
    }, null, 2) + '\n');
  }
});
