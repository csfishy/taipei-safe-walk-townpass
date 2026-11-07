# M2｜Steven：座標運算與 RouteService

**現行政策：LIVE-FIRST DEVELOPMENT + NO PRODUCTION MOCK。** 正式入口只使用真實 OSRM／合法路網與 App 內 OSM 地圖；不導往 Google Maps 作為競賽導航。Fake／Mock／fixtures 僅限隔離測試，不作為 Live 前置版本或正式 fallback。功能須從主動定位／獨立同意、查詢、目的地選擇、真實路線到 UI 與取消／錯誤完整交付，見 [完成定義](../../../../docs/SAFE_WALK_LIVE_FIRST.md)。

所有成員均可跨 M1～M5 修改功能與相應測試，自行 AI Coding、除錯及建立 PR。修改其他模組時說明目的、影響檔案及原主要負責人，先核對進行中的 PR 避免同時改同一檔；普通 Level A 變更不需小魚事前批准，Level B 合併前確認；Level C 合併前須隊長明確授權及安全／隱私審查，正式啟用前完成適用驗收。完整規則見 [開放協作](../../../../docs/SAFE_WALK_COLLABORATION.md)。

先讀根目錄 AGENTS、[Live MVP](../../../../docs/SAFE_WALK_LIVE_MVP.md)、[Live Readiness](../../../../docs/SAFE_WALK_LIVE_READINESS.md)、[五人模組契約](../../../../docs/SAFE_WALK_MODULES.md) 與 [導航接線契約](../../../../docs/SAFE_WALK_NAVIGATION_PRESENTATION_CONTRACT.md)。初始化文件是歷史紀錄。Steven 是路線／跟隨的主要聯絡人，莅紋是正式 UI/UX 設計主要負責人，小魚是平台／共用契約主要聯絡人；這些分工不限制誰能編寫跨模組功能。

2026-11-08 盤點 main `7b99fea`（#49 恢復 `3c433001`）：OSRM、RouteFollower、OSM 店家來源已有實作；正式操作仍固定 Mock，是待修正缺口。#35 的受控 Live 接線已不在此基線，需另 PR 重用／驗證而非改旗標。本文件不將未接線能力改標 LIVE_VERIFIED。

## 主要負責人與輸入輸出

- `lib/features/safe_walk/navigation/` 與 `test/features/safe_walk/navigation/` 是主要路徑；任何成員也可為完整功能修改 platform／presentation／資料／音訊與相應測試。一般邏輯與 callback 屬 Level A，不需先由小魚批准；實際改共用契約、套件、TownPass route 或重大 UI 設計時，依 Level B 在合併前取得對應主要負責人確認。
- `RouteService.planRoute(RouteRequest request, {SafeWalkCancellation? cancellation})` 回 `Future<RouteResult>`。
- request 含 M1 提供的 origin、destination、requestId、mode、departAt、preference、繞行上限與 assistancePointIds；只消費定位，不再次要求或監聽 GPS。
- 結果為 RouteSuccess 或 RouteFailure，保留同一 requestId／mode。失敗 no_route／provider_unavailable／invalid_input／cancelled 時 routes 為空。
- 距離／秒數未知依共用模型用 null；座標內部 lat／lng、GeoJSON `[lng, lat]`，不得互換。不自造第二個 Route 或 Position model。

## Mock 與整合

Mock provider 與 DataMode.mock 保留測試相容性，但正式入口不得選用，亦不要求先完成 Mock 才做 Live。無 provider、未同意或服務失敗回 Unavailable／失敗及下一步，不用 Mock／直線冒稱真實步行網路。取消或舊請求不得覆蓋新結果；沿用既有 failure／reason，不改 wire enum。

M1 將完整據點 lookup／provider 注入本模組；不得直接 import M4 實作。途經點 ID／來源／營業狀態須核對，行政區歷史犯罪統計不能直接形成即時道路安全分數。

## 目前內容

