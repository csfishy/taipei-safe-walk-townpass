# 本機實作與驗證紀錄 — 2026-11-14

**WIRED_NOT_VERIFIED**；不代表已部署、已接真實 push provider 或已通過 iPhone 鎖屏驗收。
實作範圍為獨立 PWA 地圖接收器、Supabase v1→v2 migration、唯讀 verifier、trusted Node Web Push worker、清理 SQL 與測試。
現有 IPA 發送 API 簽名保留。沒有發布頁面、推送分支、改遠端設定、延長 Live、寄信或送推播。

| 檢查 | 實際結果 |
|---|---|
| PWA `npm run build` | PASS；輸出本機 `/receiver/`，預設無遠端設定 |
| PWA `npm test` | **20 PASS / 0 fail / 0 skip** |
| PostGIS 3.3.7 v1→v2 upgrade | **26 組 PASS**；PG 15.13 x86_64 Alpine 拋棄式 DB |
| 原 v1 Live backend 回歸 | **30 組 PASS**；同一本機 PostGIS 3.3.7 環境、另一個拋棄式 DB |
| v2 verifier `--check`、SQL／verifier／runner SHA256 | PASS；與已保存的升級結果一致 |
| 原正式 migration／verifier SHA256 | PASS；與既有不可變版本相同 |
| `npm audit --omit=dev --audit-level=moderate` | 0 vulnerabilities（當次 registry 結果） |
| canonical contracts `--check` | PASS |
| TownPass history／正常 module boundaries guard | PASS |
| crime reference isolation | PASS；未開啟外部犯罪資料庫 |
| `git diff --check` | PASS |

瀏覽器測試以本機 Chrome、390×844 viewport、人工位置與攔截的 Supabase 回應驗證：
開啟即地圖、無自動定位／登入、通知按鈕、自己與呼救標記、前景移動回報不續期、到期清除呼救座標、停止／登出、無 session 持久化、獨立 SW scope、零 JS page errors。
Service Worker 測試涵蓋可見通知、一般系統提示音選項與同源安全開啟；實際 `web-push` 套件離線產出 AES128GCM 加密封裝與 VAPID Authorization，未向 provider 發 request。
另驗證離線 stop journal、重連補送、停止與 in-flight start 競態、provider 410／429／5xx、TTL、任意 endpoint 拒絕及前端禁止 server secrets。

升級測試由已有人／位置／呼救資料的 v1 升級，含 CRLF；權限 drift 會在交易內拒絕且不留新增表。
驗證 500m geography 邊界、30m／session／global 截止、每裝置 ownership／多裝置隔離、舊 IPA 相容、sender 排除、idempotent outbox、服務端精度／時間限制、worker ACL／claim／retry、帳號 opt-out、清理與正式函式／ACL／fixture 不變。
可攜式結果與當次 SQL hash 在 [PostGIS evidence](../supabase/nearby_live_test/pwa/evidence/postgis-3.3.7.json)。

本機忽略產物：`artifacts/pwa/receiver/`、`artifacts/pwa-evidence/tests.log`、`active-mobile.png`、`mobile.png`、`artifacts/pwa-compat/v1-regression.json`。
截圖是人工位置；未同意載入外部底圖，故顯示地圖畫布／標記，非真實位置或實機推播證據。
新增 GitHub workflow 僅定義 check、不含部署；**尚未推送或執行遠端 CI**。
既有本機 GPS／原生前景提示音改動保留，未混入此 PWA 提交。

部署後仍須驗收：真實 Supabase PG17.11／aarch64、APNs Web Push provider、兩台 iPhone 的主畫面安裝／鎖屏通知／聲音／Focus／拒絕權限，及 30 分鐘自然到期。
此步驟遵照「暫不部署」保留，不能以本機 fixture、加密封裝或 Chrome 通過替代。
