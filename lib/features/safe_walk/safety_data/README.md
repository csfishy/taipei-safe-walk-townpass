# M4｜信義：資料 Parser、Repository 與 fixtures

**現行政策：LIVE-FIRST DEVELOPMENT + NO PRODUCTION MOCK。** 真實資料來源／持久資料庫 → 經審查的受限唯讀服務 → M1 組合 → M2／M3 查詢與呈現才是完整交付。Fake／Mock／fixtures 僅供隔離測試，正式入口不得使用；來源失敗回 Unavailable＋阻塞／下一步，不 fallback。不得新增 AED，詳見 [完成定義](../../../../docs/SAFE_WALK_LIVE_FIRST.md)。

所有成員均可跨 M1～M5 修改功能與相應測試，自行 AI Coding、除錯及建立 PR。修改其他模組時說明目的、影響檔案及原主要負責人，先核對進行中的 PR 避免同時改同一檔；普通 Level A 變更不需小魚事前批准，Level B 合併前確認；Level C 合併前須隊長明確授權及安全／隱私審查，正式啟用前完成適用驗收。完整規則見 [開放協作](../../../../docs/SAFE_WALK_COLLABORATION.md)。

先讀根目錄 AGENTS、[Live MVP 規格](../../../../docs/SAFE_WALK_LIVE_MVP.md)、[上線條件](../../../../docs/SAFE_WALK_LIVE_READINESS.md)及 [五人模組契約](../../../../docs/SAFE_WALK_MODULES.md)。初始化文件僅作歷史參考。信義是真實公共安全資料主要負責人；功能主責可跨來源、組合根與畫面完成資料流程。普通轉換／callback 屬 Level A，實際改共用契約或新增依賴屬 Level B，重大正式 UI 改版由莅紋確認；色彩仍依既有規範。

## 目前基線與開發目標

盤點基線為 2026-11-08 main `7b99fea`。方向改為 Supabase 持久犯罪參考資料與 App 的受限唯讀查詢；#44 仍是開放 PR，不將其遠端匯入描述當作 App 已能讀取。#39 官方犯罪警示資料曾合到功能分支，不在目前 main；現有全市月統計仍是歷史趨勢，不能替代具可靠地理證據的範圍。沒有可信範圍時不得聲稱完成犯罪路段避讓。

| 能力 | 狀態 | 現況與缺口 |
|---|---|---|
| 真實求助據點 Repository | NOT_IMPLEMENTED | `SafetyDataRepository` 尚無 Live 實作；Parser／Mock 已接展示流程，App 仍注入 `demoAssistancePoints()`，不能標成真實據點。 |
| 全市暴力犯罪月統計 | IMPLEMENTED_NOT_WIRED | 真實來源讀取及正規化已合併，尚未接入 M1／畫面；不能再籠統寫「所有真實來源尚未實作」。 |
| 持久犯罪資料保護 | IMPLEMENTED_NOT_WIRED | #44 提供 crime_reference 隔離與私有儲存方案，尚未合 main；不得被 CI／Demo reset／seed 清除。 |
| App 犯罪唯讀 API／正式接線 | NOT_IMPLEMENTED | 目前缺經審查的公開資料投影／受限 API 與 Repository→UI 接線；App 不得持有 service_role／管理金鑰／DB 密碼。 |
| 犯罪查詢權限正式啟用 | BLOCKED | 缺公開投影範圍、角色權限與 Level C 隔離驗收；不能為趕 Live 直接開放私有表。 |

## 主要負責人與輸入輸出

- `lib/features/safe_walk/safety_data/`（來源轉換及 fixtures）與 `test/features/safe_walk/safety_data/` 是主要路徑，不是修改權限上限。任何成員可跨模組完成查詢、注入、呈現與測試；共用 Schema／Contracts／Models 屬 Level B，合併前由小魚等對應主要負責人確認，不能手改生成檔繞過。
- `SafetyDataParser.parseAssistancePoint(Map<String, Object?>)` 回共用 AssistancePoint，`parseAreaStatistics()` 回共用 AreaStatistics。來源先正規化，結構／語意驗證沿用 shared/contracts，不複製 validator 或建立第二套 model。
- `SafetyDataRepository.getAssistancePoints()`／`getAreaStatistics()` 均接 `required DataMode mode` 與選用 cancellation，回對應型別的 Future<List>。
- required nullable 欄位仍需存在；未知電話、來源更新時間、人口分母等用 null，不填假值。保留 sourceUrl、retrievedAt、dataUpdatedAt、license、coverage、limitations。

