export function allowedEndpoint(endpoint) {
  return typeof endpoint==='string' && endpoint.length<=2048 &&
    /^https:\/\/(?:(?:[a-z0-9-]+\.)*push\.apple\.com\/[^?#\s]+|fcm\.googleapis\.com\/fcm\/send\/[^?#\s]+|updates\.push\.services\.mozilla\.com\/wpush\/v2\/[^?#\s]+)$/.test(endpoint);
}
export async function dispatch({rpc,send,now=Date.now}) {
  const jobs=await rpc('push_claim',{});
  const counts={claimed:jobs.length,accepted:0,retry:0,dead:0,gone:0};
  // All claims complete within the 30s DB claim lease (10s provider + 12s RPC).
  // Sequential sends could let later claims expire and be sent by two workers.
  await Promise.all(jobs.map(async job=>{
    let result='dead';
    const ttl=Math.min(60,Math.floor((Date.parse(job.expires_at)-now())/1000));
    if(allowedEndpoint(job.endpoint) && ttl>0){
      try {
        const response=await send({endpoint:job.endpoint,keys:{p256dh:job.p256dh,auth:job.auth}},
          JSON.stringify({alertId:job.alert_id,expiresAt:job.expires_at}),
          {TTL:ttl,urgency:'high',timeout:10000});
        result=response.statusCode>=200 && response.statusCode<300 ? 'accepted' : 'dead';
      } catch(error){
        result=[404,410].includes(error.statusCode)?'gone':
          (!error.statusCode || error.statusCode===429 || error.statusCode>=500)?'retry':'dead';
      }
    }
    await rpc('push_finish',{p_job_id:job.job_id,p_claim_token:job.claim_token,p_result:result});
    counts[result]++;
  }));
  return counts;
}
