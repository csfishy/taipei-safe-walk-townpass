// Isolated loopback PostgreSQL only. Never accepts a remote DSN or credentials.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const assert=require('node:assert/strict');
const args=process.argv.slice(2);
assert(args.length===4&&args[0]==='--pg-module'&&args[2]==='--report');
const {Client}=require(path.resolve(args[1]));
const root=__dirname,read=f=>fs.readFileSync(path.join(root,f),'utf8').replace(/^\\[^\n]*$/gm,'');
const db='nearby_upgrade_'+crypto.randomBytes(6).toString('hex');
const config=database=>({host:'127.0.0.1',port:55439,user:'postgres',password:'',database,ssl:false,connectionTimeoutMillis:5000,query_timeout:60000});
const admin=new Client(config('postgres')),c=new Client(config(db));
let created=false,connected=false,version;const results=[];
async function test(name,fn){await fn();results.push({name,status:'PASS'});console.log('PASS',results.length,name);}
async function owner(sql,params=[]){await c.query('RESET ROLE');return c.query(sql,params);}
async function api(sql,params=[]){await c.query('SET ROLE anon');return c.query(sql,params);}
async function login(email){return (await api('SELECT * FROM public.swtest_login($1)',[email])).rows[0];}
const reject=(sql,params,code)=>assert.rejects(api(sql,params),e=>e.code===code);
const call=(name,types,values)=>api(`SELECT * FROM public.swtest_${name}(${types.map((_,i)=>'$'+(i+1)).join(',')})`,values);
const send=(token,id=crypto.randomUUID())=>call('send',[1,2,3,4],[token,25.033,121.565,id]);
const optin=token=>call('opt_in',[1,2],[token,'live-test-v1']);
const location=(token,lat=25.033,lng=121.565)=>call('report_location',[1,2,3],[token,lat,lng]);
const fetchAlerts=token=>call('fetch',[1],[token]);
let a,b,b2,far;
(async()=>{
 await admin.connect();assert.equal((await admin.query('SELECT host(inet_server_addr()) h')).rows[0].h,'127.0.0.1');
 await admin.query(`CREATE DATABASE ${db}`);created=true;await c.connect();connected=true;
 await c.query(read('../nearby_helper/local_test/00_bootstrap.sql').replace('postgis with schema extensions','postgis with schema public'));
 version=(await c.query('SELECT public.postgis_lib_version() AS postgis,version() AS postgres')).rows[0];assert.equal(version.postgis,'3.3.7');
 await c.query(read('../nearby_helper/01_create_tables.sql'));
 await c.query(read('../nearby_helper/migrations/20261107221444_allow_optional_helper_accuracy.sql'));
 await c.query(read('../nearby_helper/local_test/20_upgrade_fixture.sql'));
 await c.query(read('../nearby_helper/migrations/20261113010000_upgrade_nearby_backend_locked.sql'));
 const production=read('../nearby_helper/06_verify_locked_backend.sql');
 await c.query(production);
 const counts=async()=>(await owner(`SELECT (SELECT count(*) FROM safe_walk_nearby.helper_profiles)::int profiles,
  (SELECT count(*) FROM auth.users)::int auth_users`)).rows[0];
 const before=await counts();
 await test('install over CRLF commits in separate namespace',()=>c.query(read('01_install.sql').replace(/\n/g,'\r\n')));
 await test('read-only verifier passes locked state',()=>c.query(read('03_verify.sql')));
 await test('installed test login is disabled by default',()=>reject('SELECT * FROM swtest_login($1)',['a@example.invalid'],'42501'));
 await owner(read('02_enable_for_two_hours.sql'));
 await test('arbitrary new email logs in without Auth signup or mail',async()=>{a=await login('a@example.invalid');assert.equal(a.test_session.length,64);});
 await test('trim and case normalize to same account, independent session',async()=>{
  b=await login('b@example.invalid');b2=await login(' B@EXAMPLE.INVALID ');
  assert.equal(b.account_id,b2.account_id);assert.notEqual(b.test_session,b2.test_session);
 });
 await test('invalid email is rejected',()=>reject('SELECT * FROM swtest_login($1)',['bad'],'22023'));
 await test('forged bearer session is rejected',()=>reject('SELECT * FROM swtest_fetch($1)',['0'.repeat(64)],'28000'));
 await test('location requires explicit helper opt-in',()=>reject('SELECT swtest_report_location($1,25,121)',[a.test_session],'42501'));
 await test('real opt-in and location writes persist',async()=>{await optin(b.test_session);await location(b.test_session);});
 await test('invalid coordinate including NaN is rejected',async()=>{
  await reject("SELECT swtest_report_location($1,'NaN'::float8,121)",[b.test_session],'22023');
  await reject('SELECT swtest_report_location($1,91,121)',[b.test_session],'22023');
 });
 await test('position update rate is enforced',()=>reject('SELECT swtest_report_location($1,25,121)',[b.test_session],'PT429'));
 await test('out-of-radius helper is not selected',async()=>{far=await login('far@example.invalid');await optin(far.test_session);await location(far.test_session,24,120);});
 const request=crypto.randomUUID();
 await test('send selects only nearby test helpers and never production profiles',async()=>{
  assert.equal((await send(a.test_session,request)).rows[0].swtest_send,1);
  assert.equal((await fetchAlerts(far.test_session)).rowCount,0);
 });
 await test('recipient sees actual persisted alert and no sender identity',async()=>{
  const alerts=(await fetchAlerts(b.test_session)).rows;assert.equal(alerts.length,1);
  assert.equal(alerts[0].radius_m,500);assert.equal('sender_id' in alerts[0],false);
 });
 await test('idempotent send adds no duplicate deliveries',async()=>{
  assert.equal((await send(a.test_session,request)).rows[0].swtest_send,1);
  assert.equal((await fetchAlerts(b.test_session)).rowCount,1);
 });
 await test('different account cannot fetch recipient data even when also a helper',async()=>{
  await optin(a.test_session);assert.equal((await fetchAlerts(a.test_session)).rowCount,0);
 });
 await test('SOS cooldown is enforced',()=>reject('SELECT swtest_send($1,25,121,$2)',[a.test_session,crypto.randomUUID()],'PT429'));
 await test('rolling hourly quota survives physical alert cleanup',async()=>{
  await owner("UPDATE safe_walk_nearby_live_test.accounts SET send_times=ARRAY[now()-interval '1 minute',now()-interval '2 minutes',now()-interval '3 minutes',now()-interval '4 minutes',now()-interval '5 minutes'] WHERE id=$1",[a.account_id]);
  await owner('DELETE FROM safe_walk_nearby_live_test.alerts WHERE sender_id=$1',[a.account_id]);
  await assert.rejects(send(a.test_session),e=>e.code==='PT429');
 });
 await test('one-device logout preserves another session and location',async()=>{
  await call('logout',[1],[b.test_session]);await fetchAlerts(b2.test_session);
  assert.equal((await owner('SELECT count(*)::int n FROM safe_walk_nearby_live_test.locations WHERE account_id=$1',[b.account_id])).rows[0].n,1);
  await assert.rejects(fetchAlerts(b.test_session),e=>e.code==='28000');
 });
 await test('opt-out deletes location and pending recipient records',async()=>{
  await call('opt_out',[1],[b2.test_session]);await assert.rejects(fetchAlerts(b2.test_session),e=>e.code==='42501');
  assert.equal((await owner('SELECT count(*)::int n FROM safe_walk_nearby_live_test.locations WHERE account_id=$1',[b.account_id])).rows[0].n,0);
 });
 await test('expired location is not selected',async()=>{
  await optin(b2.test_session);await location(b2.test_session);
  await owner("UPDATE safe_walk_nearby_live_test.locations SET expires_at=now()-interval '1 second' WHERE account_id=$1",[b.account_id]);
  assert.equal((await send(far.test_session)).rows[0].swtest_send,0);
 });
 await test('expired session is rejected',async()=>{
  await owner("UPDATE safe_walk_nearby_live_test.sessions SET expires_at=now()-interval '1 second' WHERE token_hash=extensions.digest($1,'sha256')",[b2.test_session]);
  await assert.rejects(optin(b2.test_session),e=>e.code==='28000');
 });
 await test('fifty-recipient limit and sender exclusion apply in the database',async()=>{
  const batch=await login('batch@example.invalid');await optin(batch.test_session);await location(batch.test_session);
  await owner(`INSERT INTO safe_walk_nearby_live_test.accounts(email_digest,helper_enabled)
    SELECT extensions.digest('synthetic-helper-'||i,'sha256'),true FROM generate_series(1,51) i`);
  await owner(`INSERT INTO safe_walk_nearby_live_test.locations
    SELECT id,public.st_setsrid(public.st_makepoint(121.565,25.033),4326)::public.geography,now(),now()+interval '10 minutes'
    FROM safe_walk_nearby_live_test.accounts WHERE consent_version IS NULL AND helper_enabled`);
  const id=crypto.randomUUID();assert.equal((await send(batch.test_session,id)).rows[0].swtest_send,50);
  assert.equal((await fetchAlerts(batch.test_session)).rowCount,0);
 });
 await test('test-account cap rejects new labels but permits an existing one',async()=>{
  await owner(`INSERT INTO safe_walk_nearby_live_test.accounts(email_digest)
    SELECT extensions.digest('cap-'||i,'sha256') FROM generate_series(1,200-(SELECT count(*)::int FROM safe_walk_nearby_live_test.accounts)) i`);
  await assert.rejects(login('over-cap@example.invalid'),e=>e.code==='PT429');
  assert.equal((await login('a@example.invalid')).account_id,a.account_id);
 });
 await test('global login throttle rejects excess attempts',async()=>{
  await owner('UPDATE safe_walk_nearby_live_test.control SET login_bucket=now(),login_count=30');
  await assert.rejects(login('new@example.invalid'),e=>e.code==='PT429');
  await owner('UPDATE safe_walk_nearby_live_test.control SET login_count=0');
 });
 await test('raw email and bearer tokens are not stored',async()=>{
  assert.equal((await owner('SELECT count(*)::int n FROM safe_walk_nearby_live_test.accounts WHERE octet_length(email_digest)<>32')).rows[0].n,0);
  assert.equal((await owner('SELECT count(*)::int n FROM safe_walk_nearby_live_test.sessions WHERE token_hash=extensions.digest($1,\'sha256\')',[a.test_session])).rows[0].n,1);
 });
 await test('API roles cannot read tables or execute private helpers',async()=>{
  for(const role of ['anon','authenticated','service_role']){
   await c.query(`SET ROLE ${role}`);
   await assert.rejects(c.query('SELECT * FROM safe_walk_nearby_live_test.sessions'),e=>e.code==='42501');
   await assert.rejects(c.query('SELECT safe_walk_nearby_live_test.require_enabled()'),e=>e.code==='42501');
  }await c.query('RESET ROLE');
 });
 await test('time-window expiry denies every business path',async()=>{
  await owner("UPDATE safe_walk_nearby_live_test.control SET enabled_until=now()-interval '1 second'");
  await assert.rejects(login('z@example.invalid'),e=>e.code==='42501');
  await assert.rejects(optin(a.test_session),e=>e.code==='42501');
  await assert.rejects(send(a.test_session),e=>e.code==='42501');
  await assert.rejects(fetchAlerts(a.test_session),e=>e.code==='42501');
 });
 await test('production verifier and fixture account counts remain unchanged',async()=>{
  await owner(production);assert.deepEqual(await counts(),before);
  await owner(read('../nearby_helper/local_test/21_assert_preserved.sql'));
 });
 await test('independent test verifier passes final disabled state',()=>owner(read('03_verify.sql')));
 console.log(`ALL ${results.length} LIVE TEST GROUPS PASSED`);
})().catch(e=>{console.error(e);process.exitCode=1;}).finally(async()=>{
 if(connected)await c.end();
 if(created){assert(/^nearby_upgrade_[0-9a-f]{12}$/.test(db));await admin.query(`DROP DATABASE ${db}`);}
 await admin.end();
 fs.writeFileSync(args[3],JSON.stringify({status:process.exitCode?'FAIL':'PASS',checked_at_utc:new Date().toISOString(),version,passed_groups:results.length,results,
  sha256:Object.fromEntries(['01_install.sql','02_enable_for_two_hours.sql','03_verify.sql','run_tests.cjs'].map(f=>[f,crypto.createHash('sha256').update(fs.readFileSync(path.join(root,f))).digest('hex')]))},null,2)+'\n');
});
