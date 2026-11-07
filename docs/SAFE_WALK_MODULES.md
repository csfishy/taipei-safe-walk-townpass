# 臺北安心行｜TownPass Flutter 五人模組契約

## 本次交付邊界

以官方 TownPass Flutter commit `c8e5d4d3f8f699f3d9d6cd68e129ed4da12037b3` 為基底，沿用官方 GetX、`GeoLocatorService`、`TPRoute`、服務卡、`TPColors` 及 theme。舊 React 專案保留原歷史；不將其 UI、CSS 或 Design System 套進官方 App。

本次建立無 UI 的資料契約、模組介面、最小資料 Adapter／純狀態邏輯與開發邊界。`presentation/` 只有 README，沒有新增 Widget、頁面或服務卡；不改 `main.dart`、官方 route／pages／theme，也不在初始化時取得 GPS、播放音訊、撥號或發送通報。介面宣告不是已可使用的正式功能。

初始化以 PR 交付，待審查並由使用者確認合併。下表五個模組分支均為 **pending**：確認初始化 PR 已合併後，才從相同 Flutter base 建立；不自行合併 PR，也不從舊 React main 建分支。目前不能宣稱五個遠端分支已建立或五人正式整合環境已 ready。

## 所有權與預定分支

路徑均相對於 Repository 根目錄，模組根目錄為 `lib/features/safe_walk/`。

| 模組／負責人 | 預定分支（pending） | 可修改的模組路徑 | 責任 |
|---|---|---|---|
| M1 小魚 | `feat/m1-platform` | `platform/`；統一協調共用檔與官方接線 | 平台、唯一位置取得者、求助、跨模組、route／CI |
| M2 Steven | `feat/m2-navigation` | `navigation/` | 座標運算與 `RouteService`，消費 M1 位置、不另監聽 GPS |
| M3 莅紋 | `feat/m3-experience` | `presentation/` | 唯一正式 UI/UX 設計負責人；本次只有 README，未開始 Widget |
| M4 信義 | `feat/m4-safety-data` | `safety_data/` | 來源正規化、Parser、Repository、模組 fixtures |
| M5 奶爸 | `feat/m5-companion` | `companion/` | 純控制器、Audio adapter、取消與資源清理；不做通話頁 |

M1 統一管理 `shared/contracts/`、`shared/models/`、Schema、共用 fixtures、`pubspec.yaml`／lock、CI、route、官方 service adapter 及跨模組修改。M2～M5 不直接修改官方 `lib/main.dart`、`lib/page/`、`lib/util/tp_route.dart`、theme 或色票。M3 的正式 UI 後續由本人提出，M1 協調官方接線；不能由其他模組先建立一套畫面。

每人自己的說明與測試資料放在自己的模組內。新增測試可用 `test/features/safe_walk/platform/`、`navigation/`、`presentation/`、`safety_data/`、`companion/` 對應目錄；跨模組契約測試由 M1 協調。這些是修改命名空間，不表示每個測試檔已存在或已執行。

## 單一資料契約與通用規則

- 資料型別唯讀匯入 `shared/models/safe_walk_models.dart`，建議別名 `sw`，避免與官方 geolocator 的 `Position` 撞名。不得在各模組複製另一個 Position／Route／Point model。
- JSON 解析與驗證沿用 `shared/contracts/`；M4 正規化來源後呼叫共用 model／parser，不另外維護不同欄位的 validator。契約變更由 M1 協調同步 Schema、生成模型、fixtures 與接收模組。
- 業務 payload 的 `schemaVersion` 為 `1.0.0`。經緯度使用 WGS84：內部 `Coordinates(lat, lng)`，GeoJSON 為 `[lng, lat]`；距離公尺、時間秒數，不推測未知 ETA。
- Schema 中可為 null 的欄位仍是必填 nullable；不得以省略欄位、0、空字串或 false 代替未知值。`source`／營業／認可／更新時間各自保留，不用單一「安全」boolean 取代。
- 日期與時間保留 Schema 的 RFC3339 字串及時區 offset，不以本地時間字串交換，也不因轉成 Dart `DateTime` 而丟失 wire 表示。
- `DataMode.mock` 與 `DataMode.live` 必須顯式傳遞；JSON 使用 enum 的 `wireValue`，不用 Dart `enum.name` 猜 wire 格式。mock 只用人工 fixture，不能標為官方、live 或現場資訊。
- `SafeWalkCancellation` 是共用執行期取消介面，不是 JSON payload。取消需讓延遲結果失效並清理資源，不能回假成功；不另造 AbortSignal 或跨模組 import 彼此實作。
- 位置、危難筆記及聯絡資料預設只在記憶體；不在初始化中外傳、記錄到 log、加入 URL 或長期保存。沒有官方授權，不存在警消受理／派遣成功契約。

