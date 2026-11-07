# 臺北安心行：JSON Schema 與 Dart 契約

本文件只定義資料與驗證接點，不建立畫面、Widget、Theme 或音訊／導航產品功能。

此為文件範圍，不是禁止實作產品功能。現行驗收見 [Live MVP](SAFE_WALK_LIVE_MVP.md)，實際狀態見 [Readiness](SAFE_WALK_LIVE_READINESS.md)。本次不更改 Schema；Unavailable 是能力／錯誤呈現語意，不新增既有 mock/live wire enum。必要新 payload 欄位另開 Schema 變更。

## 來源與單一來源

canonical payload 為 `schemas/safe_walk/v1/contracts.schema.json`，原始版本 `1.0.0`、Draft 2020-12。Schema、16 個引用入口及 fixtures 均從 Legacy Repository 原樣保留；不是把 TypeScript 或 React 元件機械轉成 Dart。

- Legacy Repository：<https://github.com/csfishy/taipei-safe-walk>
- 固定來源 Commit：`2b13a9f5d18ad35ec0855dc3f9d8ea73c054b723`
- Schema Git blob：`98d61b1fb387a979e1fddfac667769443f8525bb`
- Schema SHA-256：`936beecdec368a917ddc042272ffdc94d9fd46d6c2116c4db8cff5278f0ff4d0`
- 所有 Schema／fixture 原始 SHA-256：`schemas/safe_walk/v1/source-manifest.json`
- Flutter 官方基底與來源另外見 `SAFE_WALK_UPSTREAM.json`；不要混淆官方 App Commit 與 Legacy payload 來源。

人工只維護 canonical Schema。`tool/generate_safe_walk_contracts.dart` 讀取 Schema，生成 runtime schema bundle、immutable typed models、enum wire mappings、sealed unions 與 inline nested models；生成檔不手改。

```text
schemas/safe_walk/v1/contracts.schema.json
  ├── lib/features/safe_walk/shared/contracts/schema_generated.dart
  └── lib/features/safe_walk/shared/models/safe_walk_models_generated.dart
```

生成檔刻意不使用上游忽略的 `*.g.dart`／`*.gen.dart` 檔名。runtime bundle 從相同 JSON 生成，不需要改官方 pubspec assets。生成器只使用 Dart 標準函式庫，未新增套件；官方既有 json_serializable 保留原用途。

## Schema → Dart 對照

唯一型別入口：`lib/features/safe_walk/shared/models/safe_walk_models.dart`。建議 `import ... as sw`，避免與官方 geolocator 的 `Position` 撞名。

| Schema 定義 | Dart 模型／接點 |
|---|---|
| Position | `Position`；位置來源、精度與原始觀測時間分別保留 |
| LocationResult | sealed `LocationResult` → `LocationSuccess`／`LocationFailure` |
| AssistancePoint | `AssistancePoint`；營業與認可為獨立資訊 |
| AreaStatistics | `AreaStatistics`；只允許行政區月／年歷史資料 |
| RouteRequest | `RouteRequest`；mode、requestId、起終點與途經 IDs |
| RouteCandidate | `RouteCandidate`；路網來源、geometry 與限制說明 |
| RouteResult | sealed `RouteResult` → `RouteSuccess`／`RouteFailure` |
| IncidentSummary | `IncidentSummary`；預設只在記憶體，不表示官方已受理 |
| EmergencyActionResult | `EmergencyActionResult`；`officialReceipt` 型別固定 `Null` |
| CompanionScenario | `CompanionScenario`；inline `CompanionStep` 也由 Schema 生成 |
| CompanionEvent | `CompanionEvent`；`CompanionState` 與 `CompanionReason` 分開 |
| AppEvent | sealed `AppEvent` → `LocationUpdatedEvent`／`RouteCompletedEvent`／`EmergencyOpenedEvent`／`CompanionChangedEvent` |
| Coordinates（nested） | `Coordinates(lat, lng)`；具名 WGS84 座標 |
| SourceMetadata（nested） | `SourceMetadata`；取得時間不等於原資料更新時間 |
| Recognition（nested） | sealed `Recognition` → `ConfirmedRecognition`／`UnconfirmedRecognition` |
| LineString（nested） | `LineString`；Dart `GeoJsonCoordinate` named record 以 longitude／latitude 表達，wire 仍為 `[lng, lat]` |

16 個 Schema defs 都有 `.fromJson(Object?)` 與 `.toJson()`；成功、失敗與各事件以 `is`／Dart pattern switch 區分，不假設 sealed base 的所有分支都有相同欄位。具體模型也提供 named typed constructor；建構與解析都先驗證。constructor 只自動供應 Schema 常數，例如 schemaVersion、固定 null 與失敗空 routes，不補未知業務值。

```dart
final sw.Position position = sw.Position.fromJson(positionJson);
final sw.RouteResult result = sw.RouteResult.fromJson(routeJson);
switch (result) {
  case sw.RouteSuccess():
    // 消費 result.routes；不因此推定道路安全。
    break;
  case sw.RouteFailure():
    // 消費 result.status／reason；routes 固定為空。
    break;
}
```

`shared/contracts/safe_walk_contracts.dart` 另提供 typed descriptor：`parseContract(SafeWalkContracts.assistancePoint, normalizedJson)`。動態 fixture 邊界可用 `parseContractByName(name, value)`，產品程式優先使用 typed descriptor 或模型 factory，不以 cast 假裝 JSON 已驗證。

## 不可弱化的 wire 規則

