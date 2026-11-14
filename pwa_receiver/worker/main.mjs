import webpush from 'web-push';
import {dispatch} from './dispatch.mjs';
import {apiHeaders} from '../src/core.mjs';
// Standalone trusted worker; never included in web build. No deployment side effects.
const env=process.env;
if(env.PWA_PUSH_ENABLED!=='true')throw new Error('Worker locked. Explicit PWA_PUSH_ENABLED=true required.');
for(const key of ['SUPABASE_URL','VAPID_PUBLIC_KEY','VAPID_PRIVATE_KEY','VAPID_SUBJECT'])if(!env[key])throw new Error(`Missing ${key}`);
const serverKey=env.SUPABASE_SECRET_KEY || env.SUPABASE_SERVICE_ROLE_KEY;
if(!serverKey)throw new Error('Missing server-only Supabase secret/service-role key');
if(!/^https:\/\/[a-z0-9]+\.supabase\.co$/.test(env.SUPABASE_URL))throw new Error('Expected Supabase HTTPS URL');
webpush.setVapidDetails(env.VAPID_SUBJECT,env.VAPID_PUBLIC_KEY,env.VAPID_PRIVATE_KEY);
async function rpc(name,args){
  const response=await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/swtest_${name}`,{
    method:'POST',headers:apiHeaders(serverKey),
    body:JSON.stringify(args),redirect:'error',signal:AbortSignal.timeout(12000)
  });
  if(!response.ok)throw new Error(`Worker RPC HTTP ${response.status}`);
  const body=await response.text();return body?JSON.parse(body):null;
}
let running=true;process.on('SIGTERM',()=>{running=false;});process.on('SIGINT',()=>{running=false;});
while(running){
  try {const counts=await dispatch({rpc,send:(...args)=>webpush.sendNotification(...args)});if(counts.claimed)console.log(JSON.stringify(counts));}
  catch { console.error('Push worker cycle failed; no credentials, subscriptions or payloads logged.'); }
  await new Promise(resolve=>setTimeout(resolve,2000));
}
