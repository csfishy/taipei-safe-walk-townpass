import {dispatch} from './dispatch.mjs';
// Dedicated service-to-service token; browser publishable keys never authorize.
export function createEdgeHandler({token,enabled,rpc,send,log=(_counts)=>{}}) {
  return async request=>{
    if(request.method!=='POST')return new Response('Method not allowed',{status:405});
    const supplied=request.headers.get('Authorization') || '';
    if(!token || !/^[0-9a-f]{64}$/.test(token))return new Response('Unavailable',{status:503});
    const digest=async value=>new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value)));
    const [a,b]=await Promise.all([digest(supplied),digest(`Bearer ${token}`)]);
    let mismatch=0;for(let i=0;i<a.length;i++)mismatch|=a[i]^b[i];
    if(mismatch)return new Response('Unauthorized',{status:401});
    if(!enabled)return Response.json({enabled:false},{status:503});
    try {
      const body=await request.json();
      if(body.mode==='health')return Response.json({ready:true});
      const counts=await dispatch({rpc,send});log(counts);
      return Response.json(counts);
    } catch {return Response.json({error:'worker_cycle_failed'},{status:503});}
  };
}
