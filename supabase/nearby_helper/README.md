# 附近協助者通知：隔離空表建置

本次使用者明確授權依剛提交的兩份 Markdown 規格建立對應資料表。規格為 commit `92565c9`，經 PR #70 合併至 main `0dd580d` 的[設計提案](../../docs/SAFE_WALK_NEARBY_HELPER_DESIGN.md)與[安全狀態](../../docs/SAFE_WALK_NEARBY_SECURITY.md)。本目錄把其中四表草案具體化為可手動審查的 SQL；授權範圍只有隔離空表、索引、RLS 與撤權，不代表附近通知已啟用。

## 2026-11-08 實際建置紀錄（Asia/Taipei）

已先核對 App 的 `SafeWalkSupabaseConfig`／`CrimeReferenceWiring`、本機 `supabase.local.json` 與 `native-client.json`，以及 GitHub Actions 的 `SUPABASE_URL`；全部指向既有專案 **`gxofnhzkqcmzrftxqddi`（csfishy's Project）**。未建立新 Supabase 專案，也未改連線設定。建置前後均使用 App 原有 `check_crime_reference.dart` 成功查詢相同快照：2,542 筆來源紀錄、10 個來源；沒有傳 GPS 或輸出個別資料列。

透過 Supabase `apply_migration` 套用 `01_create_tables.sql` 的交易內文，migration version **`20261107220740`**、name **`create_private_nearby_helper_tables`**，伺服器回覆成功。此次部署只建立本目錄列明的隔離空表及權限設定。

| 實際檢查 | 結果 |
|---|---|
| 遠端 `00_preflight.sql` | PASS；原 schema 不存在，既有 Auth／API roles／PostGIS 符合要求 |
| 遠端 `02_verify.sql` | PASS；20 欄、型別／defaults／nullability、PK／FK／UNIQUE／CHECK、GiST、RLS、零 policy／function／自訂 trigger、有效 ACL 均符合 |
| 四表筆數 | `helper_profiles`、`helper_locations`、`alerts`、`alert_deliveries` 各為 `0` |
| 公開 client 的 Data API profile 檢查 | PASS；`Accept-Profile: safe_walk_nearby` 的零資料列 probe 回 HTTP 406／`PGRST106`，未暴露此 schema |
| App 原有犯罪資料唯讀查詢 | 建置前後均 PASS；相同快照及來源筆數 |
| 本機 Schema generator／正常 module guard／犯罪資料隔離 guard | PASS |
| 附近通知 RPC、跨帳號操作與實機驗收 | 未執行；本輪未實作或啟用通知功能 |

安全 Advisor 對新四表顯示「RLS enabled, no policy」INFO，符合規格的預設拒絕設計。另確認既有 `public.set_helper_opt_in`、`public.send_emergency_alert`、`public.fetch_pending_alerts` 仍對匿名角色開放 `SECURITY DEFINER` 執行權；本次未執行舊 RPC、未變更舊物件或撤權。其[匿名 definer 權限修復說明](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable)與[既有安全處置規格](../../docs/SAFE_WALK_NEARBY_SECURITY.md)供後續受控處置。既有 PostGIS 在 public 的告警及 `public.spatial_ref_sys` RLS 告警亦未修改；不把新表驗證通過宣稱為全專案安全驗收通過。

## 執行範圍

只建立新的 `safe_walk_nearby` schema 與 `helper_profiles`、`helper_locations`、`alerts`、`alert_deliveries` 四張空表。欄位、PK、CASCADE FK、兩個 CHECK、冪等 UNIQUE 與位置 GiST 索引遵循設計草案；四表啟用 RLS，沒有 policy。`PUBLIC`、`anon`、`authenticated`、`service_role` 均無 schema／table／sequence 權限。

既有專案的 PostGIS 實際安裝在 `public`，與草案的 `extensions.geography` 寫法不同。腳本從 `pg_extension`／`pg_namespace` 找到既有 extension 的 namespace，使用其 `geography(Point,4326)` 型別；不安裝、搬移或修改 extension，也不建立替代型別。這項適配保留欄位語意。其他 schema、Auth 資料列、舊 public 物件、`crime_reference` 及 `safe_walk_demo` 都不修改。

