// Synthetic fixtures, disposable loopback DB only; no remote DSN accepted.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const args=process.argv.slice(2);assert(args.length===4&&args[0]==='--pg-module'&&args[2]==='--report');
const {Client}=require(path.resolve(args[1]));
const config=database=>({host:'127.0.0.1',port:55439,user:'postgres',password:'',database,ssl:false,connectionTimeoutMillis:5000,query_timeout:60000});
const db='nearby_upgrade_'+crypto.randomBytes(6).toString('hex'),admin=new Client(config('postgres')),c=new Client(config(db));
const read=f=>fs.readFileSync(path.join(__dirname,f),'utf8').replace(/\r\n/g,'\n').replace(/^\\[^\n]*$/gm,'');
const results=[];let created=false,connected=false,version;
async function test(name,fn){await fn();results.push({name,status:'PASS'});console.log('PASS',results.length,name);}
async function owner(sql,p=[]){if(sql==='ROLLBACK')return c.query(sql);await c.query('RESET ROLE');return c.query(sql,p);}
async function api(name,p=[],role='anon'){
 await c.query(`SET ROLE ${role}`);return (await c.query(`SELECT * FROM public.swtest_${name}(${p.map((_,i)=>'$'+(i+1)).join(',')})`,p)).rows;
}
const login=async e=>(await api('login',[e]))[0];
const token=()=>crypto.randomBytes(32).toString('hex');
const register=(s,d,endpoint='https://web.push.apple.com/'+d)=>api('receiver_register',[s.test_session,d,endpoint,'B'.repeat(87),'A'.repeat(22)]);
const start=(s,d,lat=25,lng=121,accuracy=10,observed=new Date())=>api('receiver_start',[s.test_session,d,lat,lng,accuracy,observed]);
const fetch=(s,d)=>api('receiver_fetch',[s.test_session,d]);
const reject=(fn,code)=>assert.rejects(fn,e=>e.code===code);
const claim=()=>api('push_claim',[],'service_role');
const finish=(j,result)=>api('push_finish',[j.job_id,j.claim_token,result],'service_role');
const snapshot=async()=> (await owner(`SELECT n.nspname,p.proname,pg_get_functiondef(p.oid) def,p.proacl::text acl
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='safe_walk_nearby' OR n.nspname='public' AND (left(p.proname,7)='nearby_' OR p.proname IN('set_helper_opt_in','send_emergency_alert','fetch_pending_alerts')) ORDER BY 1,2`)).rows;
let sender,helper,second,stranger,d1=token(),d2=token(),d3=token(),before,deadline,legacy;
async function send(){await owner('UPDATE safe_walk_nearby_live_test.accounts SET send_times=\'{}\' WHERE id=$1',[sender.account_id]);return api('send',[sender.test_session,25,121,crypto.randomUUID()]);}
(async()=>{
 await admin.connect();assert.equal((await admin.query('SELECT host(inet_server_addr()) h')).rows[0].h,'127.0.0.1');
 await admin.query(`CREATE DATABASE ${db}`);created=true;await c.connect();connected=true;
 await c.query(read('../../nearby_helper/local_test/00_bootstrap.sql').replace('postgis with schema extensions','postgis with schema public'));
 version=(await c.query('SELECT public.postgis_lib_version() postgis,version() postgres')).rows[0];assert.equal(version.postgis,'3.3.7');
 for(const f of ['../../nearby_helper/01_create_tables.sql','../../nearby_helper/migrations/20261107221444_allow_optional_helper_accuracy.sql','../../nearby_helper/local_test/20_upgrade_fixture.sql','../../nearby_helper/migrations/20261113010000_upgrade_nearby_backend_locked.sql','../01_install.sql','../02_enable_for_two_hours.sql'])await c.query(read(f));
 sender=await login('sender@example.invalid');helper=await login('helper@example.invalid');second=await login('helper@example.invalid');stranger=await login('stranger@example.invalid');
 await api('opt_in',[helper.test_session,'v1']);await api('report_location',[helper.test_session,25,121]);
 legacy=(await api('send',[sender.test_session,25,121,crypto.randomUUID()]))[0];
 before=await snapshot();deadline=(await owner('SELECT enabled_until FROM safe_walk_nearby_live_test.control')).rows[0].enabled_until;
 await test('atomic preflight rejects v1 privilege drift without adding objects',async()=>{
  await owner('GRANT EXECUTE ON FUNCTION public.swtest_login(text) TO PUBLIC');
  await reject(()=>owner(read('01_upgrade.sql')),'P0001');await owner('ROLLBACK');
  await owner('REVOKE EXECUTE ON FUNCTION public.swtest_login(text) FROM PUBLIC');
  assert.equal((await owner("SELECT count(*)::int n FROM pg_class WHERE relnamespace='safe_walk_nearby_live_test'::regnamespace AND relkind='r'")).rows[0].n,6);
 });
 await test('v1 populated database upgrades atomically with CRLF; push stays disabled',async()=>{
  await owner(read('01_upgrade.sql').replace(/\n/g,'\r\n'));
  const row=(await owner('SELECT push_enabled,enabled_until FROM safe_walk_nearby_live_test.control')).rows[0];assert.equal(row.push_enabled,false);assert.deepEqual(row.enabled_until,deadline);
  assert.equal(legacy.swtest_send,1);assert.equal((await api('fetch',[helper.test_session])).length,1);
 });
 await test('v2 read-only verifier passes with locked formal backend',()=>owner(read('02_verify.sql')));
 await test('old v1 verifier correctly refuses v2 instead of silently passing',()=>reject(()=>owner(read('../03_verify.sql')),'P0001'));
 await owner('ROLLBACK');
 await test('register requires session, secret device and allowed provider',async()=>{
  await reject(()=>register({test_session:'0'.repeat(64)},d1),'28000');
  await reject(()=>register(helper,d1,'https://127.0.0.1/private'),'22023');
  await register(helper,d1);await register(second,d2);await register(stranger,d3);
  await reject(()=>register(stranger,d1),'28000');await reject(()=>fetch(stranger,d1),'28000');
 });
 await test('registration alone neither opts in nor starts reception',async()=>{
  const s=(await api('receiver_status',[stranger.test_session,d3]))[0];assert.equal(s.lease_until,null);
  assert.deepEqual(await fetch(stranger,d3),[]);assert.deepEqual(await claim(),[]);
 });
 await test('freshness and accuracy enforced on server including NaN',async()=>{
  for(const [accuracy,t] of [[50,new Date()],[NaN,new Date()],[10,new Date(Date.now()-60000)],[10,new Date(Date.now()+60000)]])await reject(()=>start(helper,d1,25,121,accuracy,t),'22023');
 });
 let lease;
 await test('start clamps to 30 minutes, session and global Live deadline',async()=>{
  const t=Date.now();lease=(await start(helper,d1))[0].swtest_receiver_start;assert(Math.abs(lease.getTime()-t-1800000)<10000);
  await start(second,d2);await start(stranger,d3,24,120);
  await owner("UPDATE safe_walk_nearby_live_test.sessions SET expires_at=now()+interval '2 minutes' WHERE token_hash=extensions.digest($1,'sha256')",[stranger.test_session]);
  const short=(await start(stranger,d3,24,120))[0].swtest_receiver_start;assert(short.getTime()<Date.now()+121000);
 });
 await test('foreground update moves center but never renews the lease',async()=>{
  await owner("UPDATE safe_walk_nearby_live_test.push_devices SET reported_at=now()-interval '11 seconds' WHERE token_hash=extensions.digest($1,'sha256')",[d1]);
  await api('receiver_location',[helper.test_session,d1,25.001,121,10,new Date()]);
  const s=(await api('receiver_status',[helper.test_session,d1]))[0];assert.deepEqual(s.lease_until,lease);assert.equal(s.lat,25.001);
  await reject(()=>api('receiver_location',[helper.test_session,d1,25,121,10,new Date()]),'PT429');
 });
 let id;
 await test('IPA-compatible send queues per device, counts account once, excludes far/self',async()=>{
  await register(sender,token());
  const n=(await send())[0].swtest_send;assert.equal(n,1);
  const jobs=(await owner('SELECT * FROM safe_walk_nearby_live_test.push_outbox')).rows;assert.equal(jobs.length,2);id=jobs[0].alert_id;
  assert.equal((await fetch(helper,d1)).length,1);assert.equal((await fetch(second,d2)).length,1);assert.equal((await fetch(stranger,d3)).length,0);
  const alert=(await fetch(helper,d1))[0];assert.equal(alert.lat,25);assert.equal(alert.lng,121);assert(!('sender_id' in alert));
 });
 await test('send retry creates no duplicate push jobs',async()=>{
  const a=(await owner('SELECT request_id FROM safe_walk_nearby_live_test.alerts WHERE id=$1',[id])).rows[0];
  await api('send',[sender.test_session,25,121,a.request_id]);assert.equal((await owner('SELECT count(*)::int n FROM safe_walk_nearby_live_test.push_outbox')).rows[0].n,2);
 });
 await test('anon cannot claim queue or read subscriptions; service cannot use receiver API',async()=>{
  await reject(()=>api('push_claim'), '42501');await reject(()=>api('receiver_fetch',[helper.test_session,d1],'service_role'),'42501');
  for(const role of ['anon','authenticated','service_role']){
   await c.query(`SET ROLE ${role}`);await reject(()=>c.query('SELECT * FROM safe_walk_nearby_live_test.push_devices'),'42501');
  }
 });
 let jobs;
 await test('push switch gates worker; claims are exclusive and deadline bounded',async()=>{
  assert.deepEqual(await claim(),[]);await owner('UPDATE safe_walk_nearby_live_test.control SET push_enabled=true');
  jobs=await claim();assert.equal(jobs.length,2);assert.deepEqual(await claim(),[]);
  assert(jobs.every(j=>j.expires_at.getTime()<=Date.now()+60000));
 });
 await test('stale claim completion cannot mark accepted; transient failure schedules retry',async()=>{
  await api('push_finish',[jobs[0].job_id,crypto.randomUUID(),'accepted'],'service_role');
  assert.equal((await owner('SELECT status FROM safe_walk_nearby_live_test.push_outbox WHERE id=$1',[jobs[0].job_id])).rows[0].status,'leased');
  await finish(jobs[0],'retry');assert.deepEqual(await claim(),[]);
  await owner('UPDATE safe_walk_nearby_live_test.push_outbox SET next_attempt=now() WHERE id=$1',[jobs[0].job_id]);
  const retry=await claim();assert.equal(retry.length,1);await finish(retry[0],'accepted');
 });
 await test('stop clears only this device, cancels pending jobs and hides alerts',async()=>{
  await api('receiver_stop',[helper.test_session,d1]);assert.deepEqual(await fetch(helper,d1),[]);
  assert.equal((await fetch(second,d2)).length,1);assert.equal((await api('receiver_status',[second.test_session,d2]))[0].lease_until>new Date(),true);
 });
 await test('device logout removes its binding and jobs; other device stays bound',async()=>{
  await api('logout',[helper.test_session]);await reject(()=>fetch(helper,d1),'28000');assert.equal((await fetch(second,d2)).length,1);
 });
 await test('account opt-out revokes every receiver lease and pending delivery',async()=>{
  await api('opt_out',[second.test_session]);assert.deepEqual(await fetch(second,d2),[]);assert.equal((await api('receiver_status',[second.test_session,d2]))[0].lease_until,null);
 });
 await test('expired lease cannot update or fetch even with a valid session',async()=>{
  await start(second,d2);await owner("UPDATE safe_walk_nearby_live_test.push_devices SET lease_until=now()-interval '1 second' WHERE token_hash=extensions.digest($1,'sha256')",[d2]);
  await reject(()=>api('receiver_location',[second.test_session,d2,25,121,10,new Date()]),'42501');assert.deepEqual(await fetch(second,d2),[]);
 });
 await test('500m boundary uses PostGIS geography, not degree distance',async()=>{
  await start(second,d2);
  await owner("UPDATE safe_walk_nearby_live_test.push_devices SET geog=public.st_project(public.st_setsrid(public.st_makepoint(121,25),4326)::public.geography,501,0) WHERE token_hash=extensions.digest($1,'sha256')",[d2]);
  await owner('DELETE FROM safe_walk_nearby_live_test.locations');assert.equal((await send())[0].swtest_send,0);
  await owner("UPDATE safe_walk_nearby_live_test.push_devices SET geog=public.st_project(public.st_setsrid(public.st_makepoint(121,25),4326)::public.geography,499,0) WHERE token_hash=extensions.digest($1,'sha256')",[d2]);
  assert.equal((await send())[0].swtest_send,1);
 });
 await test('gone subscription stops reception and cancels further jobs',async()=>{
  const j=(await claim())[0];assert(j);await finish(j,'gone');assert.equal((await api('receiver_status',[second.test_session,d2]))[0].lease_until,null);
 });
 await test('global deadline also clamps a newly requested lease',async()=>{
  await owner("UPDATE safe_walk_nearby_live_test.control SET enabled_until=now()+interval '1 minute'");
  const end=(await start(second,d2))[0].swtest_receiver_start;assert(end.getTime()<=Date.now()+61000);
  await owner('UPDATE safe_walk_nearby_live_test.control SET enabled_until=$1',[deadline]);
 });
 await test('four exhausted worker claims cannot be picked forever',async()=>{
  await owner("UPDATE safe_walk_nearby_live_test.push_outbox SET status='leased',attempts=4,claimed_until=now()-interval '1 second'");
  await claim();assert.equal((await owner("SELECT count(*)::int n FROM safe_walk_nearby_live_test.push_outbox WHERE status='leased' AND attempts=4")).rows[0].n,0);
 });
 await test('verifier detects privilege drift and recovers after rollback',async()=>{
  await owner('GRANT EXECUTE ON FUNCTION public.swtest_push_claim() TO anon');
  await reject(()=>owner(read('02_verify.sql')),'P0001');await owner('ROLLBACK');
  await owner('REVOKE EXECUTE ON FUNCTION public.swtest_push_claim() FROM anon');await owner(read('02_verify.sql'));
 });
 await test('global Live expiry gates receiver, IPA send and worker without extension',async()=>{
  await owner("UPDATE safe_walk_nearby_live_test.control SET enabled_until=now()-interval '1 second'");
  await reject(()=>fetch(second,d2),'42501');await reject(()=>send(),'42501');assert.deepEqual(await claim(),[]);
 });
 await test('trusted cleanup physically removes expired locations and subscriptions',async()=>{
  await owner(read('03_cleanup.sql'));assert.equal((await owner('SELECT count(*)::int n FROM safe_walk_nearby_live_test.push_devices')).rows[0].n,0);
  assert.equal((await owner('SELECT count(*)::int n FROM safe_walk_nearby_live_test.push_outbox')).rows[0].n,0);
 });
 await test('formal function definitions/ACLs and upgrade fixture data stay unchanged',async()=>{
  assert.deepEqual(await snapshot(),before);await owner(read('../../nearby_helper/local_test/21_assert_preserved.sql'));await owner(read('02_verify.sql'));
 });
 console.log(`ALL ${results.length} PWA UPGRADE GROUPS PASSED`);
})().catch(e=>{console.error(e);process.exitCode=1;}).finally(async()=>{
 if(connected)await c.end();if(created){assert(/^nearby_upgrade_[0-9a-f]{12}$/.test(db));await admin.query(`DROP DATABASE ${db}`);}await admin.end();
 fs.writeFileSync(args[3],JSON.stringify({status:process.exitCode?'FAIL':'PASS',version,passed_groups:results.length,results,checked_at_utc:new Date().toISOString(),sha256:Object.fromEntries(['01_upgrade.sql','02_verify.sql','run_tests.cjs'].map(f=>[f,crypto.createHash('sha256').update(fs.readFileSync(path.join(__dirname,f))).digest('hex')]))},null,2)+'\n');
});
