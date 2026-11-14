import test from 'node:test';
import assert from 'node:assert/strict';
import {Receiver,validFix,Rpc,apiHeaders} from '../src/core.mjs';
const time=Date.parse('2026-11-14T00:00:00Z');
test('new Supabase API keys are not passed as JWT Authorization',()=>{
  for(const key of ['sb_publishable_synthetic','sb_secret_synthetic'])assert.equal(apiHeaders(key).Authorization,undefined);
  assert.equal(apiHeaders('legacy.jwt.value').Authorization,'Bearer legacy.jwt.value');
});
function setup(){
  let now=time,callback,cleared=0;const calls=[],stored=new Map();
  const storage={getItem:k=>stored.get(k)||null,setItem:(k,v)=>stored.set(k,v),removeItem:k=>stored.delete(k)};
  const rpc={call:async(name,args)=>{calls.push({name,args});
    if(name==='receiver_start')return new Date(now+1800000).toISOString();
    if(name==='receiver_status')return [{lease_until:new Date(time+1800000).toISOString(),push_enabled:false,live_until:new Date(time+3600000).toISOString(),lat:25,lng:121,reported_at:new Date(now).toISOString()}];
    if(name==='login')return [{test_session:'a'.repeat(64),expires_at:new Date(time+3600000).toISOString()}];
    return [];
  }};
  const c=new Receiver({rpc,storage,crypto:globalThis.crypto,now:()=>now,geo:{watchPosition:cb=>{callback=cb;return 7;},clearWatch:()=>cleared++}});
  c.token='a'.repeat(64);c.expires=time+3600000;c.registered=true;
  const fix=(lat=25)=>({lat,lng:121,accuracy:10,time:now});
  return {c,calls,rpc,stored,setNow:v=>{now=v;},fix,emit:()=>callback({coords:{latitude:25.001,longitude:121,accuracy:10},timestamp:now}),cleared:()=>cleared};
}
test('fix gate rejects stale, coarse, absent, future and nonfinite values',()=>{
  const f={lat:25,lng:121,accuracy:10,time};assert(validFix(f,time));
  for(const change of [{accuracy:50},{accuracy:null},{lat:NaN},{lng:181},{time:time-15001},{time:time+5001}])assert(!validFix({...f,...change},time));
});
test('foreground movement reports center without renewing lease; throttle 10s',async()=>{
  const s=setup();s.c.fix=s.fix();await s.c.start();const end=s.c.lease;
  s.setNow(time+11000);s.c.fix=s.fix(25.001);await s.c.report();
  assert.equal(s.c.center.lat,25.001);assert.equal(s.c.lease,end);
  s.c.fix=s.fix(25.002);await s.c.report();assert.equal(s.calls.filter(x=>x.name==='receiver_location').length,1);
});
test('background clears only watcher and retains last reception center',async()=>{
  const s=setup();s.c.fix=s.fix();await s.c.start();s.c.locate();s.c.visibility(false);
  assert.equal(s.c.watch,null);assert.equal(s.c.center.lat,25);assert(s.c.active);assert.equal(s.cleared(),2);
  s.emit();assert.equal(s.c.fix.lat,25);s.setNow(time+11000);await s.c.report();
  assert.equal(s.calls.filter(x=>x.name==='receiver_location').length,0);
});
test('30-minute expiry suppresses fetch, location and old alert coordinates',async()=>{
  const s=setup();s.c.fix=s.fix();await s.c.start();s.c.alerts=[{alert_id:'x',expires_at:new Date(time+3600000).toISOString()}];
  s.setNow(time+1800000);s.c.tick();await s.c.report();assert(!s.c.active);assert.deepEqual(s.c.alerts,[]);
});
test('offline stop remains pending in storage, never reports success',async()=>{
  const s=setup();s.c.lease=time+1800000;s.rpc.call=async()=>{throw Error('offline');};
  await assert.rejects(s.c.stop());assert(s.c.pendingStop);assert(!s.c.active);assert.equal(s.stored.get('receiver.pendingStop'),'true');
});
test('manual refresh restarts one watcher instead of accumulating watchers',()=>{
  const s=setup();s.c.locate();s.c.locate();assert.equal(s.cleared(),1);assert.equal(s.c.watch,7);
});
test('starting again after stop resumes foreground GPS even while the previous fix is fresh',async()=>{
  const s=setup();s.c.fix=s.fix();await s.c.start();await s.c.stop();
  assert.equal(s.c.watch,null);assert.equal(s.c.tracking,false);
  await s.c.start();assert.equal(s.c.watch,7);assert.equal(s.c.tracking,true);
  s.emit();assert.equal(s.c.fix.lat,25.001);
});
test('pending offline stop replays before lease restoration',async()=>{
  const s=setup();s.c.pendingStop=true;s.stored.set('receiver.pendingStop','true');
  s.rpc.call=async(name,args)=>{s.calls.push({name,args});if(name==='receiver_status')return [{lease_until:null,lat:null,lng:null,push_enabled:false}];};
  await s.c.register({endpoint:'https://web.push.apple.com/test',keys:{p256dh:'key',auth:'auth'}});
  assert.deepEqual(s.calls.map(c=>c.name),['receiver_register','receiver_stop','receiver_status']);assert(!s.c.active);assert(!s.c.pendingStop);
});
test('stop serializes behind an in-flight start; late start never revives UI',async()=>{
  const s=setup();s.c.fix=s.fix();let resolve;const order=[];
  s.rpc.call=async name=>{order.push(name);if(name==='receiver_start')return await new Promise(r=>resolve=r);};
  const start=s.c.start();await new Promise(r=>setImmediate(r));const stop=s.c.stop();
  resolve(new Date(time+1800000).toISOString());await Promise.all([start,stop]);
  assert.deepEqual(order,['receiver_start','receiver_stop']);assert.equal(s.c.lease,0);assert(!s.c.pendingStop);
});
test('bad GPS never writes reception center; failed update preserves last center',async()=>{
  const s=setup();s.c.fix=s.fix();await s.c.start();s.setNow(time+11000);s.c.fix={...s.fix(25.001),accuracy:50};await s.c.report();assert.equal(s.c.center.lat,25);
  s.c.fix=s.fix(25.001);s.rpc.call=async()=>{throw Error('offline');};await assert.rejects(s.c.report());assert.equal(s.c.center.lat,25);
});
test('tokens remain memory-only; logout revokes current session only',async()=>{
  const s=setup();await s.c.logout();assert.equal(s.c.token,null);assert.deepEqual(s.calls.map(c=>c.name),['receiver_stop','logout']);
  assert(!JSON.stringify([...s.stored]).includes('a'.repeat(64)));
});
test('RPC uses only anon authorization and sanitizes errors',async()=>{
  let options;const rpc=new Rpc({supabaseUrl:'https://example.supabase.co',anonKey:'public'},async(_,o)=>{options=o;return {ok:false,json:async()=>({message:'secret location backend trace'})};});
  await assert.rejects(rpc.call('receiver_fetch',{}),/後端拒絕/);assert.equal(options.cache,'no-store');assert.equal(options.headers.Authorization,'Bearer public');
});