| 檔案 | 內容 |
|---|---|
| `route_service.dart` | 共用介面 `RouteService.planRoute()`（未改動） |
| `default_route_service.dart` | `DefaultRouteService`：輸入檢查、mock／live 分流、取消、舊請求不覆蓋新結果、結果以 `routeProblems()` 驗證 |
| `walking_route_provider.dart` | `WalkingRouteProvider` 介面、`AssistancePointLookup`、`WalkingRouteNotFound`／`WalkingRouteProviderUnavailable` |
| `osrm_walking_route_provider.dart` | **真實**步行路線：OSRM foot profile（預設 routing.openstreetmap.de），需使用者同意才會送出座標 |
| `osm_convenience_store_source.dart` | **真實**便利商店（不限品牌）：OpenStreetMap／Overpass，預設只取 `opening_hours=24/7`，輸出共用 `AssistancePoint` |
| `nearby_places.dart` | `NearbyPlacesService`：列出附近真實地點（來源 ID、WGS84、取得時間、授權），營業時間未知一律標「未知」，並由地點組出 `RouteRequest` 交給 `RouteService`（不使用 Google 地圖） |
| `nearest_point.dart` | `nearestPoints()`：依直線距離排序，只回「記錄為營業中且近期檢查過」的點 |
| `json_transport.dart`、`io_json_transport.dart`、`unsupported_json_transport.dart`、`default_json_transport.dart` | 不需新套件的 HTTPS JSON 客戶端（`dart:io`；web 預覽自動改為「不可用」） |
| `consent.dart`、`cancellable.dart` | 同意例外；取消／搶先完成的小工具 |
| `mock_walking_route_provider.dart` | 僅供隔離測試與 DataMode.mock 相容性；正式入口不得使用。當前 App 固定 Mock 屬缺陷，不是允許交付的隔離模式 |
| `nearest_store_planner.dart` | `NearestStorePlanner`：找最近、營業中的便利商店，挑出實際步行最短的一間。不產生、也不開啟任何外部地圖 App 連結（比賽規定只用 TownPass 內建流程、OSM 地圖、OSRM 路線） |
| `route_follower.dart` | `RouteFollower`：把 M1 提供的位置對到路線上，算出已走／剩餘距離、剩餘時間、行進方向、偏離路線、抵達；純計算，不讀 GPS |
| `coordinate_math.dart` | 純 Dart：haversine 距離、折線長度、lat/lng ⇄ GeoJSON `[lng, lat]`、座標範圍檢查 |
| `route_reference_area_check.dart` | `compareRoutesWithReferenceAreas()`：只讀比對未改動的候選路線 geometry 與「經核對邊界」的參考範圍（多邊形），回 `noReliableArea`／`noCandidateCrosses`／`noAlternativeRoute`／`alternativeAvailable`；單一參考座標不能轉成範圍，不改寫 geometry、不評「安全」（issue #48 P0-2） |

`OsrmWalkingRouteProvider(requestAlternatives: true)` 會向 OSRM 要求伺服器自己的替代路線（`osrm-alt-N`，原樣保留）；預設關閉，伺服器可能不回任何替代路線。

## 接線方式（給 M1）

```dart
final transport = createDefaultJsonTransport(); // default_json_transport.dart
bool hasConsent() => /* 使用者已明確同意把位置送到第三方服務 */;

final stores = OsmConvenienceStoreSource(transport: transport, hasConsent: hasConsent);
final routes = DefaultRouteService(
  liveProvider: OsrmWalkingRouteProvider(
    transport: transport,
    hasConsent: hasConsent,
    pointLookup: lookupPointsFromM4, // 途經據點才需要
  ),
  pointLookup: lookupPointsFromM4,
);

// 最近的 24 小時便利商店 → 步行路線
final points = await stores.findNear(position.coordinates);
final nearest = nearestPoints(origin: position.coordinates, points: points);
if (nearest.isNotEmpty) {
  final result = await routes.planRoute(request /* destination = nearest.first.point.coordinates */);
}
```

`hasConsent` 每次請求都會重新讀取，可隨時撤回。

## 最近的 24 小時便利商店與 App 內路線

Google Maps URI 工具已移除。正式功能必須使用上節 OSM 真實店家與 RouteService，在 App 內顯示 OSRM 路線；服務失敗回 Unavailable，不以外部 Google Maps 代替完成。

```dart
final planner = NearestStorePlanner(
  find: (origin, {cancellation}) => stores.findNear(origin, cancellation: cancellation), // OsmConvenienceStoreSource
  routeService: routes, // 選用：DefaultRouteService（OSRM）
);

final result = await planner.plan(position, requestId: 'r1', mode: sw.DataMode.live);
switch (result.status) {
  case NearestStoreStatus.found:
    // result.store!.point        → 店（名稱、座標、來源限制）
    // result.store!.walkingRoute → 我們算的步行路線（可能為 null）
    // result.warnings            → 必須顯示：資料來源、營業時間未經確認…
  default:
    // result.reason 是固定、可直接顯示的說明
}
```

