# CI／Demo 資料庫重設（Level C 待審查）

初始化機制由 PR #40 引入，原實作基準為 main `c441070`。2026-11-08 的啟用門檻修正以 main `e263aa9` 為基準：#40 讓尚未配置專用 Demo 的 main run 也必跑遠端 job，因缺配置而阻擋既有發布。本修正保留必要的本機資料庫驗證，將遠端重設改為獨立、明確的 Level C 啟用步驟。影響 M1 的 CI 與部署門檻，交小魚／隊長及安全／隱私審查；不自行合併、配置 Secrets 或啟用遠端。既有 revert PR #45 在本修正提出時仍開放，本修正以替代修復 PR 提交，不自行關閉它。

依 [LIVE-FIRST／NO PRODUCTION MOCK](SAFE_WALK_LIVE_FIRST.md)，Demo／seed 僅用於隔離測試，不是 Production 使用者資料來源；主 App 不消費 `safe_walk_demo`。PR #47 已合併至 main `752dd96`，遠端 reset 須明確啟用；持久 `crime_reference` 不在 reset 範圍。

## 資料盤點與範圍

- PR #40 前的 Supabase client 透過 PostgREST，只有 `supabase/nearby_emergency.sql` 定義 `public.helpers`、`public.emergency_alerts`、`public.alert_recipients` 與三個 RPC，當時沒有 Supabase CLI config、正式 migrations 或 seed。#40 新增 `supabase/demo/` 的隔離 migrations／seed；Repository 定義不證明遠端已部署哪些表。
- 舊匿名 security-definer RPC 缺可信身分／ownership 驗證，仍 BLOCKED；新程序不執行舊 SQL。
- 新程序只管理專用 `safe_walk_demo` schema 的同形三表及 migration checksum journal；不改 public、Auth、Storage 或其他專案。不 DROP DATABASE／SCHEMA，不 CASCADE，也不執行 Supabase 全庫 reset。
- 初始 fixture 固定為 2 helpers、1 alert、1 recipient：人工 UUID、公開地標人工座標與 `2000-01-01T00:00:00Z`，無真人或通知外送。fixture 不是已送達通知／派遣紀錄。
- M4 `TaipeiViolentCrimeRepository` 直接讀 data.taipei 詮釋資料及主計處 `tsis.dbas.gov.taipei` CSV，僅 6 小時記憶體快取，未存 DB。重設不刪除或重新匯入該來源，也不建立另一套犯罪表／ETL。未來若改 DB-backed，須新增可信來源匯入及驗證後擴充。

主 App 目前不消費 `safe_walk_demo`。本 PR 不改 Dart transport 的 public 預設、Live 能力或通知開關；資料庫初始化成功不表示附近求助已上線。

## Actions 流程

```mermaid
flowchart LR
  A[PR／main／tag／手動] --> B[Runner 本機 PostGIS]
  B --> C[初始化＋雙重重設與安全測試]
  C --> D[解析啟用快照＋既有分析與 Flutter tests]
  D --> E[Web／Android／iOS 並行建置]
  E --> F{main push／main 手動?}
  F -->|是| G{啟用快照為 true?}
  G -->|否：未設定／false| H[Summary 明示未重設遠端]
  H --> I[既有 main 發布／Pages 門檻]
  G -->|是| J[專用 Demo：一次 migration／reset／seed／verify]
  J -->|成功| I
  J -->|失敗／缺配置／取消／非預期跳過| K[阻擋後續發布／部署]
  F -->|PR／其他手動| L[僅 artifacts，無遠端重設]
  F -->|版本 tag| M[既有 tag 發布，無遠端重設]
```

兩份工作流都先呼叫 `demo_database_ci.yml`，在獨立 job 建 runner-local PostGIS 17 與 `safe_walk_ci`；PR（含 fork）完全沒有 Demo Secrets。CI 初始化 PostGIS／受限角色／標記，再重設並執行真 DB integration tests。容器隨 job 銷毀。

只有 `build.yml` 的 **單一 `demo-database-reset` job** 可連遠端，且須同時滿足 main push／main 的 workflow_dispatch、check／Web／Android／iOS 都成功，以及啟用快照為 `true`。三平台不各自重設，`safe_walk.yml` 沒有遠端 job。PR（含 fork）永不觸發遠端；既有 tag 發布保留，但不重設共享 Demo。

