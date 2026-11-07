# M2｜Steven：座標運算與 RouteService

先讀根目錄 AGENTS、官方初始化文件及 [五人模組契約](../../../../docs/SAFE_WALK_MODULES.md)。本目錄不新增地圖 Widget、route 或 GPS watcher。

## 所有權與輸入輸出

- 可改 `lib/features/safe_walk/navigation/`；測試使用 `test/features/safe_walk/navigation/`。共用契約、套件與官方 route 需求交 M1，不直接修改其他模組。
- `RouteService.planRoute(RouteRequest request, {SafeWalkCancellation? cancellation})` 回 `Future<RouteResult>`。
- request 含 M1 提供的 origin、destination、requestId、mode、departAt、preference、繞行上限與 assistancePointIds；只消費定位，不再次要求或監聽 GPS。
- 結果為 RouteSuccess 或 RouteFailure，保留同一 requestId／mode。失敗 no_route／provider_unavailable／invalid_input／cancelled 時 routes 為空。
- 距離／秒數未知依共用模型用 null；座標內部 lat／lng、GeoJSON `[lng, lat]`，不得互換。不自造第二個 Route 或 Position model。

## Mock 與整合

先使用共用 fixture 與注入 fake provider。無 live provider 明確回 provider_unavailable，不用 mock／直線路徑冒稱真實步行網路。取消或舊請求不得覆蓋新結果。

M1 將完整據點 lookup／provider 注入本模組；不得直接 import M4 實作。途經點 ID／來源／營業狀態須核對，行政區歷史犯罪統計不能直接形成即時道路安全分數。

## 目前內容（第一輪）

| 檔案 | 內容 |
|---|---|
| `route_service.dart` | 共用介面 `RouteService.planRoute()`（未改動） |
| `default_route_service.dart` | `DefaultRouteService`：輸入檢查、mock／live 分流、取消、舊請求不覆蓋新結果、結果以 `routeProblems()` 驗證 |
| `walking_route_provider.dart` | `WalkingRouteProvider`（M1 注入真實步行 provider）、`AssistancePointLookup`（M1 接 M4 的據點查詢）、`WalkingRouteNotFound`／`WalkingRouteProviderUnavailable` |
| `mock_walking_route_provider.dart` | 只供 `DataMode.mock`：起訖直線折線，`walkingNetworkVerified: false`，警示「禁止實地導航」 |
| `coordinate_math.dart` | 純 Dart：haversine 距離、折線長度、lat/lng ⇄ GeoJSON `[lng, lat]`、座標範圍檢查 |

行為：

- `mock` 請求由 mock provider 回示範路線；`live` 請求沒有注入 provider 時回 `provider_unavailable`，不用 mock 或直線冒充。
- `invalid_input`：GPS 過期或缺欄位、live 請求用示範位置、起訖相同、途經據點查無（或沒有 lookup 可核對）。
- 路線起訖點與請求相差超過 `maxEndpointSnapMeters`（500 m）、live 路線未驗證步行路網或 provider 名稱含 mock、途經點不合規，一律 `provider_unavailable`，不放行。
- 取消：進入前、據點查詢中、provider 執行中都會回 `cancelled`；之後才到的結果或錯誤被忽略。同一個 service 較新的請求開始後，較舊請求完成時回 `cancelled`。
- provider 的錯誤訊息不寫入結果（可能含座標或金鑰），只回固定說明。
- 所有結果（含失敗）都符合共用 Schema：失敗至少一則 warning、routes 為空。

測試：`test/features/safe_walk/navigation/`（`coordinate_math_test.dart`、`default_route_service_test.dart`）。

## 尚未完成／待 M1 協調

- 真實步行 provider 未接入（專案沒有 `http` 套件；新增套件與把位置送給第三方路線服務都需 M1 決定與使用者同意）。目前 live 一律 `provider_unavailable`。
- 尚未接到 `App`／presentation：M3 的 `safe_walk_demo_data.dart` 仍用示範路線，待 M1 注入 `DefaultRouteService`。
- `AssistancePointLookup` 由 M1 接 M4 的 repository 後，途經據點的來源與營業狀態才會被實際核對。
- 「最近的 7-ELEVEN」類的預設目的地查詢不在本模組；需要時由 M1／M4 決定資料來源。

預定分支 `feat/m2-navigation`。