- 挑選：只考慮「記錄為營業中且近期檢查過」的便利商店（不限品牌）；有 `routeService` 時，對最近的 3 間逐一算實際步行距離，選最短的（一次一間，因為 `DefaultRouteService` 只保留最新請求）；都算不出來就依直線距離並在 `warnings` 說明。
- 不導往 Google Maps 或任何外部導航 App；導航只走 TownPass 內建流程、OSM 地圖與 OSRM 路線。
- 查不到店時是 `noKnownStore`（不是「附近沒有」）；沒有同意是 `consentRequired`，不會送出任何請求。

## 跟隨（follow）

`RouteFollower(route)` 對一條 `RouteCandidate` 逐筆處理 M1 給的 `Position`（`update()`，或把 M1 的 stream 交給 `follow()`），每次回 `FollowUpdate`：

| 欄位 | 意義 |
|---|---|
| `status` | `onRoute`／`offRoute`／`arrived`／`positionRejected` |
| `snapped` | 路線上最近的點 |
| `cameraCenter` | 地圖該置中的位置＝使用者真實位置（不是吸附點，避免把偏離的人畫成在路線上） |
| `distanceAlongMeters`／`remainingMeters`／`progress` | 已走、剩餘、0–1 進度 |
| `remainingSeconds` | 路線時間依剩餘距離比例估算；供應商沒給時間就是 null |
| `bearingDegrees` | 路線在該點的行進方向（0＝北、順時針），給「跟隨朝向」的地圖用 |
| `shouldReroute` | 偏離路線，需重新呼叫 `planRoute()`（起點用目前位置） |

- 偏離門檻預設 40 m；GPS 誤差更大時改用 2×精度，避免訊號飄移就誤判。抵達半徑預設 30 m，抵達後維持到 `reset()`。
- 過期、不合規或精度超過 100 m 的定位會被忽略（`positionRejected`，數值沿用上一筆），不會把進度拉走。
- 路線有重疊（來回、繞圈）時優先往前匹配，進度不會倒退跳回去。
- **不自己取得位置**：這個類別只消費平台入口提供的位置。目前 `PlatformService` 只有單次 `getCurrentPosition`；Live MVP 可先由使用者主動更新位置。若需連續定位，功能主責可在平台入口沿用 TownPass 服務，明確定義同意、啟停、背景／SOS 清理與實機驗收，不在 navigation 新增第二份 GPS watcher。

### 「真的地圖」還缺什麼（不在 M2）

- main `7b99fea` 的 `DemoMap` 已使用 flutter_map／OSM 真實圖磚，類名保留不表示仍是手繪底圖；目前缺口在 DemoGeo／示範路線覆蓋物與 Live 接線，不能為修正政策重做底圖。一般 callback／狀態修正可由任何成員實作，套件／共用契約與重大 UI 仍依 Level B。保留 © OpenStreetMap contributors 及公共圖磚使用限制。
- M3 的地圖把 `cameraCenter` 當中心、`bearingDegrees` 當朝向，用 `snapped` 以後的路線段畫「剩餘路線」即可跟隨。

## 行為

- `mock` 請求由 mock provider 回示範路線；`live` 請求沒有注入 provider 時回 `provider_unavailable`，不用 mock 或直線冒充。
- **同意**：沒有同意就不送任何請求（路線與便利商店都是）。路線服務是第三方伺服器，會收到精確的起訖座標，這是使用者必須先同意的原因。
- **隱私**：便利商店查詢只送約 1 km 網格的中心並放大半徑，不送精確位置；距離在本機計算。傳輸層的例外與日誌不含 URL 或 body。
- `invalid_input`：GPS 過期或缺欄位、live 請求用示範位置、起訖相同、途經據點查無（或沒有 lookup 可核對）。
- 路線起訖點與請求相差超過 `maxEndpointSnapMeters`（500 m）、live 路線未驗證步行路網或 provider 名稱含 mock、途經點不合規，一律 `provider_unavailable`。
- 途經據點：同時請求直接路線與經過據點的路線；繞路超過 `maxExtraDistanceMeters` 就只回直接路線並說明原因。
- 取消：進入前、據點查詢中、請求中都會回 `cancelled`（傳輸層會關閉連線）；之後才到的結果或錯誤被忽略。同一個 service 較新的請求開始後，較舊請求完成時回 `cancelled`。
- 便利商店查詢：各次呼叫擁有自己的鏡像／半徑請求；取消或回傳結果時會停止該次呼叫未使用的連線，不取消其他並行呼叫。
- 便利商店快取：只保留成功完成的資料，依網格／半徑快取 5 分鐘，沿用實際取得時間；讀取快取不更新 `retrievedAt`／`availabilityCheckedAt`。過期就重查，失敗或取消不以舊資料冒充新結果。
- 傳輸層：僅 HTTPS、不跟隨轉址、逾時 12 秒、回應上限 2 MB。
- 所有結果（含失敗）都符合共用 Schema：失敗至少一則 warning、routes 為空。