## M1｜小魚：平台、位置、求助與整合

介面：`platform/platform_service.dart` 的 `PlatformService`。

| 項目 | 契約 |
|---|---|
| 位置輸入 | `getCurrentPosition({required DataMode mode, required bool userInitiated, SafeWalkCancellation? cancellation})` |
| 位置輸出 | `Future<LocationResult>`；`LocationSuccess` 帶共用 `Position`；`LocationFailure` 帶 status 與可讀 message |
| 位置狀態 | `denied`／`timeout`／`unavailable`／`unsupported`；沒有自造的 `cancelled` wire status |
| 求助輸入 | `requestEmergency({required DataMode mode, required EmergencyChannel channel, required bool userInitiated, required bool allowRealCalls, IncidentSummary? summary})` |
| 求助輸出 | `Future<EmergencyActionResult>`；action 為 `dial_link_activated`／`share_sheet_requested`／`cancelled`／`not_configured`／`failed`，`officialReceipt` 固定 null |
| 缺值與模式 | 位置未知不得填示範 GPS；mock 不呼叫裝置定位、不撥號。false `userInitiated` 不觸發權限或外部操作；live 仍須 `allowRealCalls` 才可能進行電話 handoff |
| 官方依賴 | `TownPassPlatformAdapter` 已建立但未註冊至官方 App；僅在 live＋明確操作時包裝既有 `GeoLocatorService.position()`，將 geolocator.Position／錯誤轉成共用結果；本次只用 fake 測試 |

位置取消可在內部拋 `SafeWalkCancelledException`，由 M1 邊界處理並忽略過期回應；需要回傳 `LocationResult` 時使用 `unavailable` 加明確取消訊息，不新增 Schema 未定義狀態。求助不得等待定位成功；若 summary 有位置，外傳仍須明確同意，OS handoff 不代表接通或官方受理。

第一輪交付：以注入的 mock／fake 驗證顯式使用者操作與模式閘門、位置成功／拒絕／取消、求助不撥號／不傳座標；列出官方 adapter 與 route 接線待辦。初始化不註冊新頁面、不觸發真實權限。

## M2｜Steven：座標運算與 RouteService

介面：`navigation/route_service.dart` 的 `RouteService.planRoute(RouteRequest, {SafeWalkCancellation? cancellation})`。

| 項目 | 契約 |
|---|---|
| 輸入 | 共用 `RouteRequest`：requestId、mode、M1 提供的 origin、destination、departAt、preference、繞行上限與 assistancePointIds |
| 輸出 | `Future<RouteResult>`；`RouteSuccess` 或 `RouteFailure`，保留同一 requestId／mode |
| 狀態 | 成功 `ok`；失敗 `no_route`／`provider_unavailable`／`invalid_input`／`cancelled`，失敗 routes 固定空 |
| 缺值與模式 | 距離／秒數未知用 null；無 live provider 回明確不可用，不將直線或 mock 路線標成真實步行網路 |
| 依賴 | 只接共用模型、取消介面與 M1 注入的 provider／據點 lookup；不得直接 import M4，不新增 GPS watcher |

座標運算可在本模組純 Dart 實作及測試；途經點 ID 需要 M1 提供完整據點 lookup 並驗證 ID／來源／營業狀態。行政區犯罪統計不作為即時逐路段安全分數。

第一輪交付：固定 request 的 mock 成功／失敗、經緯度與 GeoJSON 順序、requestId 一致、取消不回舊結果；真實 provider 尚未配置則明示。沒有地圖 Widget 或頁面交付。

## M3｜莅紋：正式 UI/UX 設計唯一負責人

本次 `presentation/` **只有 README，沒有 Widget 或控制器實作**。官方 theme、服務卡與頁面保持原狀，不套舊 React Design System。

| 項目 | 契約 |
|---|---|
| 後續輸入 | M1 提供的 `LocationResult`、`RouteResult`、`AssistancePoint`／`AreaStatistics`、`CompanionEvent`、模式與操作狀態 |
| 後續輸出 | 使用者意圖與 callbacks 交 M1 協調；不自行取 GPS、呼叫警消或直接 import M2／M4 實作 |
| 狀態與缺值 | mock／live 未配置、定位拒絕、loading、無路線、空資料、未知營業／來源必須保留真實語意；未知不能等同安全或附近無求助管道 |
| 依賴 | 沿用官方 GetX／TPColors／theme；新增 UI 與 route 要另行確認設計及整合，不在本初始化中先做 |