- 所有 24 個 object 節點拒絕未知欄位。nullable 欄位仍須存在；缺欄位與明確 null 是不同情況。不能自動刪掉個資欄位後假裝輸入合格。
- Dart `double` 對應 finite JSON number；`int` 對應數學上為整數的 JSON number，包括 `1.0`。NaN／Infinity 拒絕，不將錯誤數字改為 0。
- 字串長度依 Unicode code point 計算；不是 Dart UTF-16 `String.length`。
- 時間保留原始 `String`／`String?`，不自動重寫 offset。日期需實際合法，不能僅用會正規化非法日期的 `DateTime.tryParse()`。相容原 AJV 的 `t`／單一空白 separator；Schema 本身仍要求明確 `Z` 或時區 offset。
- URI 保留原字串並檢查原有 format／HTTPS pattern；沒有宣稱網址可達、證據真實或獲得政府授權。
- `DataMode.mock/live` 明確分離。enum 使用 `.wireValue`，不要拿 `.name` 當 JSON：`EmergencyChannel.police/fire/trustedContact` 分別是 `110`／`119`／`trusted_contact`；`visibilityHidden` 等保留 snake_case wire 值。
- `RouteFailure` 不可能帶成功路線；`LocationFailureStatus` 沒有自造 cancelled。官方受理、派遣與案件編號不在本版契約，`officialReceipt` 永遠 null。
- 認可 confirmed 仍必須有 evidenceUrl 與 checkedAt；一般便利商店不自動變合作安全站。
- 音檔 wire `/audio/...` 保留為邏輯本地資產路徑；驗證格式不代表檔案存在、已授權或已播放。M5 已有控制器 allow-list 映射接點，具體核准資產／播放器仍待交付；已接裝置 TTS 是程序內另一能力，不需為此改音檔欄位。

## 結構與語意分層

`schema_validator.dart` 是針對這份凍結 Schema 的小型、零依賴 validator，不宣稱是通用完整 Draft 2020-12 引擎。它支援實際使用的 `$ref`、oneOf／anyOf、const／enum、required／additionalProperties、數字範圍、字串長度／pattern／date／date-time／URI，以及陣列長度／uniqueItems／prefixItems／items:false；遇到未支援驗證 keyword 會拒絕，不能靜默略過。

`semantics.dart` 保留原六組純檢查，沒有網路、儲存或 logging：

| 函式 | 必須維持的意義 |
|---|---|
| `positionProblems(position, {now})` | GPS 必有精度與時間；超過 60 秒需刷新；未來 30 秒容忍界線保留，測試可注入 now |
| `sourceProblems(source)` | live 必有來源 URL；URL 存在仍不等於來源已查證 |
| `pointProblems(point)` | 非未知營業有確認時間；合作商店有認可；mock 不可宣稱官方認可 |
| `statisticsProblems(statistics)` | 期間順序與人口分母；沒有逐街／逐時治安分數 |
| `routeProblems(result, {points})` | live 步行 provider／geometry、途經 ID、mock/live 混用與已知關閉據點 |
| `shareProblems(summary)` | mock 不外送；有位置須明確同意；在每次外傳前檢查，不只建立草稿時檢查 |

結構合格不等於語意合格。M4 parser 需接著呼叫相應語意檢查；M1／M2 在跨資料及外傳邊界執行相應檢查。未知營業不能被解讀為現在有人，行政區統計也不能保證即時道路安全。

`ContractFormatException` 只含欄位路徑與規則描述，不把拒絕的 note／位置 payload 放在 exception.source 或錯誤訊息。

## 非 JSON 的取消協定

`shared/contracts/cancellation.dart` 提供 `SafeWalkCancellation.isCancelled`、`whenCancelled`、`throwIfCancelled()` extension，以及 `SafeWalkCancelledException`。這是程序內部取消訊號，不是新的 Schema payload。

Route 取消回既有 `cancelled`；Location 沒有該 wire status，由 M1 邊界處理例外或回 `unavailable` 加清楚取消訊息。`CompanionStopReason` 是原 CompanionReason 的 user／emergency／unmount／visibility_hidden 子集合。取消與停止不能讓遲到結果重新啟動定位、音訊或外部動作。

## 重產與驗證

依官方 `.fvmrc` 使用 Flutter 3.47.6／Dart 3.13.5：

```text
dart tool/generate_safe_walk_contracts.dart
dart tool/generate_safe_walk_contracts.dart --check
dart analyze lib/features/safe_walk/shared tool/generate_safe_walk_contracts.dart
flutter test test/features/safe_walk/contracts --no-pub
```

`test/fixtures/safe_walk/` 原樣保留 12 個 valid＋13 個 invalid 案例與 manifest。manifest 內原 `fixtures/` 相對路徑由測試 loader 映射，不修改 fixture 內容；valid 逐筆解析再 roundtrip，invalid 必須拒絕。另驗證四個 sealed unions、額外／缺少欄位、immutable collections、GeoJSON、有限數字、日期／URI、Unicode 長度、假受理、取消與上述語意。

命令與案例清單不是 PASS 宣告；初始化結果留在 `SAFE_WALK_INITIALIZATION.md`，後續結果以各 PR／CI 與 [Readiness](SAFE_WALK_LIVE_READINESS.md) 為準。這些純資料測試不啟動官方登入、GPS、電話、音訊或任何新 UI。

依 [協作規範](SAFE_WALK_COLLABORATION.md)，任何成員可開發 Schema／契約變更，合併前由主要負責人 M1 確認（Level B），不要求小魚親自撰寫。必須同步 generator 映射、validator 支援、fixtures、語意測試與接收模組，再重產並執行 `--check`；不先手改生成 Dart 繞過契約，涉及敏感外部作用另依 Level C。
