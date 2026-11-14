import test from 'node:test';import assert from 'node:assert/strict';import vm from 'node:vm';import {readFile} from 'node:fs/promises';
import {dispatch,allowedEndpoint} from '../worker/dispatch.mjs';
import webpush from 'web-push';
import {createECDH,randomBytes} from 'node:crypto';
test('actual Web Push library builds encrypted RFC8291 request and VAPID authorization offline',()=>{
  const browserKey=createECDH('prime256v1');browserKey.generateKeys();
  const vapid=webpush.generateVAPIDKeys();
  const details=webpush.generateRequestDetails({endpoint:'https://web.push.apple.com/synthetic',keys:{
    p256dh:browserKey.getPublicKey().toString('base64url'),auth:randomBytes(16).toString('base64url')
  }},JSON.stringify({alertId:'synthetic-alert',expiresAt:'2026-11-14T01:00:00Z'}),{
    TTL:60,urgency:'high',vapidDetails:{subject:'mailto:test@example.invalid',publicKey:vapid.publicKey,privateKey:vapid.privateKey}
  });
  assert.equal(details.headers['Content-Encoding'],'aes128gcm');
  assert.match(details.headers.Authorization,/^vapid /);assert.equal(Number(details.headers.TTL),60);
  assert(Buffer.isBuffer(details.body));assert(!details.body.includes(Buffer.from('synthetic-alert')));
});
test('provider allowlist blocks credentials, private hosts, ports, fragments and redirects',()=>{
  assert(allowedEndpoint('https://web.push.apple.com/abc'));
  for(const url of ['http://web.push.apple.com/a','https://web.push.apple.com.evil.test/a','https://127.0.0.1/a','https://user@web.push.apple.com/a','https://web.push.apple.com:443/a','https://web.push.apple.com/a#b'])assert(!allowedEndpoint(url));
});
test('worker TTL bounded, generic payload, accepted never means delivered',async()=>{
  const results=[];let payload,options;
  const now=Date.now();const job={job_id:'job',claim_token:'claim',alert_id:'alert',endpoint:'https://web.push.apple.com/abc',p256dh:'key',auth:'auth',expires_at:new Date(now+99000).toISOString()};
  const counts=await dispatch({now:()=>now,rpc:async(n,a)=>n==='push_claim'?[job]:results.push(a),send:async(s,p,o)=>{payload=JSON.parse(p);options=o;return {statusCode:201};}});
  assert.equal(options.TTL,60);assert.deepEqual(Object.keys(payload),['alertId','expiresAt']);assert.equal(counts.accepted,1);assert.equal(results[0].p_result,'accepted');
});
test('worker handles gone, bounded retry, auth errors and expired jobs',async()=>{
  for(const [status,expected] of [[410,'gone'],[404,'gone'],[429,'retry'],[503,'retry'],[401,'dead']]){
    const outcomes=[];await dispatch({rpc:async(n,a)=>n==='push_claim'?[{job_id:'j',claim_token:'c',endpoint:'https://web.push.apple.com/a',expires_at:new Date(Date.now()+10000).toISOString()}]:outcomes.push(a.p_result),send:async()=>{throw {statusCode:status};}});
    assert.deepEqual(outcomes,[expected]);
  }
  let sent=false;await dispatch({rpc:async n=>n==='push_claim'?[{endpoint:'https://web.push.apple.com/a',expires_at:new Date(0).toISOString()}]:null,send:async()=>{sent=true;}});assert(!sent);
});
test('service worker always shows visible notification, default sound and safe local click target',async()=>{
  const events={},shown=[],opened=[];const self={addEventListener:(n,f)=>events[n]=f,skipWaiting(){},registration:{scope:'https://host.test/project/receiver/',showNotification:async(...a)=>shown.push(a)},clients:{claim(){},matchAll:async()=>[],openWindow:async u=>opened.push(u)}};
  vm.runInNewContext(await readFile(new URL('../public/sw.js',import.meta.url),'utf8'),{self,URL,Date});
  const id='11111111-1111-4111-8111-111111111111';let promise;
  events.push({data:{json:()=>({alertId:id,expiresAt:new Date(0).toISOString(),url:'https://evil.test'})},waitUntil:p=>promise=p});await promise;
  assert.equal(shown.length,1);assert.equal(shown[0][1].silent,false);assert(!JSON.stringify(shown).includes('evil'));
  events.notificationclick({notification:{close(){},data:{alertId:id}},waitUntil:p=>promise=p});await promise;
  assert.equal(opened[0],`https://host.test/project/receiver/?alert=${id}`);
  events.push({data:{json:()=>{throw Error();}},waitUntil:p=>promise=p});await promise;assert.equal(shown.length,2);
});
