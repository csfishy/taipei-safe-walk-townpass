export const RADIUS = 500;
// New publishable/secret keys belong only in apikey, not JWT Authorization.
export function apiHeaders(key) {
  return {apikey:key,'Content-Type':'application/json',
    ...(key.startsWith('sb_publishable_') || key.startsWith('sb_secret_') ? {} : {Authorization:`Bearer ${key}`})};
}
export function validFix(f, now = Date.now()) {
  return !!f && Number.isFinite(f.lat) && Math.abs(f.lat) <= 90 &&
    Number.isFinite(f.lng) && Math.abs(f.lng) <= 180 && Number.isFinite(f.accuracy) &&
    f.accuracy >= 0 && f.accuracy <= 30 && Number.isFinite(f.time) &&
    now - f.time <= 15000 && f.time - now <= 5000;
}
export function distance(a, b) {
  const rad = x => x * Math.PI / 180;
  const h = Math.sin(rad(b.lat-a.lat)/2)**2 + Math.cos(rad(a.lat))*Math.cos(rad(b.lat))*Math.sin(rad(b.lng-a.lng)/2)**2;
  return 6371000 * 2 * Math.asin(Math.sqrt(Math.min(1,h)));
}
export function deviceToken(crypto) {
  return Array.from(crypto.getRandomValues(new Uint8Array(32)), x=>x.toString(16).padStart(2,'0')).join('');
}
export class Rpc {
  constructor(config, fetcher = (...args)=>fetch(...args)) { this.config=config; this.fetcher=fetcher; }
  async call(name, args={}) {
    const {supabaseUrl,anonKey}=this.config;
    if (!supabaseUrl || !anonKey) throw new Error('接收器尚未配置 Supabase，請聯絡維護者。');
    let response;
    try {
      response=await this.fetcher(`${supabaseUrl}/rest/v1/rpc/swtest_${name}`, {
        method:'POST', headers:apiHeaders(anonKey),
        body:JSON.stringify(args),cache:'no-store',signal:AbortSignal.timeout(12000),redirect:'error'
      });
    } catch { throw new Error('後端連線失敗；未確認的操作不視為成功。'); }
    if (!response.ok) {
      const data=await response.json().catch(()=>({}));
      const messages={live_test_disabled:'Live 測試尚未啟用或已結束。',invalid_test_session:'登入已到期，請重新登入。',
        invalid_device:'裝置綁定失效，請重新登入。',invalid_fix:'需 15 秒內、誤差 30 公尺內的定位。',
        receiver_expired:'接收期限已到或已停止，請重新定位並主動續收。',rate_limited:'操作過於頻繁，請稍後重試。',
        device_limit:'此帳號已達 5 台接收裝置上限。'};
      const error=new Error(messages[data.message] || '後端拒絕操作，請確認部署與設定。');
      error.code=data.message; throw error;
    }
    const body=await response.text(); return body ? JSON.parse(body) : null;
  }
}
// Only this controller owns the foreground watcher. Never runs in a worker.
export class Receiver {
  constructor({rpc,geo,storage,crypto,now=Date.now,changed=()=>{}}) {
    Object.assign(this,{rpc,geo,storage,crypto,now,changed});
    this.token=null; this.expires=0; this.lease=0; this.fix=null; this.center=null;
    this.alerts=[]; this.message='請登入並主動取得定位。'; this.watch=null; this.epoch=0;
    this.visible=true; this.tracking=false; this.reporting=false; this.fetching=false; this.lastReport=0;
    this.writes=Promise.resolve();
    this.device=storage.getItem('receiver.device') || deviceToken(crypto);
    storage.setItem('receiver.device',this.device);
    this.pendingStop=storage.getItem('receiver.pendingStop')==='true';
    this.knownLease=Number(storage.getItem('receiver.leaseUntil')) || 0;
  }
  get active() { return !!this.token && this.now()<this.expires && this.now()<this.lease && !this.pendingStop; }
  args(extra={}) { return {p_test_session:this.token,p_device_token:this.device,...extra}; }
  write(name,args) {
    const request=this.writes.catch(()=>{}).then(()=>this.rpc.call(name,args));
    this.writes=request; return request;
  }
  fixArgs() { const f=this.fix; return {p_lat:f.lat,p_lng:f.lng,p_accuracy:f.accuracy,p_observed_at:new Date(f.time).toISOString()}; }
  async login(email, subscription) {
    const normalized=email.trim().toLowerCase();
    if(normalized.length>254 || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(normalized)) throw new Error('請輸入有效的 e-mail。');
    if(this.token) throw new Error('請先登出再切換帳號。');
    const epoch=++this.epoch;
    const [row]=await this.rpc.call('login',{p_email:normalized});
    if(epoch!==this.epoch) return;
    this.token=row.test_session; this.expires=Date.parse(row.expires_at);
    this.storage.setItem('receiver.email',normalized);
    this.message='已登入測試帳號；尚未開始接收。';
    if(subscription) await this.register(subscription);
    this.changed();
  }
  async register(subscription) {
    if(!this.token) throw new Error('請先登入。');
    const epoch=this.epoch;
    const sub=subscription.toJSON ? subscription.toJSON() : subscription;
    await this.write('receiver_register',this.args({p_endpoint:sub.endpoint,p_p256dh:sub.keys.p256dh,p_auth:sub.keys.auth}));
    if(epoch!==this.epoch) return;
    this.registered=true;
    // A failed offline stop is replayed before restoring any active lease.
    if(this.pendingStop) await this.stop();
    await this.status();
  }
  locate() {
    if(!this.geo) throw new Error('此瀏覽器無法提供定位。');
    this.tracking=true; this.clearWatch(); this.startWatch();
  }
  startWatch() {
    if(!this.tracking || !this.visible || this.watch!==null) return;
    this.watch=this.geo.watchPosition(p=>{
      if(!this.tracking || !this.visible) return;
      this.fix={lat:p.coords.latitude,lng:p.coords.longitude,accuracy:p.coords.accuracy,time:p.timestamp};
      this.message=validFix(this.fix,this.now()) ? '自己的位置已更新。' : '定位精度不足；接收區域仍沿用最後有效位置。';
      this.changed(); this.report().catch(e=>this.fail(e));
    },()=>this.fail(new Error('無法更新定位，請檢查定位權限及精確位置；保留最後有效接收區域。')),
    {enableHighAccuracy:true,maximumAge:0,timeout:12000});
  }
  visibility(visible) {
    this.visible=visible;
    if(!visible) this.clearWatch(); else { this.startWatch(); this.refresh().catch(e=>this.fail(e)); }
  }
  clearWatch() { if(this.watch!==null) this.geo.clearWatch(this.watch); this.watch=null; }
  async start() {
    if(this.pendingStop) throw new Error('請先連線確認停止接收，再開始新的接收期間。');
    if(!this.registered) throw new Error('請先啟用通知並完成裝置綁定。');
    if(!validFix(this.fix,this.now())) throw new Error('請先取得 15 秒內、誤差 30 公尺內的定位。');
    const epoch=this.epoch, fix={...this.fix};
    const deadline=await this.write('receiver_start',this.args(this.fixArgs()));
    if(epoch!==this.epoch || this.pendingStop) return;
    this.lease=Date.parse(deadline); this.center=fix; this.lastReport=this.now();
    this.knownLease=this.lease; this.storage.setItem('receiver.leaseUntil',String(this.lease));
    this.message='已開始接收：半徑 500 公尺；30 分鐘內到期，不自動續收。'; this.changed();
  }
  async report() {
    if(!this.visible || !this.active || this.reporting || !validFix(this.fix,this.now())) return;
    const elapsed=this.now()-this.lastReport;
    if(elapsed<10000 || (this.center && distance(this.center,this.fix)<10 && elapsed<60000)) return;
    const epoch=this.epoch,fix={...this.fix}; this.reporting=true;
    try {
      await this.write('receiver_location',this.args(this.fixArgs()));
      if(epoch===this.epoch && this.active) { this.center=fix; this.lastReport=this.now(); this.changed(); }
    } finally { this.reporting=false; }
  }
  async status() {
    const epoch=this.epoch; const [s]=await this.rpc.call('receiver_status',this.args());
    if(epoch!==this.epoch || this.pendingStop) return;
    this.lease=s.lease_until ? Date.parse(s.lease_until) : 0;
    this.knownLease=this.lease; this.storage.setItem('receiver.leaseUntil',String(this.lease));
    this.pushEnabled=s.push_enabled; this.liveUntil=Date.parse(s.live_until);
    this.center=s.lat===null ? null : {lat:s.lat,lng:s.lng};
    this.lastReport=s.reported_at ? Date.parse(s.reported_at) : 0;
    this.changed();
  }
  async refresh() {
    this.tick();
    if(!this.token || !this.registered || !this.visible || this.fetching) return;
    this.fetching=true; const epoch=this.epoch;
    try {
      if(this.pendingStop) await this.stop();
      await this.status();
      const rows=this.active ? await this.rpc.call('receiver_fetch',this.args()) : [];
      if(epoch===this.epoch && this.active) this.alerts=rows.filter(r=>Date.parse(r.expires_at)>this.now());
      else this.alerts=[];
      this.changed();
    } finally { this.fetching=false; }
  }
  tick() {
    if(!this.active) this.alerts=[];
    else this.alerts=this.alerts.filter(r=>Date.parse(r.expires_at)>this.now());
    if(this.token && this.now()>=this.expires) {
      this.token=null; this.registered=false; this.lease=0; this.epoch++; this.message='登入已到期，請重新登入。';
    }
    this.changed();
  }
  async stop() {
    this.epoch++; this.pendingStop=true; this.storage.setItem('receiver.pendingStop','true');
    this.lease=0; this.alerts=[]; this.tracking=false; this.clearWatch();
    this.message='正在向後端確認停止接收。'; this.changed();
    await this.write('receiver_stop',this.args());
    this.pendingStop=false; this.storage.removeItem('receiver.pendingStop'); this.center=null;
    this.knownLease=0; this.storage.removeItem('receiver.leaseUntil');
    this.message='此裝置已停止接收。已被工作器領取或推播服務接受的通知仍可能到達。'; this.changed();
  }
  async logout() {
    if(this.registered) await this.stop();
    if(this.token) await this.rpc.call('logout',{p_test_session:this.token});
    this.epoch++; this.token=null; this.registered=false; this.alerts=[]; this.lease=0;
    this.tracking=false; this.clearWatch(); this.fix=null; this.center=null;
    this.storage.removeItem('receiver.email'); this.message='已登出本裝置。'; this.changed();
  }
  fail(error) { this.message=error.message; this.changed(); }
}
