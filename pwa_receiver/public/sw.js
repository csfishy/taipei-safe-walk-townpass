// Separate /receiver/ scope. No GPS, auth session, coordinates or offline API cache.
self.addEventListener('install',()=>self.skipWaiting());
self.addEventListener('activate',event=>event.waitUntil(self.clients.claim()));
self.addEventListener('push',event=>{
  let data={}; try { data=event.data?.json() || {}; } catch { /* Still show a visible generic notification. */ }
  const id=typeof data.alertId==='string' && /^[0-9a-f-]{36}$/i.test(data.alertId) ? data.alertId : null;
  const expiry=Date.parse(data.expiresAt);
  const expired=Number.isFinite(expiry) && expiry<=Date.now();
  event.waitUntil(self.registration.showNotification(expired?'附近求助通知已過期':'附近有新的求助',{
    body:expired?'開啟接收器查看目前狀態。':'解鎖並開啟接收器查看有效呼救位置。',
    icon:'./icon-192.png',badge:'./icon-192.png',tag:id?`sos-${id}`:'safe-walk-sos',
    silent:false,data:{alertId:id}
  }));
});
self.addEventListener('notificationclick',event=>{
  event.notification.close();
  const url=new URL('./',self.registration.scope);
  const id=event.notification.data?.alertId;
  if(typeof id==='string' && /^[0-9a-f-]{36}$/i.test(id)) url.searchParams.set('alert',id);
  event.waitUntil((async()=>{
    const windows=await self.clients.matchAll({type:'window',includeUncontrolled:true});
    const client=windows.find(c=>new URL(c.url).origin===url.origin && new URL(c.url).pathname===url.pathname);
    if(client) { client.postMessage({type:'open-alert',alertId:id}); await client.focus(); }
    else await self.clients.openWindow(url.href);
  })());
});
