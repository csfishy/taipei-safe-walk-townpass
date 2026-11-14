import test from 'node:test';import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';import {mkdtemp,writeFile,rm,mkdir} from 'node:fs/promises';
import path from 'node:path';import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
test('browser build rejects server/VAPID private configuration and service-role JWT',async()=>{
 const parent=path.join(root,'../artifacts/config-tests');await mkdir(parent,{recursive:true});const folder=await mkdtemp(path.join(parent,'case-'));
 try {
  for(const config of [{vapidPrivateKey:'synthetic-private'},{anonKey:'sb_secret_synthetic'},
    {anonKey:`e30.${Buffer.from(JSON.stringify({role:'service_role'})).toString('base64url')}.signature`}]){
   const file=path.join(folder,'config.json');await writeFile(file,JSON.stringify(config));
   const result=spawnSync(process.execPath,[path.join(root,'build.mjs'),'--config',file,'--out',path.join(folder,'receiver')],{encoding:'utf8'});
   assert.notEqual(result.status,0);assert.match(result.stderr,/Only public|Server credentials|Only anon/);
  }
 } finally {await rm(folder,{recursive:true,force:true});}
});
test('worker is disabled without explicit enablement, before reading any credentials',()=>{
 const result=spawnSync(process.execPath,[path.join(root,'worker/main.mjs')],{encoding:'utf8',env:{...process.env,PWA_PUSH_ENABLED:'false'}});
 assert.notEqual(result.status,0);assert.match(result.stderr,/Worker locked/);
});
test('CI public configuration builds receiver scope without bundling worker or private credentials',async()=>{
 const parent=path.join(root,'../artifacts/config-tests');await mkdir(parent,{recursive:true});const folder=await mkdtemp(path.join(parent,'ci-'));
 try {
  const result=spawnSync(process.execPath,[path.join(root,'build-from-env.mjs'),'--out',path.join(folder,'receiver')],{
    encoding:'utf8',env:{...process.env,SUPABASE_URL:'https://fixture.supabase.co',SUPABASE_PUBLISHABLE_KEY:'sb_publishable_synthetic',NEARBY_VAPID_PUBLIC_KEY:'B'.repeat(87),NEARBY_VAPID_PRIVATE_KEY:'must-not-be-in-web'}});
  assert.equal(result.status,0,result.stderr);
  const fs=await import('node:fs/promises'),config=await fs.readFile(path.join(folder,'receiver/config.mjs'),'utf8');
  assert(config.includes('sb_publishable_synthetic'));assert(!config.includes('must-not-be-in-web'));
  await assert.rejects(fs.access(path.join(folder,'receiver/worker')));
 } finally {await rm(folder,{recursive:true,force:true});}
});
