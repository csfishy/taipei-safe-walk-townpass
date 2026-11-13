# 自填信箱的附近通知 Live 測試

2026-11-13：依使用者指定「自行輸入 e-mail 即建立／登入測試帳號，不寄驗證碼，使用既有 Supabase 專案實際測試通知」實作。**已依使用者本次確認部署至既有專案並啟用 48 小時；期限為台北時間 2026-11-15 23:23:10。** 詳見 [部署紀錄](DEPLOYMENT_20261113.md)。 不宣稱雙裝置、真 GPS 或通知送達已通過。

## 帳號及資料範圍

- 同一信箱（去除前後空白、全部轉小寫）在各裝置對應同一個測試帳號。不證明信箱所有權；任何人知道該標籤都可登入，勿輸入其他人的信箱或敏感資料。
- 這不是台北通／Supabase Auth 登入。不建立 auth.users、不取得或冒充既有會員，不以信箱或自行生成的 UUID 呼叫正式附近 RPC。
- 真正的測試帳號、短效 session、協助位置、求助及收件記錄寫入同一專案的獨立 `safe_walk_nearby_live_test` schema。API 僅呼叫 `swtest_*`，不讀寫 `safe_walk_nearby`、`crime_reference` 或 `safe_walk_demo`。
- 原正式 13 個 RPC 的 owner-only 封鎖維持原樣；舊三個 RPC 的既有權限也不由此修改。這不代表整個專案其他既有匿名入口已撤權。
- 後端以隨機 32-byte bearer token 判斷本次測試帳號，只存 token SHA-256；信箱只存以私有隨機 salt 計算的 HMAC。原始信箱只在 login POST 與本機偏好設定出現，不存後端資料表、不輸出至日誌。
- 安裝後預設停用；owner 已依本次確認開啟 48 小時窗口，到期所有測試 API 業務操作拒絕。每個 session 最長一小時且不超過窗口；原標籤可在窗口內重新登入。只可輸入本人或同意參與者的測試信箱及位置。

## 已實作流程

首次開啟顯示信箱入口及「未驗證、同信箱可被冒用」說明；明確確認後送出。可略過，略過不再反覆提示；上方保留輸入信箱入口。登入前及略過狀態無通知權限，不呼叫匿名 Auth 作為 fallback。

成功後記住信箱，重開時重新向測試後端取得 session；bearer token 僅在記憶體，不存 SharedPreferences。只有後端成功才顯示登入。後端未安裝／停用／超額／連線失敗均明確失敗，不偽造成功。

登入後進入實際 SafeWalkCompositionRoot，協助者加入、前景位置更新、SOS 發送、10 秒輪詢、去重及 App 內橫幅沿用現有流程。位置與發送仍由使用者明確操作／同意；沒有背景推播、FCM、APNs、簡訊或警方通報。守護區與聯絡人配對未在這個測試後端提供，UI 不開放其能力。

登出先卸載本裝置流程，停止其輪詢／定位生命週期，再清除本機標籤並撤銷本次 token；另一裝置的 session 不受影響。最後一個有效 session 登出時刪除該帳號位置。離線時顯示遠端撤銷未確認。協助者退出是帳號層級，會停止該帳號接收、刪位置與既有收件關係；不等同只登出一個裝置。

## 限制與保留

最多 200 個測試帳號，全專案每分鐘 30 次 login。位置更新最短 10 秒、位置有效 10 分鐘；SOS 最短 15 秒、滾動一小時最多 5 次，最多選取 500 公尺內 50 位有效測試協助者且不包含本人；求助有效 30 分鐘。相同 request ID 在原求助記錄存在期間不重複投遞；本 App 每次明確發送產生新 ID。

期限會阻止過期資料被查讀，**不是保證實體資料會即時刪除**。啟用期間 login 會順帶清除過期位置、求助及 session；窗口結束後須 owner 依核准保留方案執行清除。沒有自動建立 Cron。資料庫受託維運者仍可管理此私有 schema，HMAC 亦不代表匿名化法律判定。

這是刻意弱化信箱身分證明的公開測試介面，無 CAPTCHA／真人驗證，可被冒用、消耗額度或建立測試垃圾資料；限制人數與期限不能消除這些風險。不得當作正式會員或公開救援服務。參與者輸入的位置可能被其他使用相同信箱的人讀取，須在受控、經同意的 Live 測試中使用。

## 執行入口

