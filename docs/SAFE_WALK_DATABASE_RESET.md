# CI／Demo 資料庫重設（Level C 待審查）

本程序原始開發基準 main `c441070`，由 #40 合入；以下是 main `7b99fea` 仍保有的工作流及隔離重設設計。影響 M1 的 CI、隔離資料庫權限及人工位置 fixture，屬 Level B/C；遠端白名單仍空。本次文件不配置遠端 Secrets、啟用重設或放寬保護。#47 的明確啟用修正仍待合併，不能將其 variable／disabled 放行行為描述為目前 main 已有。

依 [LIVE-FIRST／NO PRODUCTION MOCK](SAFE_WALK_LIVE_FIRST.md)，這裡的 Demo／seed 僅用於隔離初始化、安全及可重複測試，不是 Production 使用者資料來源。主 App 不消費 `safe_walk_demo`，人工 seed 不能接到正式畫面；初始化成功、CI build 或 Demo 重設成功均不證明正式 Provider／業務資料已驗收。正式持久資料以 Supabase 主庫為整合方向，#44 尚待合併及 Level C 審查，不在本程序自動授權範圍。

## 資料盤點與範圍

- 原有 Supabase client 透過 PostgREST，只有 `supabase/nearby_emergency.sql` 定義 `public.helpers`、`public.emergency_alerts`、`public.alert_recipients` 與三個 RPC。原有架構沒有 Supabase CLI config、正式 migrations 或 seed（不含本程序新增的 `supabase/demo/`）；Repository 定義不證明遠端已部署哪些表。
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
  C --> D[既有分析與 Flutter tests]
  D --> E[Web／Android／iOS 並行建置]
  E --> F{main push／main 手動?}
  F -->|是| G[專用 Demo：一次 migration／reset／seed／verify]
  G -->|成功| H[既有發布／Pages]
  G -->|失敗或缺配置| I[阻擋後續發布／部署]
  F -->|PR／其他手動| J[僅 artifacts，無遠端重設]
  F -->|版本 tag| K[既有 tag 發布，無遠端重設]