## 限制（請如實呈現給使用者）

- **路線**：`walkingNetworkVerified` 只表示用了 OSM 步行路網，不保證安全、照明、無障礙或目前可通行。預設的公共伺服器是 fair-use 示範伺服器，無可用性保證；正式使用需自架或簽約伺服器（`OsrmWalkingRouteProvider(endpoint: ...)`）。
- **24 小時便利商店**：資料是 OSM 社群標籤 `opening_hours=24/7`，未經店家確認；臺灣的標註不完整，所以清單是下限，空清單代表「沒有已知的店」而不是「附近沒有」。共用契約沒有營業時間欄位，若要更可靠需 M1 擴充 Schema、M4 提供官方資料。
- `nearestPoints` 的「最近」是直線距離；`NearestStorePlanner` 若取得路線，會比較候選的實際步行距離。未取得時的直線排序與 warnings 必須明示，不可冒稱實際步行最短。
- `steps=false`，現有 RouteCandidate 沒有逐路口指示欄位；幾何方位分段不能冒稱正式轉向導航。時間未知須保留 null，不能補示範 ETA。
- 網路層在 web 預覽不可用（會回 `provider_unavailable`）。

## 測試

`test/features/safe_walk/navigation/`：座標、`DefaultRouteService`、OSRM provider、OSM 便利商店來源、`nearestPoints`、HTTP 傳輸（對本機測試伺服器，不連外網）。

`live_smoke_test.dart` 會呼叫真實公共服務，預設跳過。PowerShell 可用 `$env:SAFE_WALK_LIVE='1'` 後執行 `flutter test test/features/safe_walk/navigation/live_smoke_test.dart`；完成後移除該環境變數。這是明確 opt-in 的 provider 測試，不是開啟 App Live。

該檔的 planner 使用 stand-in 店家、follower 使用沿 geometry 合成的位置，Overpass 案例允許 transport error；通過不等於資料來源或裝置 GPS 已驗證。一般測試的 fake transport／本機測試伺服器也不構成 LIVE_VERIFIED。需記錄測試 SHA、endpoint、日期、實際結果及限制，另完成整合與 iPhone 驗收；本次文件盤點不代表重新執行上述測試。

## 尚未完成／功能主責可直接接線

- M1 組合根已建立 `DefaultRouteService`／OSRM 並注入同一 `pointLookup`，scope 與控制器也已存在；但仍固定 Mock、兩個 readiness gates 為 false，Flow 尚未消費 scope，且沒有收到 route／routeLoading／onPlanRoute。須接上真實 GPS、明確第三方同意與 M3 真實地圖，不能只改旗標。
- M3 路線 API 已合併；Live 未配置路線時已停止 fallback 至示範路徑，示範異常與據點依模式清除。DemoMap 的固定起點、據點 L 形線與完整 Live 接線仍待驗收；正式 UI/UX 由莅紋維護。
- RouteFollower、Overpass、NearestStorePlanner 尚未接入正式操作；外部導航 URI 已移除。實機／TownPass 與真實 provider 證據不足；既往 Overpass 逾時紀錄不構成成功證據。
- pointLookup 目前只查已驗證的記憶體 Mock snapshot；Live 途經需 M4 真實來源、認可／營業與同模式檢查。便利商店／AED 不直接等於政府認證救援據點。

P0 由指定功能主責跨 platform／navigation／presentation 完成 GPS、OSRM、RouteFollower、真實地圖、同意與 Live 狀態，不必為細小接線等待另一人開 PR；P1 以同樣方式接真實據點與 App 內導航。任務 Owner、前置依賴與驗收以 Live MVP／Readiness 為準，從最新 main 建工作分支並經 PR／CI，Mock 僅保留隔離測試用途。
