# 北北基犯罪參考資料庫與封裝隔離

本文件適用 2026 年臺北市、新北市、基隆市已取得的官方公開案件資料與地點參考定位。資料來源的公布類型、日期與範圍不同，不代表三市全部犯罪案件，也不是即時犯罪或道路安全評分。查詢文件保留來源 URL、來源列、原始位置文字及資料取得時間；未收錄不代表零案件。

## 既有 Supabase 主庫

使用者指定使用既有 Supabase 專案，資料存於獨立 private `crime_reference` schema，採不可變的版本化 snapshot。此文件定義操作邊界；遠端 schema、匯入筆數與權限的實際驗證應另附執行證據，不能以本機 SQLite 測試宣稱雲端已完成。

- `crime_reference` 與 Demo 的 `safe_walk_demo`、既有通知資料及 App 業務表分開。保留既有專案，不建立替代雲端專案，不擴大 PR #40 的 Demo reset。
- 表級 RLS 保持啟用；撤銷 `anon`／`authenticated` 的 schema／table／function 權限。不新增公開 RPC、Data API 權限或 App 直連。RLS 不能取代 schema／table grants；可信管理者權限仍須另行保護。
- 只有可信、明確授權的手動匯入可以新增一個唯一 snapshot version；輸入須先驗來源、2026 日期、城市、座標及定位證據。版本重複須拒絕，不做 upsert、覆寫或重設舊版本。
- 受控管理／匯入 SQL 放在 `supabase/crime_reference/`，由授權人員檢視後於已認證管理環境執行。此目錄不是會自動套用的 `supabase/migrations/`；禁止 workflow 呼叫、`supabase db push` 或全庫 reset 自動套用。
- 不將管理密碼、連線字串、service-role key 放進 Git、HTML、App、命令歷史或 CI。此變更不新增 CI 雲端憑證。

**build、CI、App 啟動、測試初始化、Demo seed／reset 一律不能寫入或重建 `crime_reference`。** 不得因重跑測試而 import、seed、update、delete、truncate、drop 正式參考資料。資料更新是獨立、受控、可查證的人工工作，不是部署的一部分。

### 2026-11-07 實際快照

