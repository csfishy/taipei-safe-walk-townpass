# 北北基犯罪參考資料：App 唯讀查詢（issue #48 P0-1）

PR #44 已將北北基 2,542 筆來源紀錄匯入既有 Supabase 的私有 `crime_reference` schema（RLS＋FORCE，anon／authenticated 無表權限）。本目錄讓 App 以**公開金鑰**透過一支審查過的唯讀函式查詢，不開放原始資料表、不放管理者金鑰。

## 介面

- SQL：[`supabase/crime_reference/04_app_read_api.sql`](../../../../../supabase/crime_reference/04_app_read_api.sql)，人工以 `postgres` 套用；不是 CLI migration，CI 不呼叫。
- `public.safe_walk_crime_reference_query(p_city, p_category, p_from, p_to, p_min_lat, p_min_lng, p_max_lat, p_max_lng, p_limit, p_offset)` → `jsonb`。
  - `SECURITY DEFINER`、`search_path=''`、`STABLE`；只回固定欄位，不回 `raw_payload`／`record_payload`／`geocoding`／`evidence`／metadata JSON。
  - 釘選已審查快照 `5ea3810c-…`；筆數與 `expected_record_count` 不符即回 `crime_reference_snapshot_unavailable`，不回部分資料。
  - `limit` 1–200、`offset` 0–5000、bbox 每邊 ≤ 0.5 度；違反回 SQLSTATE `22023`。
  - 只授 `EXECUTE` 給 `anon`、`authenticated`；不改任何 `crime_reference` 表／schema 權限，`02_verify_snapshot.sql` 應仍通過。
- 回應：`interfaceVersion`、`snapshot`（標籤、資料截至日、匯入時間、筆數）、`sources`（名稱、官方 URL、授權、取得時間、來源更新時間或 null）、`totalMatching`、`records`（日期、城市、行政區、類別、原始地點文字、參考座標或 null、精度、匹配信心、座標狀態）。

## Dart

- `CrimeReferenceRepository.query(mode:, query:, cancellation:)`：只支援 live。未配置或 mock 拋 `SafeWalkDataUnavailable`，沒有示範資料或 fallback。
- 失敗拋 `CrimeReferenceQueryException`：`network`、`timeout`、`unauthorized`、`interfaceMissing`（SQL 未套用）、`invalidArgument`、`snapshotUnavailable`、`serverUnavailable`、`invalidResponse`。訊息不含回應內容、端點或金鑰。
- Parser 重驗資料庫不變式：粗精度不得帶座標、座標成對且與 `coordinateStatus` 一致、未知信心不得帶推算座標、紀錄必屬已列來源、日期不晚於快照、結果須符合查詢條件；任一不符整頁拒絕。
- 傳輸由 M1 注入：`platform/supabase/supabase_rpc_client.dart`（dart:io，不跟隨 redirect，限制回應大小）＋ `platform/integration/crime_reference_wiring.dart`（讀 `SUPABASE_URL` 與 `SUPABASE_PUBLISHABLE_KEY`／`SUPABASE_ANON_KEY`；service_role JWT 會被拒）。Flutter web 不支援。

## 限制

參考座標不是精確案發點、不是避讓路段；歷史紀錄不是即時道路風險或安全保證；來源紀錄未跨來源去重。顯示時須保留來源、日期、精度與 `crimeReferenceLimitations`。

尚未對真實 Supabase 套用 SQL 或實際查詢，也未做 iPhone 驗收；狀態為 IMPLEMENTED_NOT_WIRED（只有獨立 live check 入口，未接正式安心行流程）。
