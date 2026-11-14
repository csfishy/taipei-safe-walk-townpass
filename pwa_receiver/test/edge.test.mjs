import test from 'node:test';import assert from 'node:assert/strict';
import {createEdgeHandler} from '../worker/edge-handler.mjs';
const token='a'.repeat(64);
const request=(auth=`Bearer ${token}`,body={})=>new Request('https://project.supabase.co/functions/v1/nearby-push',{
  method:'POST',headers:{Authorization:auth,'Content-Type':'application/json'},body:JSON.stringify(body)});
test('cloud worker denies public keys, missing auth and missing dedicated secret',async()=>{
 let called=false;const handler=createEdgeHandler({token,enabled:true,rpc:async()=>{called=true;},send:async()=>{}});
 for(const auth of ['', 'Bearer sb_publishable_synthetic','Bearer '+'b'.repeat(64)])assert.equal((await handler(request(auth))).status,401);
 assert.equal(called,false);
 assert.equal((await createEdgeHandler({token:'',enabled:true})(request())).status,503);
});
test('authorized cloud health check performs no claim or provider request',async()=>{
 let called=false;const handler=createEdgeHandler({token,enabled:true,rpc:async()=>{called=true;},send:async()=>{called=true;}});
 const response=await handler(request(undefined,{mode:'health'}));assert.equal(response.status,200);assert.equal(called,false);
});
test('cloud worker runs real dispatch contract and reports only aggregate counts',async()=>{
 const calls=[];const handler=createEdgeHandler({token,enabled:true,rpc:async(n,a)=>{calls.push(n);return n==='push_claim'?[]:null;},send:async()=>{throw Error();}});
 const response=await handler(request());assert.equal(response.status,200);assert.deepEqual(calls,['push_claim']);assert.equal((await response.json()).claimed,0);
 assert.equal((await createEdgeHandler({token,enabled:false})(request())).status,503);
});
