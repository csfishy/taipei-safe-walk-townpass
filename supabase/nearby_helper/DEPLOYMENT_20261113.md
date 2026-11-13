# 2026-11-13：完整後端已部署，通知保持封鎖

**結果：已部署 owner-only 後端，遠端唯讀 verifier PASS；新版通知未啟用，R13 仍為 BLOCKED。**
目標為既有 Supabase 專案 `gxofnhzkqcmzrftxqddi`，透過已登入的 Dashboard SQL Editor 手動執行。使用者本輪明確授權：「請先重新唯讀確認遠端結構沒有變更，再將通過驗證的 migration 部署到既有 Supabase 專案，部署後執行 verifier，先不要啟用通知。」

## 實際遠端結果（Asia/Taipei）

| 階段 | 結果 |
|---|---|
| 15:57:35 第一次唯讀基線檢查 | PASS；四表、20 欄、12 約束、6 索引、RLS／ACL、extension schema／版本與三個舊 RPC 的內容／權限符合原盤點 |
| 16:11:42 重試前唯讀基線檢查 | PASS；確認第一次失敗交易及 metadata 診斷均已回滾，沒有留下部分升級 |
| 實際環境 | PostgreSQL 17.11／aarch64、PostGIS 3.3.7 在 public、pgcrypto 1.3 在 extensions，operator 為 postgres |
| 封鎖版 migration | SQL Editor 回 `Success. No rows returned`；交易內完整 postconditions 通過後 COMMIT |
| 16:15:08.957329 獨立唯讀驗證 | `DEPLOYED_LOCKED_VERIFIED`；8 張私有表、13 個 public RPC、API 有效 EXECUTE 權限合計 0 |

完整 verifier 同時驗證 37 欄、26 個約束、索引、FK、owner、RLS／零 policy、函式參數／結果／defaults／SECURITY DEFINER／空 search_path／內容雜湊與有效／原始 ACL，並確認私有 `purge_expired()` 不授權 API 執行。驗證只查 metadata，沒有呼叫業務通知 RPC 或查讀使用者位置／聯絡人／通知內容。

可讀取的[部署收據](local_test/evidence/remote-deployment-20261113.json)保留實際觀察、時間與腳本 SHA-256。UI 截圖保存在本機 ignored artifacts，未加入 App 或版本控制。本輪未使用 `apply_migration`，腳本也沒有寫入 Supabase migration history；不宣稱有遠端 migration history version。

## 為什麼採 owner-only 版本

原 [20261113000000 升級來源](migrations/20261113000000_upgrade_nearby_backend.sql)包含 authenticated EXECUTE grant，直接部署即可能透過 API 呼叫通知，不符合「先不要啟用通知」。本輪部署的是：

- [20261113010000_upgrade_nearby_backend_locked.sql](migrations/20261113010000_upgrade_nearby_backend_locked.sql)：保留相同 14 個函式內容及資料升級行為，移除 13 個 public RPC 的 API EXECUTE grant，提交前檢查全部 API 角色仍無有效執行權。
- [06_verify_locked_backend.sql](06_verify_locked_backend.sql)：獨立唯讀 verifier，要求 owner-only ACL。
- [07_postdeploy_readonly.sql](07_postdeploy_readonly.sql)：先完整執行上述 verifier，再以額外唯讀 catalog 查詢回傳數量、權限合計與伺服器時間。
- [05_predeploy_readonly.sql](05_predeploy_readonly.sql)：部署前的精確基線／舊 RPC 比對，只讀 metadata。

原來源及其 [18 組 PostGIS 3.3.7 證據](local_test/evidence/postgis-3.3.7.json)保持原樣。本輪另有 [11 組封鎖／CRLF 升級測試](local_test/evidence/postgis-3.3.7-locked.json)全部通過，涵蓋非空資料保留、三角色所有 RPC 拒絕、誤授權偵測、重複升級回滾、CRLF 傳輸，以及真正函式內容被更動時仍會被拒絕。

產生器 [generate_locked_deployment.py](local_test/generate_locked_deployment.py)先核對原來源與 18 組證據的 SHA-256，再衍生 owner-only SQL，並斷言 14 個函式內容完全相同。可用 `--check` 核對產物；本機測試入口是 [run_locked_tests.cjs](local_test/run_locked_tests.cjs)。

## 部署時修正的格式差異

第一次交易被提交前 verifier 擋下：Windows 編輯器傳入 CRLF，PostgreSQL 的 `prosrc` 保留該換行，導致原始 MD5 不同。回滾後唯讀查得仍為 4 表、0 個新版 RPC。另一次明確以 ROLLBACK 結尾的 metadata 診斷確認，將 CRLF 正規化為 LF 後，函式內容 digest 與已驗證來源相同，其他 metadata 也一致。

本輪只在封鎖版的 verifier／postconditions 將 `md5(prosrc)` 改為 `md5(replace(prosrc, E'\r\n', E'\n'))`。沒有忽略 SQL tokens、其他空白或註解；測試確認實質更動函式仍被拒絕。修正後以 CRLF 實際送入 PostGIS 3.3.7 的隔離測試全部通過，再重新唯讀確認遠端基線後部署。

最終腳本 SHA-256（以 LF 檔案計算，UI 全文亦比對一致）：

```text
locked migration ffd39808b374b8e95dfe5e85c64c715b868b1be64d3741fb9f834065c8c254ba
locked verifier  83ef6647b23986e237b9191f9095071b45c781cd0603ba0f0388a80f1eb56064
postdeploy SQL   827c1059da91cdd51722562ff884f8ddeee9d4d810ee61d529ebd734effd027a
```

SQL 來源檔保留先前階段的 `NOT DEPLOYED` 註解以維持測試／部署內容的雜湊證據；**本文件是這次實際部署狀態的紀錄**。

## 沒有啟用的能力及後續限制

新版 13 個 RPC 與私有清除函式，對 PUBLIC／anon／authenticated／service_role 均保持禁止執行；只有可信 owner 可操作。沒有發送求助、建立 Auth 測試身分、調整匿名登入／CAPTCHA、建立 Cron job、啟用 FCM／APNs 或修改 App 開關。沒有更動其他業務 schema。

舊 `set_helper_opt_in`／`send_emergency_alert`／`fetch_pending_alerts` 的既有匿名執行權限未由本 migration 調整；本輪「未啟用通知」指新版後端保持封鎖，不能解讀成已退役所有舊通知管道。舊 RPC 的退役、伺服器資格／防濫用、資料保留排程、Auth 設定與雙裝置送達驗收仍待另行完成。

部署後不要重跑任何初次建表或四表升級腳本，也不要用原四表 `02_verify.sql`／啟用版 `04_verify_backend.sql` 判斷現況；它們會依其舊契約拒絕新狀態。現行唯讀檢查應使用 `06_verify_locked_backend.sql` 或 `07_postdeploy_readonly.sql`。尚未授權或實作正式啟用；不以部署／verifier PASS 宣稱 LIVE_VERIFIED。
