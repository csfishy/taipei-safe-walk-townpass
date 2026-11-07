# M4｜信義：資料 Parser、Repository 與 fixtures

先讀根目錄 AGENTS、官方初始化文件及 [五人模組契約](../../../../docs/SAFE_WALK_MODULES.md)。不新增後端、資料庫、資料畫面或自訂色票。

## 所有權與輸入輸出

- 可改 `lib/features/safe_walk/safety_data/`，包含來源轉換工具與模組專屬 fixtures；測試使用 `test/features/safe_walk/safety_data/`。跨模組 fixtures／Schema／模型由 M1 管理。
- `SafetyDataParser.parseAssistancePoint(Map<String, Object?>)` 回共用 AssistancePoint，`parseAreaStatistics()` 回共用 AreaStatistics。來源先正規化，結構／語意驗證沿用 shared/contracts，不複製 validator 或建立第二套 model。
- `SafetyDataRepository.getAssistancePoints()`／`getAreaStatistics()` 均接 `required DataMode mode` 與選用 cancellation，回對應型別的 Future<List>。
- required nullable 欄位仍需存在；未知電話、來源更新時間、人口分母等用 null，不填假值。保留 sourceUrl、retrievedAt、dataUpdatedAt、license、coverage、limitations。

## 狀態、Mock 與整合

Repository 沒有另一份自造 success payload；解析／來源不可用／取消透過失敗 Future 區別於正常空結果，不能靜默回假成功。mock 使用共用 fixture，live 未配置不混入人工示範資料；實際 parser 錯誤依 shared/contracts 契約。

`contract_safety_data.dart` 提供最小無 UI 適配器：`ContractSafetyDataParser` 使用共用 model 的 `fromJson()` 與 `pointProblems()`／`statisticsProblems()`，結構或語意錯誤拋 `FormatException`，不吞錯或回填假值。`MockSafetyDataRepository` 只接注入模型的唯讀快照，拒絕 live 或語意錯誤的資料；不讀檔、不存檔、不做網路請求。

正常空 mock 清單回 `[]`，代表注入的示範資料集沒有紀錄；要求 live 時拋 `SafeWalkDataUnavailable`，代表來源未配置，不能解讀為附近沒有求助據點。該例外是內部執行期錯誤，不增加 Schema payload／status。已取消的 token 拋共用 `SafeWalkCancelledException`，不交付資料。

M1 注入 repo 並將結果交 M2／M3，本模組不 import 兩者實作。合作認可、營業、位置與協助能力分開記錄，歷史行政區統計不能推導即時道路風險。

## 第一輪交付

欄位對照、parser 正反案例、mock repo／取消／來源不可用測試；取得真實資料才交來源可追溯的小樣本，未取得時明列未配置。`test/features/safe_walk/safety_data/contract_safety_data_test.dart` 使用 `test/fixtures/safe_walk/` 驗證 unknown／null、strict 欄位、錯誤認可／統計、唯讀快照、mock/live 與取消；執行結果以整體初始化驗證紀錄為準，不將測試檔存在當作 PASS。真實資料與外部來源仍未接入。

預定分支 `feat/m4-safety-data`：**pending**，待初始化 PR 審查並由使用者確認合併後，才從共同 Flutter base 建立。

## 臺北市暴力犯罪月統計（`violent_crime/`）

主計處「臺北市暴力犯罪案件按月別」的 live 讀取與轉換，見 [violent_crime/README.md](violent_crime/README.md)。來源只有全市層級，因此輸出模組內 `CityMonthlyCrimeStatistics`，不是共用 `AreaStatistics`，也尚未接入 `SafetyDataRepository` 或任何畫面；契約方案待 M1 決定。