## 狀態、Mock 與整合

Repository 沒有另一份自造 success payload；解析／來源不可用／取消透過失敗 Future 區別於正常空結果，不能靜默回假成功。mock 使用共用 fixture，live 未配置不混入人工示範資料；實際 parser 錯誤依 shared/contracts 契約。

`contract_safety_data.dart` 提供最小無 UI 適配器：`ContractSafetyDataParser` 使用共用 model 的 `fromJson()` 與 `pointProblems()`／`statisticsProblems()`，結構或語意錯誤拋 `FormatException`，不吞錯或回填假值。`MockSafetyDataRepository` 只接注入模型的唯讀快照，拒絕 live 或語意錯誤的資料；不讀檔、不存檔、不做網路請求。

正常空 mock 清單回 `[]`，代表注入的示範資料集沒有紀錄；要求 live 時拋 `SafeWalkDataUnavailable`，代表來源未配置，不能解讀為附近沒有求助據點。該例外是內部執行期錯誤，不增加 Schema payload／status。已取消的 token 拋共用 `SafeWalkCancelledException`，不交付資料。

組合根注入 repo 並將結果交 navigation／presentation，任何成員均可實作此接線；safety_data 不直接 import 兩者具體實作。合作認可、營業、位置與協助能力分開記錄，歷史行政區統計不能推導即時道路風險。

## 驗收與接線要求

`test/features/safe_walk/safety_data/contract_safety_data_test.dart` 使用 `test/fixtures/safe_walk/` 驗證 unknown／null、strict 欄位、錯誤認可／統計、唯讀快照、mock/live 與取消。這些是 Parser／Mock 證據，不代表真實資料源已驗收；本次文件審查未在此處宣告新的測試 PASS。

- P0 優先完成持久犯罪資料的隔離保護、合法公開資料投影與受限唯讀介面，再接正式 App 查詢／地圖／候選路線空間比較；依 Level C 審查資料與權限，不得直接開放私有表。M4 提供來源品質聯絡，保留來源、日期、授權、涵蓋、精度與限制；模糊地址／參考座標不當精確案發點。只有可信地理範圍與真路線比較證據才能聲稱避讓。
- 據點查詢失敗、正常無資料與尚未配置須區分。不能以 AED 裝設點或一般便利商店直接冒充政府認證救援據點；認可需 `evidenceUrl`／`checkedAt`，營業與實際可協助狀態各自表達。
- 需有真實來源契約測試、斷網／格式改版／逾時／取消測試，以及 iPhone 上的來源標示、錯誤與重試驗收，才可列為 LIVE_VERIFIED。Live 失敗不得退回 Mock 假成功。
- 全市月統計僅為較低優先級歷史趨勢；不能替代 P0 持久犯罪查詢，也不能將全市數字填成行政區、道路或逐時風險，不以歷史犯罪率推算即時安全路線。

`feat/m4-safety-data` 等模組分支已存在；初始化的 pending 分支說明已不再適用。持續工作應從當時最新 main 建獨立分支並經 PR／CI 審查。

## 臺北市暴力犯罪月統計（`violent_crime/`）

主計處「臺北市暴力犯罪案件按月別」的 live 讀取與轉換，見 [violent_crime/README.md](violent_crime/README.md)。來源只有全市層級，因此輸出模組內 `CityMonthlyCrimeStatistics`，不是共用 `AreaStatistics`，也尚未接入 `SafetyDataRepository` 或任何畫面；任何成員可提出契約方案；若修改共用 Schema／Contracts／Models，按 Level B 在合併前由對應主要負責人確認。
