# 附近協助者通知：資料表建置與隔離後端

遠端已完成的是私有四表、封鎖權限與選填定位精度 migration。PR #71 合併的 `001_nearby_helper.sql` 後端及 authenticated transport 則仍未遠端部署、未接入 App，也未啟用通知。下方分別保留實際資料表部署證據，以及隔離後端的實作與本機測試方式；R13 持續 **BLOCKED**。

本目錄依使用者授權，把兩份 Markdown 的四表草案具體化為可手動審查的 SQL。初次規格為 commit `92565c9`，經 PR #70 合併至 main `0dd580d` 的[設計提案](../../docs/SAFE_WALK_NEARBY_HELPER_DESIGN.md)與[安全狀態](../../docs/SAFE_WALK_NEARBY_SECURITY.md)。初次授權範圍是隔離空表、索引、RLS 與撤權；此次依新版兩份 MD 調整既有資料庫，附近通知仍未啟用。

## 2026-11-08 新版規格：選填定位精度（已套用）

新版規格來自 `2661d02`，已由 PR #71 合併至 main `b7d08dd`。完整比對兩份 MD 後，本輪結構差異只有 `helper_locations.accuracy_m`：保留 `real` 型別，允許 NULL，並將 CHECK 改為 `accuracy_m IS NULL OR accuracy_m >= 0`。其他三表及欄位、既有 PK／FK／UNIQUE、500 公尺 CHECK、索引、RLS 與封鎖權限沿用。

本次差異 migration 為 Supabase 官方 CLI `3.0.0` 產生的 [`20261107221444_allow_optional_helper_accuracy.sql`](migrations/20261107221444_allow_optional_helper_accuracy.sql)，已在 App 原用的 **`gxofnhzkqcmzrftxqddi`** 套用。遠端 `apply_migration` history version 為 **`20261107221553`**、name 為 **`allow_optional_helper_accuracy`**；工具自行產生 history 時間，與本機 CLI 檔名時間不同。檔案保留在手動目錄，不放入自動執行的 migrations 路徑。`00_preflight.sql`、`01_create_tables.sql` 保留初次建表版本，原始 `accuracy_m` 仍為 NOT NULL；新建環境也須在初次建表後套用本次差異 migration，才符合最新版 `02_verify.sql`。

本次實際驗證：套用前以 `d79c04d` 版唯讀 verifier 確認既有結構；套用後最新版 `02_verify.sql` **PASS**，catalog 顯示 `accuracy_m` 為 nullable `real`、明確 NULL CHECK 已 validated。四表仍為 20 欄、12 個約束，保留原 GiST／PK／UNIQUE 索引、CASCADE FK、RLS 與有效 ACL；各表筆數前後皆為 `0`。沒有建立 RPC／policy 或開放 API 權限。Advisor 對本 schema 仍僅回報預期的 RLS／零 policy INFO，既有 public／PostGIS 告警未改動。

本輪資料表調整的本機 Schema generator `--check`、正常 module guard、犯罪資料隔離 guard、README 本機連結與 diff whitespace 檢查皆 PASS。這項資料表調整本身沒有 App 程式或 shared wire 契約變更，未執行 Flutter build／裝置驗收；本輪證據僅涵蓋上述資料表規格調整。PR #71 的後端與 transport 實作另見下方說明。

PR #71 的 `001_nearby_helper.sql` 另加 consent_version 長度 CHECK、四個輔助索引與通知 RPC；這些不在兩份 MD 的表結構差異內，本輪未套用該整份 SQL，也未部署 RPC。新版 MD 的精度省略、10 秒更新間隔與重複收取／首次 seen_at 行為已有隔離實作，遠端與 App 接線驗收仍待完成。

## 2026-11-08 初次建表紀錄：舊規格（Asia/Taipei）

已先核對 App 的 `SafeWalkSupabaseConfig`／`CrimeReferenceWiring`、本機 `supabase.local.json` 與 `native-client.json`，以及 GitHub Actions 的 `SUPABASE_URL`；全部指向既有專案 **`gxofnhzkqcmzrftxqddi`（csfishy's Project）**。未建立新 Supabase 專案，也未改連線設定。建置前後均使用 App 原有 `check_crime_reference.dart` 成功查詢相同快照：2,542 筆來源紀錄、10 個來源；沒有傳 GPS 或輸出個別資料列。

透過 Supabase `apply_migration` 套用 `01_create_tables.sql` 的交易內文，migration version **`20261107220740`**、name **`create_private_nearby_helper_tables`**，伺服器回覆成功。此次部署只建立本目錄列明的隔離空表及權限設定。