依使用者指定，已在既有專案 `gxofnhzkqcmzrftxqddi` 人工建立私有三表並匯入快照 `5ea3810c-5744-4b89-baad-0121c8fc951b`；[Dashboard 驗證查詢](https://supabase.com/dashboard/project/gxofnhzkqcmzrftxqddi/sql/062f1713-c5cd-459c-abbd-150f19519259) 需要既有帳號權限。資料及定位證據不放入 Git。來源共 8 個資料集、10 個資源；以下是來源紀錄數，跨來源缺少共同案件 ID，未宣稱案件去重。

| 事件所在城市 | 來源紀錄 | 參考定位 | 空座標 |
|---|---:|---:|---:|
| 臺北市 | 617 | 560 | 57 |
| 新北市 | 970 | 806 | 164 |
| 基隆市 | 955 | 0 | 955 |
| 合計 | 2542 | 1366 | 1176 |

臺北包含新北來源中實際位於臺北的 13 筆；原新北來源中另 11 筆外縣市紀錄已排除。臺北六類來源實際案件截至 9 月 29 日、新北來源截至 6 月 30 日、基隆警政署三季來源截至 9 月 30 日，並非全年或全部案類完整資料。

官方案件檔均未提供原生座標。參考定位採臺北／新北官方門牌數值資料及官方捷運出入口資料的離線比對；無法匹配、候選坐標衝突或過度寬廣者留空。5 公里候選分布上限只是人工複核門檻，不是來源精度或誤差半徑。臺北門牌來源未明列 CRS，保留依政府地址標準推定 TWD97/TM2 121 與官方已知地址交叉核對的限制。整條道路的門牌集合只作原文地點參考，不能當成已確認的犯罪路段或避讓區域。

已實跑 10 項遠端唯讀檢查：筆數／城市／來源、參考與空座標、三表 RLS＋FORCE、PUBLIC／anon／authenticated／service_role 無 schema／表／函式存取權、不可修改 trigger、typed 欄位與完整 payload 相等（0 差異）、範圍及快照雜湊。初次 CSV 只完成 202 筆，已核對既存整列相等，以分批交易只補缺失主鍵，逐批完整比對後提交；沒有覆寫或刪除已匯入紀錄。

原快照 JSON SHA256：`2b52dde2183dac395edbe1d6b63bc6e2498aad88ece1765100894ba36819b776`；來源 manifest SHA256：`67f87f2e8966e3667bf2ee66bf5531ca144031ea2928a371cd106a8e8acc9344`。DB JSONB fingerprint 為 `a3c1f7932c5e97d0d1028673bf424be6e32e895deb1ebee51c8426f7b068e5e1`，其序列化與原 JSON 檔不同，不能宣稱兩種 hash 相等。

三表拒絕 UPDATE／DELETE／TRUNCATE；具管理權限的 postgres 仍可能新增資料或修改 DDL，不能將此稱為管理者無法更動的儲存。舊 snapshot 不追加仍依人工版本流程、來源雜湊及期望筆數驗證。沒有執行破壞性遠端測試，也未接 App/API、導航或實機驗收。

## 地點與座標語意

原始官方地點保留不動。來源原生經緯度與後續核對的參考定位分開計數：`source_provided` 表示來源提供；`reference_geocoded` 只代表原始文字對應的參考位置，**不是精確犯罪發生點**。無法確認就保留 null，不以行政區中心補座標。

每筆參考定位記錄方法、圖資名稱／URL／ID、核對時間、精度標籤、候選數與限制。`confidence` 的 high／medium 是文字與參考位置匹配的信心，不能解讀為案件發生位置的確定度。`uncertaintyMeters` 未知就是 null；候選位置分布半徑 `candidateExtentRadiusMeters` 不是來源保證的誤差範圍。行政區、模糊文字與未解析地點不能作為精確路段避讓資料。

## 可選的離線唯讀備份

`tool/crime_reference_store.py` 是獨立離線 SQLite 工具，供版本化備份、查詢與匯出文件，不是 Supabase 主庫的替代品，也不接 App、build、deploy、seed 或 Demo reset。DB 實體檔必須在 **所有 Git checkout／worktree 外**，不能僅靠 `.gitignore` 放在 checkout 裡。

PowerShell 範例：以下資料根目錄是專案 checkout 的同層目錄；依實際環境調整，確認其任何祖先都沒有 `.git`。

```powershell
$crimeDataRoot = 'D:\Users\csFishy\Documents\GitHub\.local-data\nnk-crime-reference'
$crimeSnapshot = Join-Path $crimeDataRoot 'nnk-crime-2026-20261107-v1.sqlite3'
$crimeInput = 'C:\path-outside-git\nnk-crime-2026.json'
$crimeExport = 'C:\path-outside-git\nnk-crime-query'
$crimeTemplate = 'C:\path-outside-git\index.template.html'

# 一次性的明確新增；目的檔存在或 CI=true 時必須拒絕。
python tool/crime_reference_store.py import-new --database $crimeSnapshot --input $crimeInput --allow-write

# 讀取與匯出使用 SQLite mode=ro；不修改 snapshot。
python tool/crime_reference_store.py query --database $crimeSnapshot --city 臺北市 --text 中山 --limit 20
python tool/crime_reference_store.py export --database $crimeSnapshot --output $crimeExport --template $crimeTemplate
```

下一次更新使用新檔名、新版本，不能刪除、解鎖或覆寫既有檔以重跑匯入。工具拒絕 CI 匯入及 checkout 內 DB；成功建立後設為唯讀，query／export 用 read-only URI，匯出前後確認 DB hash。HTML／JSON 匯出目錄亦與 App 封裝分開；匯出不會把 SQLite 加入產品。

## 必要 Guard 與 CI

```sh
python3 tool/check_crime_database_isolation.py
python3 -m unittest discover -s tool -p 'test_crime_database_isolation.py' -v
python3 tool/check_crime_database_isolation.py --archive /path/to/package.zip
```

Guard 不連接 Supabase、不開啟外部 DB。它只讀 Git 列出的 checkout 檔案、Flutter assets 與明確指定的 ZIP 容器：

- 阻擋已追蹤的 SQLite magic header，以及 `nnk-crime*.sqlite*`／sidecar、`.local-data/`、`crime-reference-data/`。
- 包含未追蹤／被忽略的 Flutter assets；不跟隨外部 symlink。即使資料檔改副檔名，SQLite header 仍會被拒絕。
- Web ZIP、APK、IPA 不解壓落地，檢查內部路徑與 SQLite header；無法驗證的 ZIP 視為失敗。
- 檢查 SQL／shell 的直接 `crime_reference` 寫入，只放行受控手動 SQL；workflow／本機 action 不得呼叫該目錄、import-new 或全庫 Supabase reset／push／migration-up。

此檢查是直接寫入與封裝防線，不是完整 SQL／shell 安全分析器；動態拼接、任意程式與具管理權限的人員仍須人工審查及遠端最小權限。`.gitignore`、`export-ignore` 與 CI Guard 也不能取代 DB 的實體隔離及 RLS／grants。

`build.yml` 在所有平台依賴的 check job 最先執行 Guard，且在 Web ZIP／release APK／IPA 上傳前再次檢查。`safe_walk.yml` 同樣在 checks 先驗，選用 debug APK 上傳前再驗。單元測試只使用臨時 Git、人工 header bytes 與 ZIP，不載入真實案件或資料庫。CI 不執行資料匯入、不取得正式 DB credentials，也不將這些檢查稱為真實 Provider／iPhone 驗收。
