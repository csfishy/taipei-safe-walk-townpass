import webpush from 'web-push';
import {createEdgeHandler} from './edge-handler.mjs';
const get=(name:string)=>Deno.env.get(name) || '';
const url=get('SUPABASE_URL');
const key=get('SUPABASE_SERVICE_ROLE_KEY');
const publicKey=get('NEARBY_VAPID_PUBLIC_KEY'),privateKey=get('NEARBY_VAPID_PRIVATE_KEY');
const subject=get('NEARBY_VAPID_SUBJECT');
const enabled=get('NEARBY_PUSH_ENABLED')==='true' && !!url && !!key && !!publicKey && !!privateKey && !!subject;
if(enabled)webpush.setVapidDetails(subject,publicKey,privateKey);
async function rpc(name:string,args:Record<string,unknown>){
  const response=await fetch(`${url}/rest/v1/rpc/swtest_${name}`,{
    method:'POST',headers:{apikey:key,Authorization:`Bearer ${key}`,'Content-Type':'application/json'},
    body:JSON.stringify(args),signal:AbortSignal.timeout(12000),redirect:'error'
  });
  if(!response.ok)throw new Error('worker_rpc_failed');
  const body=await response.text();return body?JSON.parse(body):null;
}
// Generate the real encrypted RFC8291 request with the reviewed library; use
// Edge-native fetch rather than Node HTTPS sockets or a resident Node daemon.
async function send(subscription:unknown,payload:string,options:Record<string,unknown>){
  const request=webpush.generateRequestDetails(subscription,payload,options);
  const response=await fetch(request.endpoint,{method:request.method,headers:request.headers,
    body:new Uint8Array(request.body),signal:AbortSignal.timeout(10000),redirect:'error'});
  if(!response.ok)throw {statusCode:response.status};
  await response.body?.cancel();return {statusCode:response.status};
}
Deno.serve(createEdgeHandler({token:get('NEARBY_PUSH_CRON_TOKEN'),enabled,rpc,send,
  log:(counts:unknown)=>console.log(JSON.stringify(counts))}));
