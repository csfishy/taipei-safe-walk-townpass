// Disposable loopback database only. Never accepts a host/DSN/database name.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const args = process.argv.slice(2);
assert(args.length===4 && args[0]==='--pg-module' && args[2]==='--report');
const {Client} = require(path.resolve(args[1]));
const root = path.resolve(__dirname,'..');
const read = name => fs.readFileSync(path.join(root,name),'utf8').replace(/^\\[^\n]*$/gm,'');
const config = database => ({host:'127.0.0.1',port:55439,user:'postgres',password:'',database,
  ssl:false,options:'',connectionTimeoutMillis:5000,query_timeout:90000});
const database='nearby_upgrade_'+crypto.randomBytes(6).toString('hex');
const admin=new Client(config('postgres'));
const client=new Client(config(database));
let created=false,connected=false,version=null;
const results=[];
const migration=read('migrations/20261113010000_upgrade_nearby_backend_locked.sql');
const verify=read('06_verify_locked_backend.sql');
async function test(name,fn){await fn();results.push({name,status:'PASS'});console.log('PASS',results.length,name);}
(async()=>{
 await admin.connect();
 assert.equal((await admin.query('SELECT host(inet_server_addr()) AS host')).rows[0].host,'127.0.0.1');
 await admin.query(`CREATE DATABASE "${database}"`);created=true;
 await client.connect();connected=true;
 await client.query(read('local_test/00_bootstrap.sql').replace('postgis with schema extensions','postgis with schema public'));
 version=(await client.query(`SELECT public.postgis_lib_version() AS library,
  public.postgis_scripts_installed() AS scripts,
  (SELECT extversion FROM pg_extension WHERE extname='postgis') AS extension,
  version() AS postgres`)).rows[0];
 assert.equal(version.library,'3.3.7');assert.equal(version.extension,'3.3.7');
 assert.match(version.scripts,/^3\.3\.7(?: [0-9a-f]+)?$/);
 await client.query(read('01_create_tables.sql'));
 await client.query(read('migrations/20261107221444_allow_optional_helper_accuracy.sql'));
 await client.query(read('02_verify.sql'));
 await client.query(read('local_test/20_upgrade_fixture.sql'));
 await test('nonempty four-table upgrade over CRLF transport commits with owner-only RPCs',()=>client.query(migration.replace(/\n/g,'\r\n')));
 await test('read-only locked verifier passes',()=>client.query(verify));
 await test('data, legacy RPC ACLs, unrelated rows and auth CASCADE preserved',()=>client.query(read('local_test/21_assert_preserved.sql')));
 const calls=(await client.query(`SELECT format('SELECT * FROM public.%I(%s)',p.proname,
  coalesce((SELECT string_agg('NULL::'||format_type(t,NULL),',') FROM unnest(p.proargtypes) t),'')) AS sql
  FROM pg_proc p WHERE p.pronamespace='public'::regnamespace AND left(p.proname,7)='nearby_'`)).rows;
 assert.equal(calls.length,13);
 for(const role of ['anon','authenticated','service_role']){
  await test(`${role} cannot execute any of the 13 RPCs`,async()=>{
   await client.query(`SET ROLE ${role}`);
   for(const call of calls)await assert.rejects(client.query(call.sql),e=>e.code==='42501');
   await assert.rejects(client.query('SELECT safe_walk_nearby.purge_expired()'),e=>e.code==='42501');
   await client.query('RESET ROLE');
  });
 }
 await test('enabled-profile verifier rejects locked profile',async()=>{
  await assert.rejects(client.query(read('04_verify_backend.sql')),/metadata mismatch|ACL mismatch/);
  await client.query('ROLLBACK');await client.query(verify);
 });
 await test('locked verifier rejects accidental authenticated SOS grant',async()=>{
  await client.query('BEGIN; GRANT EXECUTE ON FUNCTION public.nearby_sos_send(double precision,double precision,uuid) TO authenticated');
  const inside=verify.replace('BEGIN TRANSACTION READ ONLY;','').replace(/ROLLBACK;\s*$/,'');
  await assert.rejects(client.query(inside),/ACL/);
  await client.query('ROLLBACK');await client.query(verify);
 });
 await test('repeat migration fails atomically and leaves owner-only state intact',async()=>{
  await assert.rejects(client.query(migration),/Expected four ordinary tables/);
  await client.query('ROLLBACK');await client.query(verify);
 });
 await test('all 14 function bodies retain CRLF and match canonical LF digest',async()=>{
  const {rows}=await client.query(`SELECT count(*)::int AS n FROM pg_proc p WHERE
   (p.pronamespace='public'::regnamespace AND left(p.proname,7)='nearby_'
    OR p.oid='safe_walk_nearby.purge_expired()'::regprocedure)
   AND md5(p.prosrc)<>md5(replace(p.prosrc,E'\\r\\n',E'\\n'))`);
  assert.equal(rows[0].n,14);await client.query(verify);
 });
 await test('normalizing CRLF does not hide a changed function body',async()=>{
  await client.query("BEGIN; CREATE OR REPLACE FUNCTION public.nearby_helper_opt_out() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$ BEGIN NULL; END $$");
  const inside=verify.replace('BEGIN TRANSACTION READ ONLY;','').replace(/ROLLBACK;\s*$/,'');
  await assert.rejects(client.query(inside),/metadata mismatch/);
  await client.query('ROLLBACK');await client.query(verify);
 });
 console.log(`ALL ${results.length} LOCKED DEPLOYMENT TESTS PASSED`);
})().catch(e=>{console.error(e);process.exitCode=1;}).finally(async()=>{
 if(connected)await client.end();
 if(created){assert(/^nearby_upgrade_[0-9a-f]{12}$/.test(database));await admin.query(`DROP DATABASE "${database}"`);}
 await admin.end();
 const files=['migrations/20261113010000_upgrade_nearby_backend_locked.sql','06_verify_locked_backend.sql','local_test/run_locked_tests.cjs'];
 fs.writeFileSync(args[3],JSON.stringify({status:process.exitCode?'FAIL':'PASS',checked_at_utc:new Date().toISOString(),
  version,passed_groups:results.length,results,sha256:Object.fromEntries(files.map(n=>[n,crypto.createHash('sha256').update(fs.readFileSync(path.join(root,n))).digest('hex')]))},null,2)+'\n');
});