| 實際檢查 | 結果 |
|---|---|
| 遠端 `00_preflight.sql` | PASS；原 schema 不存在，既有 Auth／API roles／PostGIS 符合要求 |
| 遠端 `02_verify.sql`（當時 `d79c04d` 版） | PASS；20 欄、型別／defaults／nullability、PK／FK／UNIQUE／CHECK、GiST、RLS、零 policy／function／自訂 trigger、有效 ACL 均符合 |
| 四表筆數 | `helper_profiles`、`helper_locations`、`alerts`、`alert_deliveries` 各為 `0` |
| 公開 client 的 Data API profile 檢查 | PASS；`Accept-Profile: safe_walk_nearby` 的零資料列 probe 回 HTTP 406／`PGRST106`，未暴露此 schema |
| App 原有犯罪資料唯讀查詢 | 建置前後均 PASS；相同快照及來源筆數 |
| 本機 Schema generator／正常 module guard／犯罪資料隔離 guard | PASS |
| 附近通知 RPC、跨帳號操作與實機驗收 | 未執行；本輪未實作或啟用通知功能 |

安全 Advisor 對新四表顯示「RLS enabled, no policy」INFO，符合規格的預設拒絕設計。另確認既有 `public.set_helper_opt_in`、`public.send_emergency_alert`、`public.fetch_pending_alerts` 仍對匿名角色開放 `SECURITY DEFINER` 執行權；本次未執行舊 RPC、未變更舊物件或撤權。其[匿名 definer 權限修復說明](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable)與[既有安全處置規格](../../docs/SAFE_WALK_NEARBY_SECURITY.md)供後續受控處置。既有 PostGIS 在 public 的告警及 `public.spatial_ref_sys` RLS 告警亦未修改；不把新表驗證通過宣稱為全專案安全驗收通過。

## 執行範圍

初次建置只建立新的 `safe_walk_nearby` schema 與 `helper_profiles`、`helper_locations`、`alerts`、`alert_deliveries` 四張空表。欄位、PK、CASCADE FK、兩個 CHECK、冪等 UNIQUE 與位置 GiST 索引遵循初次設計草案；四表啟用 RLS，沒有 policy。`PUBLIC`、`anon`、`authenticated`、`service_role` 均無 schema／table／sequence 權限。本次差異 migration 僅調整既有 `accuracy_m` 的 nullability 與 CHECK，不建立或重建資料表。

既有專案的 PostGIS 實際安裝在 `public`，與草案的 `extensions.geography` 寫法不同。腳本從 `pg_extension`／`pg_namespace` 找到既有 extension 的 namespace，使用其 `geography(Point,4326)` 型別；不安裝、搬移或修改 extension，也不建立替代型別。這項適配保留欄位語意。其他 schema、Auth 資料列、舊 public 物件、`crime_reference` 及 `safe_walk_demo` 都不修改。

已套用的手動 `00/01` 與 optional-accuracy migration 不部署 RPC、seed、上傳位置、通知、排程清除、client grant、PostgREST exposed-schema 設定或 App transport；`001_nearby_helper.sql` 的隔離後端另列於下方。沒有 CI、build、App 啟動或 Demo reset 接線。資料表 FK 參照既有 `auth.users(id)`，但本輪不建立 Auth 使用者，也未決定 TownPass 身分橋接方式。

## 私有資料表的手動執行順序

1. 在已獲本次授權的 Supabase 專案，使用有權變更目標表的管理 SQL session。先人工核對專案；不要將密碼或 token 貼進腳本、對話或日誌。
2. 已有初次四表的專案直接進行差異 migration；不要重跑 `00_preflight.sql` 或 `01_create_tables.sql`。只有全新環境先完整執行 [`00_preflight.sql`](00_preflight.sql) 的唯讀 metadata 檢查，再審閱並完整執行 [`01_create_tables.sql`](01_create_tables.sql)。`CREATE SCHEMA` 刻意沒有 `IF NOT EXISTS`；schema 已存在就失敗，不接管、不刪除、不自動修復既有物件。
3. 完整套用 [`20261107221444_allow_optional_helper_accuracy.sql`](migrations/20261107221444_allow_optional_helper_accuracy.sql)，將既有欄位改為 nullable 與明確接受 NULL 的 CHECK。所有變更及斷言應在同一交易；任何錯誤須停止並回滾。若 SQL 工具在錯誤後仍保持 aborted transaction，只執行 `ROLLBACK` 結束失敗交易，再調查原因。
4. 差異 migration 成功後才執行最新版 [`02_verify.sql`](02_verify.sql)。它要求 `accuracy_m` 可為 NULL、CHECK 為 `accuracy_m IS NULL OR accuracy_m >= 0`，並唯讀驗證精確欄位／型別／defaults、PK／FK 與 CASCADE、冪等 UNIQUE、CHECK、Point/4326 geography、GiST、RLS、零 policy／function／自訂 trigger，以及 PUBLIC、API roles 的有效權限（含繼承及欄位權限）。最後只回傳四表筆數；初次空表建置時應各為 `0`，後續執行不會刪除非零資料，不輸出座標或使用者資料。
5. 每次執行皆記錄實際目標、腳本版本、日期與各步結果。僅保存不含 secrets 或位置的摘要；不得把上方本次紀錄挪作其他部署的 PASS。

