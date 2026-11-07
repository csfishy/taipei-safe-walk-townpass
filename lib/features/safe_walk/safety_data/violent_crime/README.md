# M4｜臺北市暴力犯罪月統計（live 來源，Dart）

信義為資料主要聯絡人；所有成員均可跨來源、組合根及畫面開發完整功能與測試，依 [開放協作](../../../../../docs/SAFE_WALK_COLLABORATION.md) 說明目的、影響檔案及原負責人並避免檔案衝突。一般轉換／呈現屬 Level A，共用 Schema／Contracts／Models 變更屬 Level B；不以資料夾阻擋跨模組實作。

讀取臺北市政府主計處「臺北市暴力犯罪案件按月別」，轉成**模組內型別** `CityMonthlyCrimeStatistics`（格式名 `m4.cityMonthlyCrimeStatistics/0.1`）。在 App 內執行，不新增後端、套件或資料庫。

現行目標依 [Live MVP 規格](../../../../../docs/SAFE_WALK_LIVE_MVP.md) 與 [上線條件](../../../../../docs/SAFE_WALK_LIVE_READINESS.md)。截至 main `03f98f2b7b5254db73774c4d097eb4d610499c2c`，真實來源 Provider 已實作，狀態為 **IMPLEMENTED_NOT_WIRED**；此處「live 來源」描述讀取實作，不表示正式 App 已接線、通過 iPhone 驗收或可宣稱 LIVE_VERIFIED。

> **不是共用契約 `AreaStatistics`。** 來源只有全市數字；`AreaStatistics` 只允許行政區層級，把全市填進 district 會誤導。任何成員可提出 city 層級 Schema 變更（見文末提案），合併前須依 Level B 由共用契約主要負責人確認。在那之前本 repository 不實作 `SafetyDataRepository`，也沒有接入任何畫面或 M1 組合。

## 檔案

| 檔案 | 內容 |
|---|---|
| `violent_crime_normalizer.dart` | 純轉換：CSV 解析、民國年月 → 西元期間、剔除規則、`CityMonthlyCrimeStatistics`、`cityCrimeProblems()`；`source` 用共用 `sw.SourceMetadata` 建立並驗證 |
| `taipei_violent_crime_repository.dart` | `TaipeiViolentCrimeRepository.getMonthlyStatistics(mode:, from:, to:, cancellation:)`；live-only、6 小時記憶體快取、共用進行中的讀取、取消、`lastReport` |
| `get_connect_text_fetcher.dart` | 預設傳輸（沿用官方 App 既有 GetX），把被當成 Latin-1 解碼的 UTF-8 還原 |
| `fixtures/violent_crime_raw_sample.csv` | 來源 CSV 真實節錄 6 列（含 113 年 2 月閏月），2026-11-07 取得 |
| `fixtures/violent_crime_expected.json` | 舊 React repo Node 版對同一樣本的輸出；Dart 測試要求逐欄相同 |

## 行為

- `mode: live`：讀取並回傳月統計，舊到新；`from`／`to` 為含頭尾的 `YYYY-MM`，格式錯誤丟 `ArgumentError`。
- `mode: mock`：沒有示範資料集，丟 `SafeWalkDataUnavailable`（未配置），不回假資料。
- 讀取失敗、內容不是預期 CSV（包含未閉合引號的截斷內容）、欄位改變、或沒有任何有效列：丟 `ViolentCrimeSourceUnavailable`，訊息不含資料內容；不改用示範資料，不回空陣列冒充成功。
- 已取消的 token 丟共用 `SafeWalkCancelledException`，即使快取已填也不交付資料。

## 來源