第一輪交付：核對資料接點、操作意圖與待設計清單，確認正式 UI 責任；本輪驗收為沒有新 UI，而不是既有官方頁面已完成安心行產品流程。後續 UI 的測試標準另由 M3 與 M1 訂定。

## M4｜信義：Parser、Repository、fixtures

介面：`safety_data/safety_data_service.dart` 的 `SafetyDataParser` 與 `SafetyDataRepository`。

| 項目 | 契約 |
|---|---|
| Parser 輸入 | 正規化後的 `Map<String, Object?>`；`parseAssistancePoint()`／`parseAreaStatistics()` |
| Parser 輸出 | 共用 `AssistancePoint`／`AreaStatistics`；格式錯誤由共用驗證拒絕，不靜默刪欄位或補假值 |
| Repository 輸入 | `getAssistancePoints()`／`getAreaStatistics()` 均顯式接 `required DataMode mode` 與選用 cancellation |
| Repository 輸出 | `Future<List<AssistancePoint>>`／`Future<List<AreaStatistics>>`；這兩個 API 沒有自造的 success status payload |
| 缺值與錯誤 | 未知時間／電話／分母依 Schema 用 null；資料不可用／解析錯誤與空結果應可區分，錯誤沿 Future 拋出，不能靜默回假成功 |
| 依賴與模式 | 共用 models／contracts；mock fixture 與 live 原始來源分開。不得自行新增後端、資料庫或官方授權聲明 |

真實來源正規化工具與模組專屬 fixtures 放本模組；共用跨模組 fixture 由 M1 管理。保留 sourceUrl、retrievedAt、dataUpdatedAt、license、coverage、limitations，不能將歷史行政區統計改成即時道路安全預測。

第一輪交付：少量可追溯來源的欄位對照、parser 正反案例、mock repo 與取消／來源不可用案例；尚無真實來源時明列未配置，不杜撰證據。M1 將結果注入 M2／M3。

## M5｜奶爸：純控制器、Audio adapter 與清理

介面：`companion/companion_service.dart` 的 `CompanionController`、`CompanionAudioAdapter`。沒有模擬電話頁、不新增音訊套件、不錄音或要求麥克風。

| 項目 | 契約 |
|---|---|
| 控制器輸入 | `start(CompanionScenario, {cancellation})`、`pause()`、`stop(CompanionStopReason)`、`dispose()` |
| 控制器輸出 | `Stream<CompanionEvent>`；state：`idle`／`playing`／`paused`／`ended`／`error`；reason 沿用共用 enum |
| Audio adapter | `playAsset(String assetPath, {cancellation})`、`pause()`、`stop()`、`dispose()`；由控制器注入，不耦合 Widget／GetX |
| 缺值與模式 | scenario 的 audioSrc 為 null 表示無錄音；回 `not_configured` reason，不冒稱播放／真人接聽。只容許經核准的本地資產，不把 wire `/audio/...` 當任意 URL 播放 |
| 取消與依賴 | M1 求助先 `stop(emergency)`；取消、卸載、隱藏及 dispose 清理音訊、計時器、事件串流與延遲 play 結果，不向平台直接撥號 |

`CompanionStopReason` 的 user／emergency／unmount／visibilityHidden 對應共用 wire 值。`not_configured` 是事件 reason，不能自造為新的 state。dispose 與 stop 須可重複安全呼叫；已取消後的 await 結果不得重啟聲音。

第一輪交付：注入 fake audio 的純控制器測試，涵蓋無音檔、使用者停止、求助中斷、取消、延遲播放、重複 dispose 與清理。本初始化另提供 `companion_state.dart` 的純狀態轉移與測試；播放中只由實際音訊回執觸發，不以使用者開始指令假裝已播放。具體控制器／audio Adapter、計時器清理與離線錄音仍待 M5 交付，不把狀態測試等同完整播放器驗收。

## PR 與整合流程

1. 先審查本初始化 PR，確認官方 base、共用契約與無 UI 邊界；不自動 merge。
2. 使用者確認合併後，M1 從同一已合併的 Flutter commit 建立五個 pending 分支，再核對遠端 SHA；各自 clone／checkout 才進行正式開發。
3. 各模組先用相同 fixture／fake，不等待其他模組完成正式功能；只經共用型別與注入介面整合。
4. 跨模組／共用 Schema／官方 route 需求先交 M1 協調；M3 唯一負責正式 UI 設計，不由其他模組先建立替代畫面。
5. PR 附分支／SHA、可重現結果、實際執行的格式／分析／測試／build、未完成與未驗事項。宣告介面、靜態閱讀或環境缺少 SDK 不得報 PASS。
