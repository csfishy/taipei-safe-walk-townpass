# TownPass Supabase 連線設定

## 2026-11-08：原生犯罪查詢發布修正

本節記錄使用者授權「方案 1」的修正；下方舊基線及部署狀態保留為歷史，不代表現在的犯罪查詢介面仍不存在。

第 163 次原生發布（main `f9154b0`）沒有帶入 Supabase 編譯設定，導致犯罪 Repository 未配置。M3 設定按鈕先關閉面板，再無提示地返回，因此看起來沒有反應。修正後，Android／iOS 建置從 Actions variable `SUPABASE_URL` 與 secret `SUPABASE_PUBLISHABLE_KEY` 產生暫存 dart-defines，使用 App 同一驗證器拒絕缺值與管理金鑰。後者仍是可供 App 使用的 **publishable key**，存為 secret 僅用於遮罩日誌；沒有設定 DB 密碼、service_role 或管理 token。

原生封裝會檢查預期公開設定確實存在於 Flutter AOT 程式；缺設定時不可發布。這個檢查只證明編譯注入，不代替後端可用性或裝置驗收。Web 的既有預設關閉行為、附近通知封鎖及 Demo reset 均未因本修正啟用。操作方式見 [原生建置](BUILDS.md)。舊版 App 需安裝新建置，重新登入無法改變已編譯的設定。

實際唯讀驗證使用既有專案 `gxofnhzkqcmzrftxqddi` 的公開 client key，沿正式 `CrimeReferenceWiring` → native HTTP → Repository → parser：

| 檢查 | 2026-11-08 結果 |
|---|---|
| 無位置、limit 1 查詢 | 成功；快照 `5ea3810c-5744-4b89-baad-0121c8fc951b`，2,542 筆來源紀錄、10 個來源 |
| 臺北市、limit 200 查詢 | 成功；符合 617 筆，本頁 200 筆中 182 筆有參考座標；不是全市完整頁面 |
| 私有 schema 暴露檢查 | 公開 client 指定 `Accept-Profile: crime_reference` 的零筆讀取被 406／PGRST106 拒絕 |
| 真實 RPC → Flutter 地圖 | Opt-in 測試 1 項通過；2 次真實查詢產生 17 個參考標記及 17 個 50 公尺產品緩衝，來源與精度標籤通過。人工起終點、隔離路線／TTS／儲存邊界，0 次裝置 GPS；不代表 iPhone 實機驗收 |

遠端 `safe_walk_crime_reference_query` 已存在。本次沒有執行 SQL 部署、初始化、匯入、reset，亦沒有改動資料或 DB 權限。上述筆數是來源紀錄，並非去重案件數；有座標也不代表精確案發點。

可明確重跑的唯讀工具（不可把設定值貼到日誌）：

```text
dart tool/check_crime_reference.dart secrets/supabase.local.json
dart tool/check_crime_reference.dart secrets/supabase.local.json --city 臺北市 --require-coordinates
```

地圖驗收另以環境變數 `SAFE_WALK_CRIME_LIVE_CONFIG` 指定本機設定檔，再執行 `flutter test --no-pub test/features/safe_walk/platform/integration/crime_reference_live_map_acceptance_test.dart`；未設定時明確 skip，不讀本機設定或連網。它只在記憶體消費真實公開紀錄，選取有參考座標的紀錄後建立人工行程範圍，驗證同意後的查詢、來源標示與地圖圈，不存下原始回應。完成後移除這個環境變數，避免日常完整測試意外執行遠端驗收。

第一個命令只查一筆、不傳位置；第二個只傳城市名稱，不取得 GPS 或傳送行程。工具只輸出快照識別、日期和筆數，不輸出個別紀錄、地址、座標或金鑰。這些結果不等於 iPhone 實機驗收；正式裝置仍須確認設定對話框、同意後重新規劃、標示詳情與撤回清除。犯罪標示沿用 **50 公尺產品避讓緩衝**，不是官方犯罪邊界或安全保證。

## 歷史基線與隔離政策

示範資料庫 migrations／seed、重設腳本與相關 CI 工作已移除。建置及發布不連線或重設遠端資料庫；既有持久犯罪參考資料及隔離保護不變。

現行規格依 [LIVE-FIRST／NO PRODUCTION MOCK](SAFE_WALK_LIVE_FIRST.md)、[Live MVP](SAFE_WALK_LIVE_MVP.md) 與 [上線條件](SAFE_WALK_LIVE_READINESS.md)。2026-11-08 的 main `7b99fea` 仍是 Mock 正式入口，#35 的 P0 接線已由 #49 restore 移除；#39 僅合入 feature branch，#44 仍開放，不能列為主線已完成。正式持久資料以 Supabase 主資料庫為整合方向，必須接到完整使用者查詢／更新流程，不能只交連線 probe 或 Parser。

