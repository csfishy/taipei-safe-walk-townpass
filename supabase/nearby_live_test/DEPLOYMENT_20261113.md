# 48 小時 Live 測試部署紀錄

使用者操作當下確認：部署到既有 Supabase 專案，啟用 **48 小時**，執行 verifier 並確認正式後端權限及資料不受影響。本次未要求預先指定測試信箱。

- 專案：`gxofnhzkqcmzrftxqddi`，csfishy's Project／main PRODUCTION。
- 實際啟用：2026-11-13 15:23:10.845667 UTC（台北時間 2026-11-13 23:23:10）。
- 到期：2026-11-15 15:23:10.845667 UTC（台北時間 **2026-11-15 23:23:10**）。
- 結果：`LIVE_TEST_CONTRACT_VERIFIED`，`test_enabled=true`。
- 結構：6 張私有表、2 個私有函式、7 個 `public.swtest_*` RPC。測試帳號、位置、求助及收件關係均與正式資料隔離。

## 實際操作與驗證

使用 computer-use 技能經 Supabase Dashboard SQL Editor 手動執行；沒有使用 CLI push，也沒有宣稱新增 Supabase migration history 記錄。

1. 執行 [00_preflight_readonly.sql](00_preflight_readonly.sql)：原完整正式後端 verifier 通過、PostGIS 3.3.7、pgcrypto/extensions、測試 schema 與測試 RPC 尚不存在，結果 `READY_FOR_LIVE_TEST_INSTALL`。
2. 執行 [04_production_snapshot_readonly.sql](04_production_snapshot_readonly.sql) 保存正式資料與權限指紋。原正式八張表全部為 0 筆；只取得筆數／摘要，不輸出資料內容。
3. 安裝 [01_install.sql](01_install.sql)，與既有 30 組相容性測試證據的檔案 SHA-256 一致。Dashboard 靜態預檢未辨識 DO 迴圈內的 RLS，操作審查拒絕「Run without RLS」。改採平台提供的 **Run and enable RLS** 安全選項後成功；未跳過審查或停用 RLS。
4. 執行 [03_verify.sql](03_verify.sql)，通過六表 RLS／ACL、函式內容雜湊、owner／search_path、7 個測試 API 的授權及私有函式隔離檢查。此時 `enabled_until=NULL`、`test_enabled=false`。
5. 執行原 [06_verify_locked_backend.sql](../nearby_helper/06_verify_locked_backend.sql)，並以 [48 小時啟用腳本](02_enable_for_48_hours.sql) 將 COMMIT 改為 ROLLBACK 做期限交易測試。腳本內斷言 deadline 必須精確等於交易時間加 48 小時；測試通過後，重跑測試 verifier 仍為停用。這是在遠端既有 PostGIS 3.3.7 環境上的期限驗證，沒有呼叫測試帳號／位置／發送 RPC。
6. 正式執行 48 小時啟用腳本並 COMMIT，得到上述啟用／到期時間。此腳本與原兩小時版本分開保存，沒有改寫原 30 組測試的歷史證據。
7. 啟用後連續執行原正式封鎖版 verifier 與測試 verifier，均通過。
8. 重跑正式資料／權限快照，以程式比對部署前後輸出完全一致。正式八表的各筆數及資料摘要一致，正式 schema／relation ACL 摘要一致，原 13 個正式 RPC、私有 purge 及舊三個 RPC 的函式內容／ACL 摘要一致。

正式 13 個 RPC 仍為 owner-only；未解鎖既有正式通知功能。舊三個 RPC 的原有權限保持原樣，本次未替它們撤權，也不宣稱那些舊入口已安全封鎖。未修改 Supabase Auth、SMTP、正式身分或正式通知路徑。

可追溯的結果、檔案 SHA-256 及前後指紋：[deployment-48-hours-20261113.json](evidence/deployment-48-hours-20261113.json)。啟用後 verifier 及正式資料／權限快照的畫面保存在本機忽略的 artifacts 目錄，未提交至版本庫。

## 測試入口與停止方式

依 [README 的原生 debug 入口](README.md#執行入口)啟動 App，參與者自行輸入信箱；不需驗證碼。App 使用真實 Supabase 測試 RPC。通知是既有前景輪詢與 App 內橫幅，沒有啟用 FCM／APNs／背景推播、簡訊、信件或官方派遣。

本次部署當時僅執行後端部署、啟用及 verifier 驗證，**沒有執行真 GPS、雙裝置或通知送達驗收**。後續原生預發版已依使用者要求接到一般 main／官方路由，見 [原生預發版](../../docs/SAFE_WALK_EMAIL_LIVE_PREVIEW.md)；不可將後端 verifier PASS 解讀為裝置已收到求助。

要提早停止，由 owner 手動執行：

```sql
UPDATE safe_walk_nearby_live_test.control
SET enabled_until = NULL WHERE id;
```

到期或提早停止會拒絕測試業務 API；不需排程才能到期，但不會自動撤銷 EXECUTE ACL 或刪除實體資料。資料清理由 owner 另行依核准範圍處理。不可自行重跑啟用腳本展延期限。

任何人知道同一測試信箱都可以登入該測試身分；只供已同意參與者在受控 Live 測試使用，不作為正式信箱所有權或會員資格證明。