遠端啟用由 **Repository Actions Variable `DEMO_DATABASE_RESET_ENABLED`** 控制，在 Repository Settings → Secrets and variables → Actions → Variables 設定；不要建立同名 environment variable 代替，因 job 條件在載入 environment 設定之前就會求值。這個非敏感旗標不存 DSN、密碼或 Project ID。`check` job 的 `demo-policy` step 一次解析該 repository variable，輸出本次 run 的 `demo_reset_enabled` 啟用快照；遠端 job 與 main 發布／Pages gate 都使用相同快照，避免執行中重新讀值造成判斷不一致。

| Repository variable 值 | main 遠端 job | main prerelease／Pages 的資料庫門檻 |
|---|---|---|
| 未設定、空字串或精確值 `false` | 預期跳過，不讀取遠端 Secrets、不連遠端 | 所有本機資料庫測試、分析及三平台建置仍須成功；只接受這個 disabled 快照的預期 skip，Summary 明示未執行遠端重設 |
| 精確值 `true` | 檢查與三平台建置通過後執行一次 | 必須重設成功；缺 Secrets／白名單／marker／受限角色或重設失敗、取消、非預期 skip 都阻擋 |
| 其他值，例如 `TRUE`、`1`、含空白的 ` true ` | 配置檢查失敗 | 阻擋，不自動解讀成 disabled |

disabled 時允許延續的是**目前不依賴 `safe_walk_demo` 的既有發布流程**，不表示遠端環境已就緒，也不放寬任何本機 CI 門檻。未來若 App 或部署開始消費此資料庫，須另修資料依賴與啟用驗收，不能沿用 disabled 分支宣稱可用。main 手動執行仍依既有規則不建立 GitHub Release；Pages 保留原有設定、事件及最新來源檢查。tag 不連遠端，不以 tag run 清除共享 Demo。

已啟用的遠端 job 跨 workflow 共用 concurrency group `safe-walk-demo-database`、`cancel-in-progress: false`，DB 內另用交易 advisory lock；鎖已占用即失敗，稍後明確重試。GitHub 可能以新 run 取代舊 pending job；啟用快照為 `true` 時，被取消／失敗的 reset 不放行部署。共享 Demo 保證每次成功重設後的初始狀態一致；新成功 build 可以更新共同 Demo，不代表各舊版本永久有獨立 snapshot。

## Fail-closed 防線

1. runner-local CI 必跑，僅接受 loopback `safe_walk_ci`。遠端先要求精確的啟用快照，再驗證明確 `demo`、GitHub Actions repository、environment 與 Project ID；Demo 僅 main 的受信事件。啟用旗標不能取代任何 DB 安全驗證。
2. Demo ref 必須在 `supabase/demo/targets.json` 唯一列出，DSN host、專用 username 與 ref 一致。遠端只允許 direct／session pooler 5432、`sslmode=verify-full`；禁止 transaction pooler、hostaddr／service／options 或環境 PG 連線覆寫。
3. 白名單目前為空，本修正也不設定啟用 variable。未設定／`false` 時不嘗試遠端；若之後設為 `true` 但白名單仍空，必須失敗並阻擋相關發布，不能因「尚未配置」自動放行。原專案 `gxofnhzkqcmzrftxqddi` 用途未經獨立 Demo 驗證，列程式及 manifest 保護清單，不猜測其可清除性。
4. DB 必須先由 DBA 獨立 provision `safe_walk_demo_control.target` 單一標記（environment、project_id、repository）；reset 程式不能建立或修改標記，錯配即停止。
5. `safe_walk_demo_reset` 只擁有 app schema，不得有 superuser、CREATEDB、CREATEROLE、BYPASSRLS、replication 或角色繼承，也不能寫 Auth／其他 schema。PostGIS 須預先在 `extensions`。未審查 event trigger、app trigger、跨 schema FK、未知 objects／RPC 會停止，防間接副作用；不自動修改其他 schema 的 ACL 解決錯誤。
6. preflight、有序 migrations、三表 TRUNCATE RESTRICT、seed 與結構／資料／權限驗證同一交易，失敗全回滾。`schema_migrations` 記每檔 SHA-256，歷史檔漂移或不明版本拒絕；演進須新增 forward migration。
7. 表級 RLS 開啟、無外部 policy；PUBLIC／anon／authenticated 無 app schema／表存取。只有受限 owner 可建表與播種人工資料，不部署通知 RPC、不處理 Auth 使用者。

## 審查後尚待配置

