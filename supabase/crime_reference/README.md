# 私有犯罪參考資料：人工 SQL 套件

僅供已確認的既有 Supabase 專案之獨立 `crime_reference` schema。這些檔案不在 `supabase/migrations`，沒有 CLI、CI、App、Demo seed、RPC 或 API 接線。沒有執行遠端 SQL 的宣告。Schema/RLS 屬 Level C；隊長在實際套用前審查具體 SQL 與資料快照。

## 人工順序

1. 在專案 Dashboard 核對專案身分，以 `postgres` 執行 `00_preflight.sql`；只讀 schema、ACL、policy、trigger 與三張指定表筆數。既有未知 schema 必須停止並調查。
2. 確認 Data API exposed schemas 不包含 `crime_reference`。此套件不更改 API 全域設定、Auth、public 表或現有 Demo。
3. 審查後執行一次 `01_initialize.sql`。交易中建立全新 schema；既有 schema 會拋錯，沒有 overwrite、DROP、reset 或 `IF NOT EXISTS`。
4. 人工建立新 snapshot UUID，核對產物與來源 manifest SHA256；依 snapshots → sources → records 順序匯入。SQL 匯入應包在單一交易且在 COMMIT 前驗 count。Dashboard CSV 分三表匯入不是跨表原子交易，未完成驗證的 snapshot 不可標為成功；失敗時保留不完整快照供審計，修正後用新 UUID，不 UPDATE/DELETE/TRUNCATE。不可使用 upsert 或衝突忽略。
5. 將 `02_verify_snapshot.sql` 的 UUID 替換為本次 UUID，執行只讀驗證並保存結果及 DB fingerprint 至外部驗收收據。此版本預期10來源、2542紀錄：臺北617、新北970、基隆955；這是來源紀錄，未按案件去重。

## CSV 欄位契約

UTF-8、正常 CSV quoting；JSON 用 object 並依 CSV 規則跳脫雙引號。可空值用空欄而非字串 `null`；JSON object 不能留空（無證據用 `{}`）。UUID 由人工匯出器產生，不依賴新增 extension。

```text
snapshots:
snapshot_id,label,as_of_date,expected_record_count,expected_source_count,artifact_sha256,manifest_sha256,metadata

sources:
snapshot_id,source_key,dataset_id,resource_id,name,source_url,resource_url,license,retrieved_at,data_updated_at,raw_sha256,original_encoding,expected_record_count,metadata

records:
snapshot_id,source_key,source_record_id,source_row,event_date,city,district,category,location_text,latitude,longitude,spatial_precision,confidence,coordinate_status,raw_payload,record_payload,geocoding,evidence
```

`source_key` 使用匯出器穩定來源代碼；`dataset_id` 保留真實官方 ID；NPA同 dataset 的三季 resource 必須是不同 source_key。`source_record_id` 保留來源列身分（不是官方案件 ID）。主鍵包含 snapshot_id；新版本不覆寫舊快照。source_row 是來源列號而非去重序號；有欄位說明列的 CSV 須保留明確列號慣例。

`raw_payload` 是原始來源 object；`record_payload` 是完整正規化匯出 object；`geocoding` 是定位處理 object；`evidence` 是可查證定位證據 object。來源 metadata 不加入私人聯絡人、憑證或 App 使用者 GPS。資料與 CSV/JSON seed 不放入 Git。

精度枚舉沿用資料工具：`public_place_reference`、`road_segment_reference`、`address_range_reference`、`address_reference` 可帶查證後的參考座標；`district_only`、`blurred_text`、`unresolved` 必須為空座標。confidence=`high|medium|unknown` 是位置匹配可信度，不是治安可信度。coordinate_status=`not_provided|reference_geocoded|source_provided`。未知 confidence 不得帶推算座標，原生來源座標例外。經緯度必須成對、符合 WGS84 範圍；參考定位須有非空定位與證據 object。精度標記不代表精確案發點，也不自動適用道路避讓。

## 保護與限制

三表啟用並 FORCE RLS，只有 `postgres` SELECT/INSERT policy；PUBLIC、anon、authenticated、service_role 的 schema、table、sequence、function 權限明確撤回。三表 statement trigger 拒絕 UPDATE、DELETE、TRUNCATE，即使無符合紀錄也會拒絕。只有人工 postgres insert；這些保護不聲稱能阻止具備 DDL/超級使用者權限的人停用保護或刪 schema。

Schema 範圍的 default privileges 亦撤回；PostgreSQL 的全域預設權限不能由 schema revoke 抵消，因此本版已明確撤回兩個 trigger helper 的 PUBLIC EXECUTE。未來新增物件需再次逐物件審查 ACL；不得為此更改其他 schema 的全域預設。沒有對外 RPC，兩個函式只供內部 trigger 使用，均為 SECURITY INVOKER 與固定 pg_catalog search_path。

artifact_sha256/manifest_sha256 是原檔雜湊，供對照經審查檔案。驗證 SQL 另產生依 C 排序之 `record_payload::jsonb::text` 串接 SHA256，屬 DB JSONB fingerprint；它的序列化不同於原檔，不能假稱兩者相等。匯入器仍須在送出前校驗原檔 hash 與 typed 欄位／record_payload 一致性。

官方技術依據：[PostgreSQL RLS](https://www.postgresql.org/docs/current/ddl-rowsecurity.html)、[default privileges](https://www.postgresql.org/docs/current/sql-alterdefaultprivileges.html)、[Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security)、[custom schemas](https://supabase.com/docs/guides/api/using-custom-schemas)。RLS 不涵蓋 TRUNCATE，故另有 trigger 與 ACL；FORCE 不限制超級使用者/BYPASSRLS，故不能單靠 RLS 宣稱角色隔離。

2026-11-07 已依使用者指定在既有專案完成初始化與快照 `5ea3810c-5744-4b89-baad-0121c8fc951b` 的實際匯入；10 項遠端唯讀結構／權限／內容驗證通過，詳見 [實際快照](../../docs/SAFE_WALK_CRIME_DATABASE.md)。初次 CSV 部分寫入後，以逐批既存整列相等檢查及 missing-key INSERT 完成；沒有 UPDATE／DELETE／TRUNCATE。資料與雜湊收據保存在 Git 外；此目錄只含受控 SQL 及操作說明。

尚未執行故意修改遠端資料的 negative security tests；App/API 及實機亦未接入，不能標記 LIVE_VERIFIED。管理者仍能向舊 snapshot INSERT 或變更 DDL，版本流程與期望筆數需持續驗證，不能聲稱僅靠 append-only trigger 即可永久封存。