Production 不注入 Mock／fixtures、固定成功或失敗後模擬 fallback；未完成為 Unavailable＋真實原因＋下一步。Supabase client API 可達不等於已具業務授權。管理 key、service_role、資料庫密碼不得進 App；正式唯讀存取、身分／RPC／RLS、敏感位置儲存仍需適用 Level C 審查與驗收，不能為追求 Live 直接放寬權限。既有 `gxofnhzkqcmzrftxqddi` 不視為可清除 Demo。main `752dd96` 已合併 #47，遠端重設須明確啟用，本文件不配置或啟用任何遠端環境。

| 能力 | 狀態 | 現行結論 |
|---|---|---|
| Supabase client／唯讀連線診斷 | IMPLEMENTED_NOT_WIRED | Config、connection probe 與 transport factory 已存在；需明確呼叫，沒有自動接入產品通知流程。歷史唯讀連線成功只證明 Data API 可達。 |
| M4／Supabase 正式持久資料 API 與 UI 流程 | IMPLEMENTED_NOT_WIRED | #55 已合併唯讀 Repository、Parser、RPC SQL 與獨立檢查入口；正式 UI、遠端權限套用與完整驗收仍待完成。#44 持久庫隔離另經審查；權限啟用未驗部分維持 BLOCKED。 |
| 附近協助者位置通知 | BLOCKED | 匿名 UUID／anon security-definer RPC 缺可信身分、接收資格、ownership 與防濫用；不能因參數已設定就啟用。 |

附近協助者通知與正式警消通報分別驗收。上述 BLOCKED 不阻擋合法的真實導航、資料查詢、裝置 TTS、使用者主動開啟 110／119 系統撥號器或官方通報管道；自動警消派遣仍須官方授權。各能力獨立啟用，不能以全域 Mock 長期鎖住已驗證功能。本次規格 PR 不部署 SQL、不開啟附近通知。

## 歷史：原連線設定與驗證

以下至文末保留原 `99d4135` 設定及後續 `03f98f2` 查核的 SHA、操作與 20/20 測試結果，不是本輪重跑、現在遠端狀態或附近通知驗收。PR #25 已合併，不表示業務流程完成；Production 不得因此沿用 Mock。配置說明不授權新增權限、執行通知 SQL 或讀寫真實使用者資料。

2026-11-07（Asia/Taipei）。本輪依使用者明確要求，為目前 TownPass Flutter App 設定 Supabase 連線；基準為共同 main `99d4135`。這是資料連線基礎，不代表附近求助、官方通報或任何 Live 產品流程已上線。

## 本輪範圍及契約影響

- 沿用 M1 的原生 HTTP transport，不新增 SDK 套件、不升級 Flutter／GetX／lock，不修改官方 main、登入、Theme、M3 版面或 canonical payload Schema。
- `platform/supabase/SafeWalkSupabaseConfig` 提供編譯參數讀取、HTTPS origin 與公開 client key 驗證。`SupabaseNearbyAlertTransport.fromEnvironment()` 消費同一設定；建構不傳送資料。
- `SupabaseConnection.checkConnection()` 是明確呼叫的原生連線檢查，不在 App 啟動或進入安心行時自動執行。沒有新跨模組依賴、GPS 監聽、位置上傳或官方帳號登入。
- 原生入口仍為 Mock；附近求助 service 尚未接入 composition／UI。設定 build 參數只提供 client 參數，不會自行啟用求助、通知或替換 M4 資料。

## 本機設定

雲端專案：`gxofnhzkqcmzrftxqddi`，Data API 已啟用。Dashboard 的 Connect → Flutter 可確認專案 URL；Settings → API Keys 的 **Publishable key** 供 App 使用。沒有為本輪建立金鑰或變更雲端存取權限。

將 `supabase/client-config.example.json` 的欄位填入本機 `secrets/supabase.local.json`。本輪已透過 Dashboard 寫入此本機檔；`**/secrets/` 已由既有 `.gitignore` 排除。不要將實際 key 加入追蹤檔、對話或命令列紀錄，也不要將 JSON 放進 Flutter assets。

```text
fvm flutter run --dart-define-from-file=secrets/supabase.local.json
fvm dart tool/check_supabase_connection.dart secrets/supabase.local.json
```

App 程式可明確建立 `SafeWalkSupabaseConfig.fromEnvironment()`、`SupabaseConnection(config: config)`，使用完畢呼叫 `close()`。連線檢查只在明確呼叫時發送網路請求。`SupabaseNearbyAlertTransport` 已退役並封鎖全部 HTTP 呼叫；保留 factory 僅供相容，不能由 key 或旗標啟用。附近通知的安全阻塞、手動撤權與後續驗證見[安全狀態](SAFE_WALK_NEARBY_SECURITY.md)。