若透過已連接的 Supabase `apply_migration` 工具部署，由工具記錄 migration history 並管理交易。提交要部署的完整 migration；若該腳本自帶最外層 `BEGIN`／`COMMIT`，僅移除該外層包裝，不拆開變更與交易內檢查。本機初次建表檔保留外層交易供手動執行。部署前 metadata 檢查與部署後唯讀驗證仍須分別完成。

`01_create_tables.sql` 的 transaction 內另有權限／RLS／零 policy 檢查，避免權限異常仍提交。`02_verify.sql` 是可重跑的結構檢查，不會刪除非零資料；未來經另案授權增加 RPC、policy、欄位或 trigger 後，需同步更新驗證規格。

## 權限與尚未啟用的能力

`ALTER DEFAULT PRIVILEGES IN SCHEMA safe_walk_nearby` 只涉及本次建立者及此 schema。PostgreSQL 的 global default grants 是加總關係，schema 級 REVOKE 無法取消 global grants，也不涵蓋其他 owner。既有四表因此仍逐一明確撤權並驗證有效 ACL；任何未來物件也必須在同一交易明確撤權並驗證，不能靠本次 defaults 保證安全。

R13 附近通知維持 **BLOCKED**。後續仍須完成身分來源／資格、三項獨立同意、可信 session 與 `auth.uid()` ownership、受限 RPC、限流與防重送、接收上限、位置新鮮度與合理移動、撤回、TTL 清除、濫用處理、通知管道、位置精度與保留政策的決策及驗收。10 分鐘位置 TTL、30 分鐘 alert TTL、50 人上限已寫入隔離後端實作；本次資料表部署沒有設定這些執行期限制或建立排程。

啟用前另需安全與隱私審查、跨帳號拒絕／500 公尺邊界／併發冪等／TTL／撤回／級聯刪除等測試、受控測試身分兩裝置驗收與適用 Level C 授權。建表成功不能證明有人收到通知，不代表官方警消受理；`officialReceipt` 仍為 `null`。

## 隔離後端實作（PR #71；尚未遠端部署）

Implements the design in [SAFE_WALK_NEARBY_HELPER_DESIGN.md](../../docs/SAFE_WALK_NEARBY_HELPER_DESIGN.md).
**The `001_nearby_helper.sql` RPC backend and authenticated transport are not
deployed, wired into the app, or enabled.** The manual table migrations above have
been applied; their verification does not verify these RPCs. Readiness for nearby
notification stays **BLOCKED** until the evidence listed in
[SAFE_WALK_NEARBY_SECURITY.md](../../docs/SAFE_WALK_NEARBY_SECURITY.md) exists and the
team lead authorizes it (Level C).

### Backend behavior

- People who opt in as **helpers** have **one latest position** stored, replaced on
  each report, expiring after 10 minutes, never a history.
- A signed-in user's SOS creates an alert at the SOS position. The server finds
  opted-in helpers inside **500 m** with PostGIS, excluding the sender and anyone whose
  position is missing or expired, and notifies at most the 50 nearest.
- The SOS caller only gets back **how many** helpers were notified. A helper reads the
  alerts addressed to them (position, time, expiry). **Neither side ever receives the
  other's identity**, and no function returns other people's coordinates to a caller
  who is not the recipient.
- Identity is always `auth.uid()` from a verified session. No function accepts a user id.

### Files