以下沒有在此 PR 執行，不能將程式完成描述為遠端已啟用：

1. 隊長指定獨立、無正式使用者的空白 Demo Supabase project，審核用途、triggers／ACL，在 `targets.json` 新增 `{"project_id":"審查後20字元ref","pooler_hosts":[]}`。不得加入 Production 或既有未分類專案。
2. DBA 在專用 Demo 安裝 PostGIS 至 `extensions`，審閱並手動執行 `provision_demo.sql.example` 建受限 role、schema、唯讀 marker；密碼另走既有安全管道設定。程序不自動 provision 遠端，也不建立管理 API key。
3. GitHub 配置 protected Environment **`safe-walk-demo`**，限制 main、設定隊長／安全 reviewer；環境及白名單屬 Level C 啟用門檻。準備期間保持 repository 啟用 variable 未設定或 `false`。
4. 只在該 environment 設定 Actions Secrets：

   | Secret | 用途 |
   |---|---|
   | `DEMO_SUPABASE_PROJECT_ID` | 已審查並列白名單的 Demo ref，與 DB 標記一致 |
   | `DEMO_DATABASE_URL` | 受限 reset role 的 PostgreSQL URI，明確 port／database／verify-full；不用 postgres 管理角色或 Supabase secret API key |

   Direct 格式：`postgresql://safe_walk_demo_reset:ENCODED_PASSWORD@db.REVIEWED_REF.supabase.co:5432/postgres?sslmode=verify-full`。若 runner 無 direct IPv6，白名單列 exact session pooler host，username 使用 `safe_walk_demo_reset.REVIEWED_REF`、5432；先驗自訂 role 支援及 CA，不能停用 TLS 驗證。可用 URI `sslrootcert` 指定可信 CA。不要把 DSN 放 Variables、Flutter assets、build args、文件或對話。
5. 在隔離 Demo 完成 verify-full 連線、雙重 reset 結果一致、rollback、權限與非本專案／Auth 隔離驗收，將實際目標、source SHA、命令與證據記錄在 Level C 審查。取得隊長明確批准後才進入下一步；原專案的公開 key 不是 SQL reset 憑證。
6. **最後**建立或更新 Repository Actions Variable **`DEMO_DATABASE_RESET_ENABLED=true`**，精確小寫、不含空白。不要把旗標放在 `safe-walk-demo` environment 的 Variables 或當成第三個 Secret；job 條件讀 repository scope。這是獨立啟用動作，本 PR 不代為設定。下一次 main run 必須在 Summary 與遠端 job 顯示實際成功，才能宣稱該次 Demo 初始化完成。若需停用，經適用審查將 repository variable 設為 `false`，之後 run 會明示未重設；已啟動 run 仍使用自己的快照。

參考：[GitHub environment](https://docs.github.com/en/actions/deployment/targeting-different-environments/managing-environments-for-deployment)、[concurrency](https://docs.github.com/en/actions/how-tos/writing-workflows/choosing-when-your-workflow-runs/control-the-concurrency-of-workflows-and-jobs)、[Supabase PostgreSQL 連線](https://supabase.com/docs/guides/database/connecting-to-postgres)、[PostgreSQL advisory locks](https://www.postgresql.org/docs/17/explicit-locking.html#ADVISORY-LOCKS)。

## 驗證

```text
python3 -m pip install -r scripts/requirements-db-test.txt
python3 -m unittest discover -s scripts/tests -v
python3 scripts/reset_demo_database.py --environment ci --validate-only
```

真 DB tests 需 `RESET_TEST_DATABASE_URL`（受限 role）、`RESET_TEST_ADMIN_URL`（僅本機 disposable DB 管理連線），兩者限 loopback／`safe_walk_ci`，不准用遠端做破壞性測試。依 reusable workflow 建空白 database（template0）、執行 `bootstrap_ci.sql` 後測試。CI 明確提供兩值；缺配置／跳過 DB tests 不能算驗收。

程式只從環境讀 DSN，不接受 CLI 密碼／SQL 路徑；`--validate-only` 不連 DB，不能當遠端驗收。錯誤只輸出固定訊息／SQLSTATE，不回顯 DSN、SQL 或資料。原 PR #40 的本機缺 PostGIS、Docker daemon 未運行，DB 整合改由 disposable CI 驗證；啟用門檻修正的實跑與限制另記於自己的 PR，不沿用歷史綠燈，遠端 Demo 不會在 PR 被呼叫。