- 資料集：https://data.taipei/dataset/detail?id=33dc5028-78ef-4892-bec6-0b459f7cb193（主計處，每月更新，政府資料開放授權條款-第1版）。
- 資料本體不在 data.taipei（`has_datastore=false`，`/api/v1/dataset/...` 回空陣列），而是臺北市統計資料庫 `tsis.dbas.gov.taipei` 的 UTF-8 CSV（伺服器標成 `application/octet-stream`、沒有 charset）。
- 先讀 `https://data.taipei/api/frontstage/tpeod/dataset.view?id=…` 取 CSV 連結、`last_modified`、授權與宣告列數；連結只接受 `https://tsis.dbas.gov.taipei`。詮釋資料讀不到時改用程式內同一個主計處連結，授權與更新時間保持 `null`。
- Flutter web 未驗證：瀏覽器 CORS 可能擋下請求，此時回報來源不可用，不會變成資料。

## 欄位對照

| 欄位 | 來源／規則 |
|---|---|
| `id` | `tpe-violent-crime-month-YYYY-MM` |
| `city` / `geographicLevel` | `臺北市` / `city`；**沒有 district** |
| `periodStart` / `periodEnd` | `統計期`「115年 8月」→ 民國 + 1911 → `2026-08-01` / `2026-08-31` |
| `aggregation` / `category` | `month` / `暴力犯罪` |
| `caseCount` | `發生件數/總計[件]` |
| `breakdown` | `強盜搶奪`、`強制性交`、`其他`（來源合併的類別，不拆分不推測） |
| `sourceReportedRatePer100k` | `發生率[件/十萬人]` 原值；刻意不叫 `ratePer100k`，因來源沒給人口分母 |
| `populationDenominator` | 永遠 `null` |
| `source` | 共用 `SourceMetadata`：`retrievedAt` 為讀取時間（+08:00），`dataUpdatedAt` 為平台 `last_modified`，授權只接受「政府資料開放授權條款」字樣 |

未使用：嫌疑犯、犯罪人口率、破獲件數與破獲率（含積案與他轄，比例可能超過 100%，易被誤讀）。

剔除（整列丟棄並列入 `lastReport.rejected`，不修補）：統計期無法解析、件數不是非負整數、總計 ≠ 三類相加、發生率超出有限數值範圍、期間重複。

## 既有驗證紀錄（2026-11-07）與現行驗收

- 以舊 React repo 的 Node 版實際讀取：116 列（106/1–115/8），宣告 116 列 → 轉換 116、剔除 0；總計與三類相加全部一致。
- 本 Dart 版：撰寫環境沒有 Flutter SDK，`flutter analyze`／`flutter test` **未在本機執行**，以 PR CI 結果為準。

上述為原交付時的事實，沒有用本次文件審查改寫。現有 `test/features/safe_walk/safety_data/violent_crime/violent_crime_normalizer_test.dart` 與 `taipei_violent_crime_repository_test.dart` 涵蓋樣本轉換、來源錯誤、快取、篩選及取消；注入的 fetcher 與 CSV fixture 不能代替 Dart 真實來源測試。

P2 由指定功能主責跨來源、組合根與資訊畫面完成交付，信義、小魚、莅紋分別是資料、共用契約、設計的主要聯絡人；普通轉換／呈現依 Level A，實際共用契約或重大 UI 變更依 Level B。接線前需確認 metadata／CSV 實際讀取、授權與來源更新時間缺值、服務不可用、格式改版、取消及 iPhone 顯示；明確標示全市／歷史／月份與限制，不產生安全路線分數。本次不修改共用 Schema；確有跨模組新欄位需求時另開 Schema PR。

## 共用契約提案（Level B，未修改 Schema／模型）

`AreaStatistics` 只允許 `geographicLevel: 'district'`，而臺北市公開的暴力犯罪統計目前只有全市層級。建議二擇一：

1. Schema 增加 `geographicLevel: 'city'`（此時 `district` 允許 `null`），`statisticsProblems()` 加上「city 層級不得有 district」；之後本模組改為輸出 `AreaStatistics` 並實作 `getAreaStatistics()`。
2. 維持現狀：全市統計只作說明文字，不進 `SafetyDataRepository`。