```

兩份工作流都先呼叫 `demo_database_ci.yml`，在獨立 job 建 runner-local PostGIS 17 與 `safe_walk_ci`；PR（含 fork）完全沒有 Demo Secrets。CI 初始化 PostGIS／受限角色／標記，再重設並執行真 DB integration tests。容器隨 job 銷毀。

只有 `build.yml` 的 **單一 `demo-database-reset` job** 可連遠端，僅 main push／main 的 workflow_dispatch，必須 check、Web、Android、iOS 都成功。三平台不各自重設，`safe_walk.yml` 沒有遠端 job。main prerelease／Pages 依賴 reset 成功；缺配置會失敗，不會跳過後繼續部署。既有 tag 發布保留但不重設共享 Demo。

跨 workflow 共用 concurrency group `safe-walk-demo-database`、`cancel-in-progress: false`，DB 內另用交易 advisory lock；鎖已占用即失敗，稍後明確重試。GitHub 可能以新 run 取代舊 pending job，被取消／失敗的 reset 不放行部署。共享 Demo 保證每次成功重設後的初始狀態一致；新成功 build 可以更新共同 Demo，不代表各舊版本永久有獨立 snapshot。

## Fail-closed 防線

1. 只接受明確 `ci`／`demo`、GitHub Actions repository、environment 與 Project ID。CI 僅 loopback `safe_walk_ci`；Demo 僅 main 的受信事件。
2. Demo ref 必須在 `supabase/demo/targets.json` 唯一列出，DSN host、專用 username 與 ref 一致。遠端只允許 direct／session pooler 5432、`sslmode=verify-full`；禁止 transaction pooler、hostaddr／service／options 或環境 PG 連線覆寫。
3. 白名單目前為空，**未啟用遠端重設**。原專案 `gxofnhzkqcmzrftxqddi` 用途未經獨立 Demo 驗證，列程式及 manifest 保護清單，不猜測其可清除性。
4. DB 必須先由 DBA 獨立 provision `safe_walk_demo_control.target` 單一標記（environment、project_id、repository）；reset 程式不能建立或修改標記，錯配即停止。
5. `safe_walk_demo_reset` 只擁有 app schema，不得有 superuser、CREATEDB、CREATEROLE、BYPASSRLS、replication 或角色繼承，也不能寫 Auth／其他 schema。PostGIS 須預先在 `extensions`。未審查 event trigger、app trigger、跨 schema FK、未知 objects／RPC 會停止，防間接副作用；不自動修改其他 schema 的 ACL 解決錯誤。
6. preflight、有序 migrations、三表 TRUNCATE RESTRICT、seed 與結構／資料／權限驗證同一交易，失敗全回滾。`schema_migrations` 記每檔 SHA-256，歷史檔漂移或不明版本拒絕；演進須新增 forward migration。
7. 表級 RLS 開啟、無外部 policy；PUBLIC／anon／authenticated 無 app schema／表存取。只有受限 owner 可建表與播種人工資料，不部署通知 RPC、不處理 Auth 使用者。

## 審查後尚待配置

以下沒有在此 PR 執行，不能將程式完成描述為遠端已啟用：

1. 隊長指定獨立、無正式使用者的空白 Demo Supabase project，審核用途、triggers／ACL，在 `targets.json` 新增 `{"project_id":"審查後20字元ref","pooler_hosts":[]}`。不得加入 Production 或既有未分類專案。
2. DBA 在專用 Demo 安裝 PostGIS 至 `extensions`，審閱並手動執行 `provision_demo.sql.example` 建受限 role、schema、唯讀 marker；密碼另走既有安全管道設定。程序不自動 provision 遠端，也不建立管理 API key。
3. GitHub 配置 protected Environment **`safe-walk-demo`**，限制 main、設定隊長／安全 reviewer；環境及白名單屬 Level C 啟用門檻。
4. 只在該 environment 設定 Actions Secrets：

   | Secret | 用途 |
   |---|---|
   | `DEMO_SUPABASE_PROJECT_ID` | 已審查並列白名單的 Demo ref，與 DB 標記一致 |
   | `DEMO_DATABASE_URL` | 受限 reset role 的 PostgreSQL URI，明確 port／database／verify-full；不用 postgres 管理角色或 Supabase secret API key |

   Direct 格式：`postgresql://safe_walk_demo_reset:ENCODED_PASSWORD@db.REVIEWED_REF.supabase.co:5432/postgres?sslmode=verify-full`。若 runner 無 direct IPv6，白名單列 exact session pooler host，username 使用 `safe_walk_demo_reset.REVIEWED_REF`、5432；先驗自訂 role 支援及 CA，不能停用 TLS 驗證。可用 URI `sslrootcert` 指定可信 CA。不要把 DSN 放 Variables、Flutter assets、build args、文件或對話。
5. 在隔離 Demo 完成雙重 reset、rollback、權限及隔離驗收後才啟用 main；原專案的公開 key 不是 SQL reset 憑證。

參考：[GitHub environment](https://docs.github.com/en/actions/deployment/targeting-different-environments/managing-environments-for-deployment)、[concurrency](https://docs.github.com/en/actions/how-tos/writing-workflows/choosing-when-your-workflow-runs/control-the-concurrency-of-workflows-and-jobs)、[Supabase PostgreSQL 連線](https://supabase.com/docs/guides/database/connecting-to-postgres)、[PostgreSQL advisory locks](https://www.postgresql.org/docs/17/explicit-locking.html#ADVISORY-LOCKS)。

## 驗證

```text
python3 -m pip install -r scripts/requirements-db-test.txt
python3 -m unittest discover -s scripts/tests -v
python3 scripts/reset_demo_database.py --environment ci --validate-only
```

真 DB tests 需 `RESET_TEST_DATABASE_URL`（受限 role）、`RESET_TEST_ADMIN_URL`（僅本機 disposable DB 管理連線），兩者限 loopback／`safe_walk_ci`，不准用遠端做破壞性測試。依 reusable workflow 建空白 database（template0）、執行 `bootstrap_ci.sql` 後測試。CI 明確提供兩值；缺配置／跳過 DB tests 不能算驗收。

程式只從環境讀 DSN，不接受 CLI 密碼／SQL 路徑；`--validate-only` 不連 DB，不能當遠端驗收。錯誤只輸出固定訊息／SQLSTATE，不回顯 DSN、SQL 或資料。本輪實跑與限制記於 PR；本機缺 PostGIS、Docker daemon 未運行，完整 DB 整合由 PR disposable CI 驗證，遠端 Demo 不會在 PR 被呼叫。
