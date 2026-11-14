# 臺北安心行 PWA 協助者接收器

後續授權更新：使用者已要求遠端唯讀確認後部署、發布與啟用 Web Push；部署順序與兩台 iPhone 步驟見 [DEPLOYMENT.md](DEPLOYMENT.md)。
遠端唯讀盤點、v2 升級、Supabase Edge 工作器與 Web Push 啟用已完成；啟用後 verifier PASS，正式資料／函式／ACL 指紋一致。網站發布以 CI 的實際部署狀態為準，iPhone 鎖屏顯示與聲音仍待裝置驗收。後端證據見 [deployment-backend-20261114.json](../supabase/nearby_live_test/pwa/evidence/deployment-backend-20261114.json)。
下文「暫不部署」記錄的是最初實作回合的授權與驗證邊界。

狀態：**WIRED_NOT_VERIFIED**（程式已接線；本機合成資料驗證，尚未部署／實機 Web Push 驗收）。
使用者 2026-11-14 確認流程並授權實作與隔離測試，**暫不部署**。本次沒有遠端設定、寄信、推播、Live 延期或帳號申請。
主責 M1 小魚，涉及 platform/UI、Supabase Level B/C；IPA 保持既有 `swtest_send`。

## 已確認流程

開啟 `/receiver/` 即顯示地圖；初始臺北概覽不是使用者位置。輸入任意測試信箱登入（未驗證，可被冒用）；
信箱只作測試帳號標籤，與 IPA 沿用相同私有 HMAC 帳號資料，沒有 Supabase Auth signup 或 SMTP。
兩台測試手機須使用不同信箱，後端排除自己帳號。

1. iPhone iOS 16.4+ 用 Safari 加入主畫面，從主畫面開啟。
2. 登入 → 明確點「啟用通知」。訂閱在點擊事件中直接請求，不等待 GPS 或 RPC 後才請求。
3. 底圖另行同意載入 OSM；前景定位／接收期間回報位置也有獨立同意。
4. 「取得／更新我的位置」開啟唯一前景 watcher。藍點＋誤差圈＋座標／時間；背景清除 watcher，回前景重新啟動。
5. 合格定位（15 秒內，誤差 ≤30m，未來容差 5 秒）才可「開始／續收 30 分鐘」。服務端再次驗證。
6. Supabase 維護每裝置的半徑 500m、最長 30 分鐘 lease；受登入期限與現有 Live 截止時間共同限制。
7. 前景每個 GPS 更新即更新藍點；後端最多每 10 秒一次，移動 ≥10m 或距上次回報 ≥60 秒才回報。
   更新不續期。灰色／失敗定位保留最後合格接收區域並顯示時間，不建立假位置。
8. 背景／鎖屏沿用最後區域；移動 1km 也不會自動跟隨，直至回前景取得新位置或到期。
9. IPA 發送 → 500m 內有效裝置進 durable outbox → trusted worker → Web Push → Service Worker 顯示一般通知。
   通知不帶信箱、帳號、座標、session 或裝置密鑰。提示音交由 OS，不能繞過靜音／Focus，不能保證送達。
10. 點通知回接收器地圖；登入後重新查詢此裝置的有效呼救。紅點為發送時座標，藍點為目前自身位置。
    已過期／未授權不顯示呼救座標；可切換多筆呼救、查看時間、座標、直線距離與全部標記。

停止只影響本裝置，停止定位、刪除後端接收中心、取消未完成工作；登出再撤銷本登入 session，其他裝置不受影響。
既有 IPA 的「退出協助者」是帳號層級，會撤銷此帳號所有 PWA lease。已被 worker 領取／開始傳送或 provider 接受的通知仍可能到達；點開仍重新驗權，不因此暴露已撤銷的座標。
離線停止持久記錄 pending stop，顯示最後已知期限；重連／重新登入後先補送停止，不自動恢復接收。
密碼／OTP 無；登入 token 僅記憶體。localStorage 保存信箱、隨機裝置密鑰、停止狀態與期限，沒有座標或呼救資料。
同源 XSS、未驗證信箱冒用仍是此測試模式的限制，不能轉作正式救援身分。

## 本機建置與驗證

Node 22+（本機 Node 26.13），從此目錄：

```sh
npm ci --ignore-scripts
npm run build
npm test
```

