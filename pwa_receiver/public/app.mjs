import {Receiver,Rpc,validFix,distance} from './core.mjs';
import config from './config.mjs';
const $=id=>document.getElementById(id), L=globalThis.L;
// Initial viewport is an overview, never a claimed device location.
const map=L.map('map').setView([25.04,121.54],12);
let tiles,selfMarker,accuracyCircle,zone,following=true,wanted=new URL(location.href).searchParams.get('alert');
const alertMarkers=new Map();
const controller=new Receiver({rpc:new Rpc(config),geo:navigator.geolocation,storage:localStorage,crypto:globalThis.crypto,changed:render});
$('email').value=localStorage.getItem('receiver.email') || '';
const swReady='serviceWorker' in navigator ? navigator.serviceWorker.register('./sw.js',{scope:'./',updateViaCache:'none'}).then(()=>navigator.serviceWorker.ready) : Promise.resolve(null);
swReady.catch(()=>controller.fail(new Error('Service Worker 無法啟用；請確認 HTTPS 與瀏覽器支援。')));
function text(id,value){$(id).textContent=value;}
function coord(p){return `${p.lat.toFixed(6)}, ${p.lng.toFixed(6)}`;}
function time(t){return t ? new Date(t).toLocaleTimeString('zh-TW',{hour12:false}) : '未知';}
function render(){
  text('status',controller.message);
  $('email').disabled=!!controller.token; $('login').disabled=!!controller.token;
  $('logout').disabled=!controller.token; $('notify').disabled=!controller.token;
  $('start').disabled=!controller.token || !controller.registered || !validFix(controller.fix) || controller.pendingStop;
  $('stop').disabled=!controller.registered;
  text('lease',controller.pendingStop?`停止接收尚未獲後端確認，請保持連線重試。最後已知期限：${time(controller.knownLease)}。`:controller.active?
    `接收中 · 半徑 500 公尺 · ${time(controller.lease)} 到期（剩 ${Math.ceil((controller.lease-Date.now())/60000)} 分鐘），不自動續收`:'尚未接收／接收已到期；需主動開始或續收。');
  text('push-state',controller.registered ? `鎖屏推播：${controller.pushEnabled?'後端允許（送達仍受系統與網路影響）':'後端尚未啟用'}；Live 截止：${controller.liveUntil?new Date(controller.liveUntil).toLocaleString('zh-TW'): '未知'}`:'');
  const f=controller.fix;
  text('coordinates',f?`自己的座標：${coord(f)} · 誤差約 ${Math.round(f.accuracy)} 公尺 · ${time(f.time)} 更新${validFix(f)?'':'（定位已過時或精度不足）'}`:'自己的座標：尚未取得');
  text('server-location',controller.center?`後端接收區域中心：${coord(controller.center)} · ${time(controller.lastReport)} 更新；背景沿用此區域。`:'尚未回報接收區域。');
  if(f){
    if(!selfMarker) selfMarker=L.marker([f.lat,f.lng],{icon:L.divIcon({className:'self-dot',iconSize:[20,20]})}).addTo(map).bindTooltip('自己');
    selfMarker.setLatLng([f.lat,f.lng]);
    if(!accuracyCircle) accuracyCircle=L.circle([f.lat,f.lng],{color:'#356C77',weight:1,fillOpacity:.1}).addTo(map);
    accuracyCircle.setLatLng([f.lat,f.lng]).setRadius(Number.isFinite(f.accuracy)?f.accuracy:0);
    if(following) map.setView([f.lat,f.lng],Math.max(16,map.getZoom()));
  } else {if(selfMarker) map.removeLayer(selfMarker); if(accuracyCircle)map.removeLayer(accuracyCircle); selfMarker=null;accuracyCircle=null;}
  if(zone)map.removeLayer(zone);
  zone=controller.active && controller.center ? L.circle([controller.center.lat,controller.center.lng],{radius:500,color:'#356C77',dashArray:'6',fill:false}).addTo(map) : null;
  for(const [id,marker] of alertMarkers) if(!controller.alerts.some(a=>a.alert_id===id)){map.removeLayer(marker);alertMarkers.delete(id);}
  $('alerts').replaceChildren();
  if(!controller.alerts.length) text('alerts',wanted?'此呼救已過期、尚未登入接收帳號，或不在此裝置的有效接收紀錄內。':'目前沒有有效呼救。');
  for(const a of controller.alerts){
    if(!alertMarkers.has(a.alert_id)) alertMarkers.set(a.alert_id,L.marker([a.lat,a.lng],{icon:L.divIcon({className:'sos-dot',iconSize:[24,24]})}).addTo(map).bindTooltip('呼救位置'));
    const card=document.createElement('div');card.className='alert-card';
    const p=document.createElement('p');p.textContent=`呼救位置：${coord(a)} · ${time(a.created_at)} 發送 · ${time(a.expires_at)} 到期${f?` · 距自己約 ${Math.round(distance(f,a))} 公尺`:''}`;
    const button=document.createElement('button');button.textContent='查看此呼救';button.onclick=()=>{following=false;map.setView([a.lat,a.lng],17);alertMarkers.get(a.alert_id).openTooltip();};
    card.append(p,button);$('alerts').append(card);
    if(wanted===a.alert_id){wanted=null;button.click();}
  }
  text('map-note',f?'藍點：自己 · 紅點：呼救位置 · 虛線圈：後端接收範圍':'目前為臺北概覽，尚未取得自己的位置。');
}
const run=fn=>Promise.resolve().then(fn).catch(e=>controller.fail(e));
$('login-form').onsubmit=e=>{e.preventDefault();run(async()=>controller.login($('email').value,await (await swReady)?.pushManager.getSubscription()));};
$('notify').onclick=()=>{
  // Invoke subscribe directly in this gesture; do not await GPS/network first.
  const ios=/iPhone|iPad|iPod/.test(navigator.userAgent);
  if(ios && !matchMedia('(display-mode: standalone)').matches && !navigator.standalone){controller.fail(new Error('請先加入主畫面，並從主畫面開啟接收器。'));return;}
  if(!('PushManager' in globalThis) || !('Notification' in globalThis)){controller.fail(new Error('此瀏覽器不支援 Web Push；iPhone 需 iOS 16.4 以上並加入主畫面。'));return;}
  if(!config.vapidPublicKey){controller.fail(new Error('尚未設定 Web Push 公開金鑰；本次尚未部署。'));return;}
  const worker=navigator.serviceWorker?.controller;
  if(!worker){controller.fail(new Error('接收器尚未準備完成，請稍後再按啟用通知。'));return;}
  const key=Uint8Array.from(atob(config.vapidPublicKey.replace(/-/g,'+').replace(/_/g,'/')),c=>c.charCodeAt(0));
  // Registration was initialized at startup. getRegistration is async; retain it below.
  if(!registration){controller.fail(new Error('通知服務尚未準備完成，請稍後重試。'));return;}
  const subscription=registration.pushManager.subscribe({userVisibleOnly:true,applicationServerKey:key});
  run(async()=>{await controller.register(await subscription);controller.message='通知已啟用；請定位並主動開始接收。';render();});
};
let registration=null;swReady.then(r=>{registration=r;}).catch(()=>{});
$('map-consent').onchange=()=>{
  if($('map-consent').checked){tiles=L.tileLayer(config.tileUrl || 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',{maxZoom:19,attribution:'© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'}).addTo(map);tiles.on('tileerror',()=>text('map-note','底圖暫時無法載入；座標仍可查看。'));}
  else if(tiles){map.removeLayer(tiles);tiles=null;}
};
$('locate').onclick=()=>run(()=>{
  if(!$('location-consent').checked)throw new Error('請先同意前景定位及接收期間位置回報。');
  following=true;controller.locate();
});
$('location-consent').onchange=()=>{if(!$('location-consent').checked){controller.tracking=false;controller.clearWatch();if(controller.registered)run(()=>controller.stop());}};
$('start').onclick=()=>run(async()=>{if(!$('location-consent').checked)throw new Error('請先同意定位及位置回報。');await controller.start();await controller.refresh();});
$('stop').onclick=()=>run(()=>controller.stop());
$('logout').onclick=()=>run(()=>controller.logout());
$('follow').onclick=()=>{following=true;render();};
$('fit').onclick=()=>{const positions=controller.alerts.map(a=>[a.lat,a.lng]);if(controller.fix)positions.push([controller.fix.lat,controller.fix.lng]);if(positions.length){following=false;map.fitBounds(positions,{padding:[35,35],maxZoom:17});}};
map.on('dragstart',()=>{following=false;});
document.addEventListener('visibilitychange',()=>controller.visibility(!document.hidden));
addEventListener('pagehide',()=>controller.visibility(false));
addEventListener('pageshow',()=>controller.visibility(!document.hidden));
addEventListener('online',()=>run(()=>controller.refresh()));
navigator.serviceWorker?.addEventListener('message',e=>{if(e.data?.type==='open-alert'){wanted=e.data.alertId;run(()=>controller.refresh());}});
setInterval(()=>controller.tick(),1000);
setInterval(()=>{if(!document.hidden)run(async()=>{await controller.report();await controller.refresh();});},10000);
render();
