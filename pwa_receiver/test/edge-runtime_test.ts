import webpush from 'web-push';
import {createECDH,randomBytes} from 'node:crypto';
import {createEdgeHandler} from '../worker/edge-handler.mjs';
function assert(value:unknown){if(!value)throw new Error('Assertion failed');}
Deno.test('Deno generates real encrypted Web Push request without any network permission',()=>{
  const recipient=createECDH('prime256v1');recipient.generateKeys();const vapid=webpush.generateVAPIDKeys();
  const request=webpush.generateRequestDetails({endpoint:'https://web.push.apple.com/synthetic',keys:{
    p256dh:recipient.getPublicKey().toString('base64url'),auth:randomBytes(16).toString('base64url')
  }},'synthetic-message',{TTL:60,vapidDetails:{subject:'https://example.invalid',publicKey:vapid.publicKey,privateKey:vapid.privateKey}});
  assert(request.headers['Content-Encoding']==='aes128gcm');assert(request.body.length>0);
});
Deno.test('Deno service authentication and health perform no provider or database requests',async()=>{
  let called=false;const token='a'.repeat(64);const handler=createEdgeHandler({token,enabled:true,
    rpc:()=>{called=true;throw Error();},send:()=>{called=true;throw Error();}});
  const request=(auth:string)=>new Request('https://example.invalid',{method:'POST',headers:{Authorization:auth},body:JSON.stringify({mode:'health'})});
  assert((await handler(request('Bearer public'))).status===401);
  assert((await handler(request(`Bearer ${token}`))).status===200);assert(!called);
});