`npm test` 含 Chromium 手機尺寸流程：Windows 使用已安裝 Chrome；Linux 先 `npx playwright install --with-deps chromium`。
所有瀏覽器 Supabase 回應攔截為人工測試資料，GPS 是人工測試位置，不是 Live 證據。
預設輸出 `../artifacts/pwa/receiver`，未配置會明確顯示不可用，不默認啟用任何既有專案。
最終 public config（另建本機 JSON；不可提交秘密）欄位：

```json
{"supabaseUrl":"https://PROJECT.supabase.co","anonKey":"PUBLIC_ANON_OR_PUBLISHABLE_KEY","vapidPublicKey":"PUBLIC_VAPID_KEY"}
```

```sh
node build.mjs --config /local/public-config.json --out /local/site/receiver
```

只接受公開 anon／publishable key，拒絕 service-role/secret key。VAPID 私鑰永不進網頁。
Leaflet 固定版本並打包本機資產與授權，不由 CDN 載入程式。沿用官方圖示與 TPColors 對應色碼。
SW、manifest id、scope、start URL 全部相對於 `/receiver/`，不攔截既有 Flutter app；無 fetch handler、無敏感 API／圖磚快取。
OSM 底圖使用標準 HTTPS tile URL、可見署名與瀏覽器 Referer／HTTP 快取，不預抓或離線下載。

## 後端與工作器（尚未部署）

見 [v2 升級與 verifier](../supabase/nearby_live_test/pwa/README.md)。增加 `push_devices`、`push_outbox` 私有 RLS 表；
6 個 receiver RPC；2 個 service-role-only worker RPC；裝置密鑰 hash／session／account 共同驗 ownership。
每帳號最多 5 個 PWA 裝置。沿用舊登入與 SOS 限流、50 個不同帳號接收上限及 sender 排除。
原有 native location 10 分鐘 TTL 不延長；PWA 使用獨立 lease。v1 immutable SQL 不改寫。

工作器為可獨立運作的 Node 程序，`npm run worker`；需以下 server-only 環境變數：
`PWA_PUSH_ENABLED=true`, `SUPABASE_URL`, `SUPABASE_SECRET_KEY`（或既有 `SUPABASE_SERVICE_ROLE_KEY`）, `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT`。
依 [Supabase API keys](https://supabase.com/docs/guides/getting-started/api-keys)，新 publishable／secret key 只放 `apikey`；legacy JWT 才同時作 Bearer。
本次不產生／設定正式 VAPID 私鑰，未提供任何遠端憑證。DB 的 `push_enabled` 也須另行明確核准啟用，migration 預設 false。
每 2 秒原子 claim 最多 20 件，併行送出；10 秒網路逾時、30 秒 claim lease、最多 4 次嘗試及指數退避。
provider TTL ≤60 秒且不超過 lease/session/Live 截止；404/410 停用裝置，429/5xx/網路失敗重試。
只允許 Apple/FCM/Mozilla 指定 HTTPS provider endpoint，禁止任意 URL／私網 SSRF；不跟隨 HTTP redirect。
工作器只記 aggregate 計數，不記密鑰、endpoint、帳號或位置。accepted 是 provider 接受，不代表螢幕已顯示／人已看見。
claim 逾期後重試屬 at-least-once；同 alert/device 的 outbox UNIQUE 與通知 tag 避免建立重複紀錄／堆疊通知，不能保證 provider exactly-once。

尚待部署後驗收：兩台實體 iPhone、加入主畫面、權限拒絕／恢復、實際鎖屏顯示與聲音、Focus／靜音、背景移動保留區域、
回前景定位、30 分鐘自然到期、停止／登出及 provider 410。Windows Chrome 通過不等於 iOS Web Push 已驗收。

## 部署前邊界

目前所有變更停留本機。既有 Live 截止 **2026-11-15 23:23:10 Asia/Taipei** 不自動延期。
後續須另行授權：遠端唯讀 drift check、v2 migration、verifier、HTTPS 接收器發布、工作器／VAPID secrets、
清理排程與推播開關啟用。現有 CI 沒有加入本接收器的發布步驟；本機建置不會部署。

官方依據：[Apple Web Push](https://developer.apple.com/documentation/usernotifications/sending-web-push-notifications-in-web-apps-and-browsers)、
[MDN foreground geolocation](https://developer.mozilla.org/en-US/docs/Web/API/Geolocation/watchPosition)、
[OSM tile policy](https://operations.osmfoundation.org/policies/tiles/)。