本目錄不提供 RPC、seed、上傳位置、通知、排程清除、client grant、PostgREST exposed-schema 設定或 App transport。沒有 CI、build、App 啟動或 Demo reset 接線。資料表 FK 參照既有 `auth.users(id)`，但本輪不建立 Auth 使用者，也未決定 TownPass 身分橋接方式。

## 手動執行

1. 在已獲本次授權的 Supabase 專案，使用可建 schema、參照 `auth.users` 的管理 SQL session。先人工核對專案；不要將密碼或 token 貼進腳本、對話或日誌。
2. 完整執行 [`00_preflight.sql`](00_preflight.sql)。它使用唯讀交易，只查 metadata；檢查新 schema 不存在、既有 PostGIS geography、Auth UUID 欄位與預期 API roles，並列出執行身分、extension namespace 與 owner default ACL。
3. 審閱後完整執行 [`01_create_tables.sql`](01_create_tables.sql)。全部建置與撤權在同一交易；任何錯誤須停止並回滾。`CREATE SCHEMA` 刻意沒有 `IF NOT EXISTS`；schema 已存在就失敗，不接管、不刪除、不自動修復既有物件。若 SQL 工具在錯誤後仍保持 aborted transaction，只執行 `ROLLBACK` 結束失敗交易，再調查原因。
4. 執行 [`02_verify.sql`](02_verify.sql)。唯讀驗證精確欄位／型別／nullability／defaults、PK／FK 與 CASCADE、冪等 UNIQUE、CHECK、Point/4326 geography、GiST、RLS、零 policy／function／自訂 trigger，以及 PUBLIC、API roles 的有效權限（含繼承及欄位權限）。最後只回傳新四表筆數，建置完成時應各為 `0`；不輸出任何座標或使用者資料。
5. 每次執行皆記錄實際目標、腳本版本、日期與各步結果。僅保存不含 secrets 或位置的摘要；不得把上方本次紀錄挪作其他部署的 PASS。

若透過已連接的 Supabase `apply_migration` 工具部署，由工具記錄 migration history 並管理交易；僅移除 `01_create_tables.sql` 最外層的 `BEGIN`／`COMMIT` 後提交其完整內容，不拆開建表、撤權或交易內檢查。本機檔保留外層交易供手動執行。metadata preflight 與部署後唯讀驗證仍須分別完成。

`01_create_tables.sql` 的 transaction 內另有權限／RLS／零 policy 檢查，避免權限異常仍提交。`02_verify.sql` 是可重跑的結構檢查，不會刪除非零資料；未來經另案授權增加 RPC、policy、欄位或 trigger 後，需同步更新驗證規格。

## 權限與尚未啟用的能力

`ALTER DEFAULT PRIVILEGES IN SCHEMA safe_walk_nearby` 只涉及本次建立者及此 schema。PostgreSQL 的 global default grants 是加總關係，schema 級 REVOKE 無法取消 global grants，也不涵蓋其他 owner。既有四表因此仍逐一明確撤權並驗證有效 ACL；任何未來物件也必須在同一交易明確撤權並驗證，不能靠本次 defaults 保證安全。

R13 附近通知維持 **BLOCKED**。後續仍須決定身分來源／資格、三項獨立同意、可信 session 與 `auth.uid()` ownership、受限 RPC、限流與防重送、接收上限、位置新鮮度與合理移動、撤回、TTL 清除、濫用處理、通知管道、位置精度與保留政策。草案的 10 分鐘位置 TTL、30 分鐘 alert TTL、50 人上限是示例，本次不擅自固定其值或建立排程。

啟用前另需安全與隱私審查、跨帳號拒絕／500 公尺邊界／併發冪等／TTL／撤回／級聯刪除等測試、受控測試身分兩裝置驗收與適用 Level C 授權。建表成功不能證明有人收到通知，不代表官方警消受理；`officialReceipt` 仍為 `null`。
