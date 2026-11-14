import test from 'node:test';import assert from 'node:assert/strict';
import {createServer} from 'node:http';import {readFile,mkdir} from 'node:fs/promises';import path from 'node:path';import {fileURLToPath} from 'node:url';
import {chromium} from '@playwright/test';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../../artifacts/pwa');
test('mobile browser: map-first, own + SOS markers, movement, expiry, stop and local SW scope',async()=>{
 const server=createServer(async(req,res)=>{
  const url=new URL(req.url,'http://localhost');
  if(url.pathname.endsWith('/config.mjs')){res.setHeader('Content-Type','text/javascript');res.end(`export default ${JSON.stringify({supabaseUrl:'https://fixture.supabase.co',anonKey:'synthetic-public-key',vapidPublicKey:'B'.repeat(87)})}`);return;}
  const relative=url.pathname.replace('/project/','');const target=path.resolve(root,relative.endsWith('/')?relative+'index.html':relative);
  if(!target.startsWith(root+path.sep)){res.writeHead(403);res.end();return;}
  try {const body=await readFile(target);res.setHeader('Content-Type',({'.mjs':'text/javascript','.js':'text/javascript','.css':'text/css','.webmanifest':'application/manifest+json','.html':'text/html','.png':'image/png'})[path.extname(target)]||'application/octet-stream');res.end(body);}
  catch{res.writeHead(404);res.end();}
 });
 await new Promise(r=>server.listen(0,'127.0.0.1',r));
 const browser=await chromium.launch(process.platform==='win32'?{channel:'chrome',headless:true}:{headless:true});
 const context=await browser.newContext({viewport:{width:390,height:844},permissions:['geolocation','notifications'],geolocation:{latitude:25,longitude:121,accuracy:10}});
 const page=await context.newPage(),calls=[],errors=[];page.on('pageerror',e=>errors.push(e.message));
 page.on('console',m=>{if(m.type()==='error')console.error('Browser console:',m.text());});
 let lease=null,lat=25,lng=121,reportTime=null;const aid='11111111-1111-4111-8111-111111111111';
 await page.addInitScript(()=>{
  const sub={endpoint:'https://web.push.apple.com/synthetic',keys:{p256dh:'B'.repeat(87),auth:'A'.repeat(22)}};
  PushManager.prototype.subscribe=function(){return Promise.resolve({toJSON:()=>sub});};
  PushManager.prototype.getSubscription=function(){return Promise.resolve(null);};
 });
 await page.route('https://fixture.supabase.co/**',async route=>{
  const req=route.request(),name=req.url().split('swtest_')[1],args=req.postDataJSON();calls.push({name,args});let body=null;
  if(name==='login')body=[{test_session:'a'.repeat(64),expires_at:new Date(Date.now()+3600000).toISOString()}];
  if(name==='receiver_start'){lease=new Date(Date.now()+1800000).toISOString();lat=args.p_lat;lng=args.p_lng;reportTime=new Date().toISOString();body=lease;}
  if(name==='receiver_location'){lat=args.p_lat;lng=args.p_lng;reportTime=new Date().toISOString();}
  if(name==='receiver_stop')lease=null;
  if(name==='receiver_status')body=[{lease_until:lease,lat:lease?lat:null,lng:lease?lng:null,reported_at:reportTime,push_enabled:false,live_until:new Date(Date.now()+3600000).toISOString()}];
  if(name==='receiver_fetch')body=lease?[{alert_id:aid,lat:25.002,lng:121.002,created_at:new Date().toISOString(),expires_at:new Date(Date.now()+1800000).toISOString()}]:[];
  await route.fulfill({status:200,contentType:'application/json',body:JSON.stringify(body)});
 });
 try {
  await page.clock.install();
  const url=`http://127.0.0.1:${server.address().port}/project/receiver/`;
  await page.goto(url);await page.waitForSelector('.leaflet-container');
  assert.equal(calls.length,0);assert.equal(await page.locator('.self-dot').count(),0);
  await page.waitForFunction(()=>navigator.serviceWorker.controller!==null);
  const scope=await page.evaluate(async()=> (await navigator.serviceWorker.getRegistration()).scope);assert.equal(scope,url);
  await page.locator('#email').fill('helper@example.invalid');await page.locator('#login').click();await page.waitForFunction(()=>document.getElementById('email').disabled);
  await page.locator('#notify').click();await page.waitForFunction(()=>document.getElementById('status').textContent.includes('通知已啟用'));
  await page.locator('#location-consent').check();await page.locator('#locate').click();await page.waitForSelector('.self-dot');
  await page.locator('#start').click();await page.waitForSelector('.sos-dot');assert.equal(calls.filter(x=>x.name==='receiver_start').length,1);
  assert.match(await page.locator('#coordinates').textContent(),/25\.000000, 121\.000000/);
  await page.waitForTimeout(11000);await context.setGeolocation({latitude:25.001,longitude:121,accuracy:10});
  await page.waitForFunction(()=>document.getElementById('coordinates').textContent.includes('25.001000'));
  await page.waitForFunction(()=>document.getElementById('server-location').textContent.includes('25.001000'));
  assert.equal(calls.filter(x=>x.name==='receiver_start').length,1);assert(calls.some(x=>x.name==='receiver_location'));
  await mkdir(path.join(root,'../pwa-evidence'),{recursive:true});
  await page.screenshot({path:path.join(root,'../pwa-evidence/active-mobile.png'),fullPage:true});
  // Advance only after GPS assertions; native geolocation has a real clock.
  await page.clock.setSystemTime(new Date(Date.now()+1801000));await page.clock.runFor(1100);
  assert.equal(await page.locator('.sos-dot').count(),0);
  assert.match(await page.locator('#lease').textContent(),/接收已到期/);
  // Revoke and ensure both the marker and any previously returned coordinates vanish.
  await page.locator('#stop').click();await page.waitForFunction(()=>document.getElementById('status').textContent.includes('已停止'));
  assert.equal(await page.locator('.sos-dot').count(),0);assert(!((await page.locator('#alerts').textContent()).includes('25.002')));
  await page.locator('#logout').click();await page.waitForFunction(()=>!document.getElementById('email').disabled);
  const stored=await page.evaluate(()=>JSON.stringify(localStorage));assert(!stored.includes('a'.repeat(64)));
  await page.screenshot({path:path.join(root,'../pwa-evidence/mobile.png'),fullPage:true});
  assert.deepEqual(errors,[]);
 } catch(error){console.error('Browser failure diagnostics:',await page.locator('#status').textContent(),JSON.stringify(calls.map(c=>c.name)),errors);throw error;}
 finally {await context.close();await browser.close();await new Promise(r=>server.close(r));}
});