原生預發版 CI 明確傳入 `SAFE_WALK_EMAIL_LIVE_TEST=true`，使用一般 `lib/main.dart` 啟動即進入官方「臺北安心行」路由的信箱測試入口；保留官方導航、獨立同意與求助 callback。未指定此旗標的 build 保持原入口；Web 永遠不選用信箱測試身分。release／profile 只有明確指定此原生測試旗標才能使用測試 transport。

合併後由既有 CI/CD 建置未簽署 arm64 IPA，自行簽署安裝即可測試，詳見 [原生預發版驗收](../../docs/SAFE_WALK_EMAIL_LIVE_PREVIEW.md)。獨立開發用 debug 入口仍可使用：

```powershell
flutter run --debug -t lib/features/safe_walk/platform/integration/email_live_test_main.dart --dart-define-from-file=artifacts/live-test-client.json
```

上述 ignored 本機設定檔需由維護者準備，只有 `SUPABASE_URL` 與 `SUPABASE_PUBLISHABLE_KEY`（或受支援的 legacy anon key），不得放 service_role／DB 密碼。此文件沒有生成實際憑證檔。

## 遠端部署與啟用順序（本次已執行；不可重跑安裝）

1. 以 [00_preflight_readonly.sql](00_preflight_readonly.sql) 唯讀確認目標專案為 `gxofnhzkqcmzrftxqddi`，PostGIS 3.3.7／public、pgcrypto／extensions；執行原 [06_verify_locked_backend.sql](../nearby_helper/06_verify_locked_backend.sql)。不以升級前四表基線判斷已部署狀態。
2. 查 `safe_walk_nearby_live_test` 及 `swtest_*` 不存在；若已有物件，停止並盤點，不覆寫。
3. 經操作當下確認後，owner 手動執行 [01_install.sql](01_install.sql)。全交易建立 6 私有表、2 私有函式及 7 測試 RPC；只開 API EXECUTE 給 anon／authenticated，資料表與私有 schema 不開直接存取。控制列預設停用。
4. 執行 [03_verify.sql](03_verify.sql) 與原正式封鎖版 verifier。驗證 RLS／ACL、函式 owner／search_path／內容雜湊；結果不得包含 salt、token、email 或位置。
5. 再執行 [02_enable_for_48_hours.sql](02_enable_for_48_hours.sql)，由 owner 設定 48 小時窗口。部署＋啟用會增加雲端存取權，本次已獲使用者操作當下確認並執行；不可自行重新執行以展延期限。原兩小時腳本保留作本機測試證據。
6. 重跑兩份 verifier；使用者在同意裝置上以兩個自行輸入的測試信箱測試。A 加入、B 主動發送、A 前景輪詢取得橫幅；確認距離、去重、登出及停用。DB 收件筆數不等於對方已看到或已送達。
7. 提早停止可執行 `UPDATE safe_walk_nearby_live_test.control SET enabled_until=NULL WHERE id;`。停止會讓既有 session 的後續業務操作全部拒絕，不刪既有記錄或退回舊匿名 RPC。

不要將以上 SQL 加入 CI、App 啟動、build 或 Demo reset。不要將既有封鎖版 SQL 改寫成啟用版。遠端部署／啟用前核對此目錄證據雜湊；使用者未同意前不呼叫真 GPS／發送通知。

## 本機驗證

`generate_verifier.py --check` 比對獨立唯讀 verifier。`run_tests.cjs` 僅接受 loopback 的隨機隔離 DB，使用 PostGIS 3.3.7，先建立原正式封鎖版與合成資料，再驗證測試 API 不影響原資料、函式與 ACL。實際結果及腳本雜湊見 [evidence/postgis-3.3.7.json](evidence/postgis-3.3.7.json)。

Flutter 測試使用 loopback HTTP 與合成信箱／人工座標；不是遠端收件或實機送達證據。新的入口／transport／Widget tests 均不更動正式帳號服務，原無 sample account 的測試契約仍適用。

本次遠端部署前後另執行 [04_production_snapshot_readonly.sql](04_production_snapshot_readonly.sql)，比較原正式八表資料與 schema／relation ACL、正式及舊三個 RPC 的函式內容／ACL 指紋；輸出一致。證據見 [48 小時部署結果](evidence/deployment-48-hours-20261113.json)。期限到期會拒絕業務 API，但不撤銷函式 EXECUTE ACL、不實體刪除測試資料。