| File | Purpose |
|---|---|
| [`00_preflight.sql`](00_preflight.sql) | 已遠端執行的初次建表唯讀檢查，要求目標 schema 尚不存在 |
| [`01_create_tables.sql`](01_create_tables.sql) | 已遠端套用的歷史四表／RLS／撤權建置；accuracy 原為 NOT NULL |
| [`20261107221444_allow_optional_helper_accuracy.sql`](migrations/20261107221444_allow_optional_helper_accuracy.sql) | 已遠端套用的差異 migration，只修改 accuracy nullability／CHECK |
| [`02_verify.sql`](02_verify.sql) | optional-accuracy migration 後的唯讀結構／權限／筆數驗證，要求零 RPC／policy |
| [`001_nearby_helper.sql`](001_nearby_helper.sql) | **尚未遠端部署的隔離後端。** Private schema `safe_walk_nearby`, tables with RLS (no policies), and the `public.nearby_*` RPCs, executable by `authenticated` only |
| [`local_test/00_bootstrap.sql`](local_test/00_bootstrap.sql) | **Local test only.** Stubs Supabase roles, `extensions`, `auth.users` and `auth.uid()` |
| [`local_test/10_test_nearby_helper.sql`](local_test/10_test_nearby_helper.sql) | **Local test only.** Assertions for privileges, identity, 499 m / 501 m boundary, expiry, opt-out deletion, idempotency, rate limits, retention and cascade deletion |

RPCs: `nearby_helper_opt_in`, `nearby_helper_opt_out`, `nearby_helper_report_location`,
`nearby_sos_send`, `nearby_helper_fetch_alerts`, `nearby_helper_set_areas`,
`nearby_helper_get_areas`. **Guard areas** (`helper_areas`): a helper may set up to 3 circles
(500 or 1000 m, centre rounded to ~100 m by the server); an SOS also notifies a
helper whose guard area covers it, once per helper. The server cannot verify that a centre
is where the helper really is; see the design doc's known-risk note. `safe_walk_nearby.purge_expired()` is
hygiene only (every read already filters on expiry) and is not exposed to API roles.

Limits built in: location reports at most every 10 s; SOS at most one per 15 s and 5 per
hour per sender; SOS is idempotent per `client_request_id`; reported accuracy above
500 m is rejected.

### Run the backend tests locally

Needs any PostgreSQL with PostGIS. With Docker, using only synthetic data:

```bash
docker run -d --name nearby-pg -e POSTGRES_PASSWORD=test -p 54329:5432 postgis/postgis:16-3.4
PSQL="docker exec -i nearby-pg psql -U postgres -v ON_ERROR_STOP=1"
$PSQL < supabase/nearby_helper/local_test/00_bootstrap.sql
$PSQL < supabase/nearby_helper/001_nearby_helper.sql
$PSQL < supabase/nearby_helper/local_test/10_test_nearby_helper.sql   # prints ALL ... PASSED
docker rm -f nearby-pg
```

The test file runs in one transaction and rolls back.

### Deploying the RPC backend (manual, after authorization)

1. Use an **isolated** Supabase project (or a schema the team lead has authorized).
   Not the `crime_reference` data, not `safe_walk_demo`, never from CI, builds, app
   startup or Demo reset.
2. Review `001_nearby_helper.sql` for that isolated target before applying it as the
   project owner. It assumes PostGIS is in `extensions` and uses `CREATE TABLE IF
   NOT EXISTS`, which does not upgrade existing tables. The authorized project
   above has PostGIS in `public` and the manual tables already exist; its future
   backend deployment needs a reviewed forward migration that adapts those
   prerequisites. Do not use the standalone script as the table delta above.
3. Schedule `safe_walk_nearby.purge_expired()` (for example every minute with
   `pg_cron`) after review.
4. Verify as real roles: `anon` cannot call any function, one account cannot read
   another's data, opt-out removes the position, rate limits return HTTP 429.

### Client

### Delivery to helpers is in-app, not SMS

Helpers join from the Safe Walk home page (consent text first). While the app is in the
foreground the helper's position is refreshed about every 4 minutes and alerts are polled
every 10 seconds; an incoming alert appears as a banner over the current screen. Nothing
runs in the background or when the app is closed, because the project has no push channel
(FCM/APNs). The existing SMS card is unrelated to this path.

[`AuthenticatedNearbyAlertTransport`](../../lib/features/safe_walk/platform/nearby_emergency/authenticated_nearby_alert_transport.dart)
calls these RPCs with the user's session token. It needs a `NearbySession`, which only
exists once the team decides where user identity comes from (TownPass login or Supabase
Auth). Until a composition supplies one, the app keeps using the unavailable transport.
