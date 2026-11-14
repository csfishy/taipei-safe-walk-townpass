# PWA 發布與 Supabase Edge 作業流程

2026-11-14 使用者已授權：先遠端唯讀盤點，再升級既有專案、發布 PWA 並啟用 Web Push；IPA 保持發送呼救。
本文件是可重複操作流程；實際完成狀態須以當次遠端結果記錄為準，不能把此文件當部署證據。

## 固定目標與範圍

- Supabase：`gxofnhzkqcmzrftxqddi`（既有 csfishy's Project）。不得新建或切換專案。
- Pages：既有 `https://csfishy.github.io/taipei-safe-walk-townpass/`；接收器子路徑 `receiver/`。
- Edge：只部署 `nearby-push`，不使用 `--prune`，不變更 Auth／SMTP／其他 Function。
- Live 原截止：2026-11-15 23:23:10 Asia/Taipei，不因部署延期。
- 此功能仍為未驗證信箱的受控 Live 測試；正式 13 個 `nearby_*` 保持 owner-only。

## 依序操作

1. 以既有 CLI 登入執行定向唯讀 query（`--remote=gxofnhzkqcmzrftxqddi --read-only --file ...`）：
   原正式 `06_verify_locked_backend.sql`、Live v1 `03_verify.sql`、正式 `04_production_snapshot_readonly.sql`。
   再核對 deadline、PG/PostGIS、已安裝 `pg_cron`／`pg_net`／`supabase_vault`、同名 Cron／Edge 不存在。
   保存無個資／密鑰的結構與正式資料／權限摘要。讀取失敗或 drift 時停止，不能先部署。
2. 套用 `supabase/nearby_live_test/pwa/01_upgrade.sql`，重跑 v2 `02_verify.sql` 與正式 snapshot 並比對。
3. `node pwa_receiver/prepare-edge.mjs` 準備 Edge 本機副本（須與 worker 來源一致）。
4. `node pwa_receiver/deploy-prepare.mjs` 在忽略的 `.local-data/nearby-push/` 準備一次性 project-bound VAPID／scheduler token。
   重跑沿用原憑證，不輪換；絕不 print 私鑰／token、提交該目錄或把 service-role 放進網頁。
5. 只把該目錄的 `edge.env` 設到既有專案的 Edge secrets，部署單一 Function：
   `supabase functions deploy nearby-push --remote=gxofnhzkqcmzrftxqddi --use-api --yes`。
   `verify_jwt=false` 僅此函式；handler 仍要求獨立 256-bit服務憑證，拒絕公開 anon／publishable key。
   用授權 `{"mode":"health"}` 檢查 runtime／secrets；health 不 claim 或送 provider request。
6. 確認 scheduler extensions 後，執行本機生成的 `activate.sql`：Vault 儲存 dedicated token、
   10 秒一次 worker Cron、每分鐘位置／subscription 清理 Cron，最後才開 `push_enabled`。
   不在 cron command 存明文 token；只讀 Vault。兩個新 Cron 於原 Live 截止後自動取消自己，不延長期限。
7. GitHub 新增公開 variable `NEARBY_VAPID_PUBLIC_KEY`，設定 `NEARBY_PWA_ENABLED=true`；既有 `SUPABASE_URL`
   與 `SUPABASE_PUBLISHABLE_KEY` 沿用。必要 CI 通過後合併，既有 main Pages 工作流將 receiver 打包進網站。
   後續所有 Pages rebuild 會保留 receiver；IPA 呼救 RPC 與原生啟動旗標不變。
8. 發布後檢查 HTTPS receiver、manifest／SW scope／公開 config（不含私鑰）、Edge 健康狀態、
   v2 verifier、正式 snapshot，及兩個 Cron 的 schedule／active 狀態。不得以 provider accepted 冒稱 iPhone 已顯示。

## 裝置驗收（部署完成後）

1. iPhone A 繼續使用目前 IPA，以信箱 A 登入；iPhone B 用不同信箱 B，Safari 開啟已發布接收器，加入主畫面後從圖示開啟。
2. B 登入、按「啟用通知」允許通知，分別同意底圖及定位，取得誤差 ≤30m 且 15 秒內的定位。
3. B 按「開始／續收 30 分鐘」，確認 500m、到期時間與後端推播已啟用；兩機在 500m 內。
4. B 保持前景，A 發出測試呼救；確認紅點是 A 發送位置、藍點是 B 的位置與誤差圈。
5. B 前景移動 ≥10m，確認藍點更新、接收中心節流更新，但到期時間未延長。
6. B 鎖屏，A 依原限流等候後再發送；檢查鎖屏通知與一般提示音。請先關閉靜音／Focus 並允許聲音。
   點通知解鎖後開接收器地圖；過期／停止後的呼救不應顯示座標。
7. B 背景移動時沿用最後中心，回前景才重新定位；不將其當作背景追蹤。
8. 等 30 分鐘自然到期（不按續收），確認停止新接收；停止／登出只影響 B。本帳號其他裝置不登出。
   離線按停止會顯示未確認，重連後補送停止；已領取／傳送中的通知可能仍到達，但點開會重新驗權。

一般通知音量、靜音、Focus 與推播送達由 iOS 控制，非 critical alert，不保證每次鳴響。
測試不得撥打真實 110／119 或送官方通報；此 Web Push 只對同意測試的附近協助者。

官方參考：[Supabase 排程 Edge Functions](https://supabase.com/docs/guides/functions/schedule-functions)、
[函式限制](https://supabase.com/docs/guides/functions/limits)、[pg_cron 秒級排程](https://github.com/citusdata/pg_cron)。
