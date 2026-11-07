# TownPass Supabase 連線設定

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

App 程式可明確建立 `SafeWalkSupabaseConfig.fromEnvironment()`、`SupabaseConnection(config: config)`；既有原生 nearby transport 可用 `SupabaseNearbyAlertTransport.fromEnvironment()`。使用完畢呼叫 `close()`。只有明確呼叫的檢查或業務方法會發送網路請求。附近求助目前仍須先完成下節權限設計，不能因為有 factory 就啟用。

採用 `SUPABASE_URL`、`SUPABASE_PUBLISHABLE_KEY`。相容變數 `SUPABASE_ANON_KEY` 只接受 legacy `anon` JWT；拒絕 `service_role`／`sb_secret_...`。公開 key 只放 `apikey` header，不把它當作 Bearer JWT。公開 key 可由 App 使用，資料存取仍須靠資料庫權限與 RLS；見 [Supabase API keys](https://supabase.com/docs/guides/getting-started/api-keys)。

## 連線檢查的意義

檢查先 GET `/rest/v1/`，驗證 OpenAPI JSON。此專案會對公開 key 回 `401 Secret API key required`，因此檢查只在該階段 HTTP 401 後，改 GET 保留診斷路徑 `/rest/v1/__safe_walk_connection_probe__?select=*&limit=0`。只有 `404`、`PGRST205` 且訊息包含該診斷名稱，才視為公開 key 已通過 gateway、請求已抵達 PostgREST。一般 401／403／404、無效 JSON、HTML、redirect、timeout 都不算成功。

這個檢查不建立診斷表、不讀寫資料列、不呼叫任何通知 RPC。成功只能證明 client → Data API／PostgREST 可達；不能推論業務表已建立、RLS 已驗證或通知已送達。[PostgREST 的 OpenAPI 說明](https://docs.postgrest.org/en/stable/references/api/openapi.html)也不等於資料列存取授權。

## 附近通知 SQL 尚未部署

既有 `supabase/nearby_emergency.sql` 來自 PR #21。本輪沒有執行：其 `security definer` RPC 開放給 `anon`，只相信呼叫者提供的 helper／sender UUID，沒有驗證資料所有者。已知其他 helper ID 的呼叫者可能改其 opt-in、座標，或讀取並標記其通知；開啟表級 RLS 不能補上這個函式內的缺口。

正式啟用前需由 M1 完成可信身份與 ownership 檢查、座標保留／到期及刪除策略、濫用限制，並測試跨使用者拒絕讀寫。還需要使用者清楚同意位置分享及 M3 的真實狀態呈現。`fetch_pending_alerts` 會更新 `seen`，不可用作唯讀健康檢查。任何測試均不使用真實危難、聯絡人、GPS 或警消通報。

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

本輪變更以 `codex/supabase-setup` 分支交 PR 至團隊 main，由隊員審查；不自行合併或發布。業務資料接線與通知部署須另完成前述權限及產品流程；不能把 API 可達回報為已上線。