採用 `SUPABASE_URL`、`SUPABASE_PUBLISHABLE_KEY`。相容變數 `SUPABASE_ANON_KEY` 只接受 legacy `anon` JWT；拒絕 `service_role`／`sb_secret_...`。公開 key 只放 `apikey` header，不把它當作 Bearer JWT。公開 key 可由 App 使用，資料存取仍須靠資料庫權限與 RLS；見 [Supabase API keys](https://supabase.com/docs/guides/getting-started/api-keys)。

## 連線檢查的意義

檢查先 GET `/rest/v1/`，驗證 OpenAPI JSON。此專案會對公開 key 回 `401 Secret API key required`，因此檢查只在該階段 HTTP 401 後，改 GET 保留診斷路徑 `/rest/v1/__safe_walk_connection_probe__?select=*&limit=0`。只有 `404`、`PGRST205` 且訊息包含該診斷名稱，才視為公開 key 已通過 gateway、請求已抵達 PostgREST。一般 401／403／404、無效 JSON、HTML、redirect、timeout 都不算成功。

這個檢查不建立診斷表、不讀寫資料列、不呼叫任何通知 RPC。成功只能證明 client → Data API／PostgREST 可達；不能推論業務表已建立、RLS 已驗證或通知已送達。[PostgREST 的 OpenAPI 說明](https://docs.postgrest.org/en/stable/references/api/openapi.html)也不等於資料列存取授權。

## 附近通知 SQL：部署歷史與現行封鎖

舊 `supabase/nearby_emergency.sql` 來自 PR #21：其 `security definer` RPC 開放給 `anon`，只相信呼叫者提供的 helper／sender UUID，沒有驗證資料所有者。已知其他 helper ID 的呼叫者可能改其 opt-in、座標，或讀取並標記其通知；開啟表級 RLS 不能補上這個函式內的缺口。PR #41 已將此檔改為手動撤權腳本並封鎖 App 的匿名 nearby transport，但未執行遠端 SQL，不能推論實際部署或 ACL 狀態；見[安全修正與限制](SAFE_WALK_NEARBY_SECURITY.md)。

正式啟用前需由 M1 完成可信身分、通知接收資格與 ownership 驗證、RLS／RPC 權限檢查、請求頻率及濫用限制、座標保留／到期及刪除策略，並測試跨使用者拒絕讀寫。還需要使用者清楚同意位置分享、M3 的真實狀態呈現，以及受控測試帳號的實際後端與裝置測試；在所有證據完成前維持 BLOCKED，不得以匿名 UUID 對陌生人開放位置通知。`fetch_pending_alerts` 會更新 `seen`，不可用作唯讀健康檢查。連線診斷不使用真實危難、聯絡人、GPS 或警消通報；後續位置驗收僅在明確同意、隔離的測試資料與保留政策下進行。

## 本輪驗證

| 項目 | 實際結果 |
|---|---|
| Dashboard／本機參數 | Data API 已啟用；公開 key 與 URL 已存入忽略版控的本機 JSON，沒有讀取 secret key 或建立新權限。 |
| 真實專案唯讀連線 | **通過**。Dart CLI 使用公開 key，先取得 OpenAPI 401，再取得保留診斷路徑的 404／PGRST205。沒有資料列讀寫或通知 RPC。 |
| 本輪 Supabase 測試 | **20/20 通過**，Dart 3.13.5、隔離的 `package:test 1.33.0` runner。兩份測試只在被忽略的 harness 將 `flutter_test` import 換為 `package:test`；實作仍引用本輪 lib。沒有改 root pubspec／lock／`.dart_tool`。 |
| Schema generator `--check`／module guard | **通過**。canonical Schema、生成模型與模組邊界維持同步。 |
| Dart format／diff whitespace | **通過**。Formatter 有 root 尚無法解析 `flutter_lints` include 的提示，不將其當成 lint 通過。 |
| Flutter pub get／build_runner／完整 analyze／Flutter tests／build | **未執行**：本機 PATH 的 Flutter 為 3.47.7，與 `.fvmrc` 指定 3.47.6 不符，且沒有該版本的 FVM 安裝。沒有為此升級、降版或改動使用者 SDK；純 Dart 驗證不能代替 Flutter 驗證。Windows 沒有宣稱本機 iOS build。 |
| 業務資料／裝置操作 | **未執行**：沒有部署既有通知 SQL、讀真位置、登入官方 App、撥號、送通知或做裝置驗收。 |

歷史：原連線設定以 `codex/supabase-setup` 分支交 PR #25；PR #27 新增獨立 nearby_live_test_main／page 與 fake Widget tests，當時以三項 dart-define 配置隔離，未接正常 TownPass，也未補可信身分／ownership。PR #41 現已移除該入口的匿名 UUID／Supabase 設定，附近通知固定不可用，僅保留明確旗標與分別同意後的隔離簡訊測試。業務資料接線與通知部署仍須完成前述權限及產品流程，API 可達不是已上線。
