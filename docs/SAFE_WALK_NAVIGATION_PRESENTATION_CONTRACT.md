# M1／M2／M3 導航接線契約

2026-11-07（Asia/Taipei），稽核基線 `origin/main`：`03f98f2b7b5254db73774c4d097eb4d610499c2c`。現行目標為 [Live MVP](SAFE_WALK_LIVE_MVP.md)，啟用證據見 [Live Readiness](SAFE_WALK_LIVE_READINESS.md)。本次只改文件，不開啟 Live。正式 UI/UX、地圖與可讀性由 M3 莅紋維護；M1 負責組合及接線，M2 負責路線與跟隨計算。

## 已合併程式與缺口

| 範圍 | main 實況 | 尚缺交付 |
|---|---|---|
| TownPass 入口 | 城市服務／首頁已連到 `SafeWalkCompositionRoot` → `SafeWalkFlow`。 | 保留原生殼、GetX route、Theme 與品牌。 |
| M2 路線 | `DefaultRouteService`、`OsrmWalkingRouteProvider`、座標驗證、取消及同意檢查已存在；組合根已建立 OSRM provider。 | 真實 provider 證據、GPS 與正式地圖操作接線；不是尚未實作 OSRM。 |
| M1 控制 | `SafeWalkNavigationController`／`SafeWalkNavigationScope` 已提供結果、loading、同意、取消及 lifecycle callbacks；背景會取消並鎖 inactive。 | Flow 尚未消費 scope，組合根也未傳 `route`／`routeLoading`／`onPlanRoute`。scope tests 不等於 UI 操作端到端驗收。 |
| M3 介面 | 已合併 `SafeWalkFlow(route: RouteResult?, routeLoading: bool, onPlanRoute: ValueChanged<Coordinates>?)`、`RouteState` loading／failure／success；`_go(map)` 在使用者進入地圖才呼叫 callback，目前沒有初始化 post-frame 規劃。 | 保留 API，由 M1 adapter 接線，補同意／撤回、取消及 lifecycle。舊「M3 尚未合併／無路線介面」已失效。 |
| 地圖與模式 | #29 底圖增量保留 `DemoMap` 類名，renderer 已改用 flutter_map／OSM 圖磚與座標投影；Flow 的路線/點位仍 Mock，缺位置／據點仍可補 Demo。據點切換只改 `_pointIndex`、畫 `DemoGeo.lRoute`。 | 沿用已接 renderer，補正式 geometry／viewport／標記整合、Live 缺值分流及所有目的地事件接線；底圖與 iPhone 驗收待完成。 |
| 距離／時間 | 已能讀 route 距離、秒數與第一則 explanation；duration null 仍以 `walkMinutes` 補值，據點卡也用直線距離換算分鐘。 | Live 未知時間保留未知、完整 warnings／provider、直線距離明確標示；不顯示虛構避讓件數與地標。 |
| 跟隨 | `RouteFollower` 已有進度、偏離、抵達與 remainingSeconds 計算及測試。 | 尚未接 App；先支援使用者主動更新位置。若需連續定位，由 M1 沿用 TownPass 服務定義啟停／同意，M2 不另開 GPS。 |
| 便利商店／外部導航 | `OsmConvenienceStoreSource`、`NearestStorePlanner`、`googleMapsWalkingUri` 已存在。 | 尚未接組合根或正式操作；便利商店不是政府認證救援據點。 |

目前組合根固定 `DataMode.mock`、`livePresentationReady: false`、`liveProviderReady: false`，定位、據點讀取及 Flow 也各自固定 Mock。這是未驗收能力的暫時隔離；完成相應驗收後必須可由正式流程使用 Live，不能成為永久禁令。只改三個值不足以完成導航；解除條件、Owner 與證據依 Readiness 表逐項核對。

## 模式與共用契約

- Mock 僅供測試、離線開發及明確展示。缺 scope 的 standalone preview 可保留 Mock；正式版本優先提供各自已驗證的 Live 能力，TTS、撥號、資料查詢不必與導航共用一個全域開關。
- Live 使用真實平台／來源，具備權限、同意、provider 及必要測試；失敗、取消或未配置提供原因與下一步，不能落回 Mock、DemoGeo、虛構直線或「已送出」假成功。
- `DataMode` wire enum 仍只有 mock／live；Unavailable 使用既有 failure／reason 及程序內可用性語意，本文件不新增 Schema enum。canonical JSON Schema 是唯一 payload 來源。
- M3 僅依賴 presentation 與 shared，不 import M1 控制器、M2 provider 或 M4 repository；跨模組實作集中 M1 `platform/integration/`，以共用型別及 callbacks 注入。
- 位置許可、第三方查詢同意、SOS 附上位置與撥號是不同用途；官方受理／派遣授權及 `officialReceipt` 真實性限制繼續有效。

## 輸入與操作邊界

scope 名稱以 `shared/contracts/safe_walk_navigation_scope.dart` 為準。保留 Flow 已有的 `route`／`routeLoading`／座標 callback，由 M1 adapter 映射；其餘為待 UI 接線需求，不表示畫面已提供。

| 資料／操作 | 契約 |
|---|---|
| `mode` | 顯式 DataMode，頁面與子畫面同源，不從有沒有位置或結果推斷。 |
| `liveNavigationAvailable` | 由 readiness 證據決定，false 提供原因及下一步，不用 debug flag 繞過。scope 目前無 reason 欄，後續可協調程序內呈現，不自造 wire payload。 |
| `routeResult` → Flow `route` | canonical RouteResult；null 表示未規劃／清除／未配置，Live 不補示範路線。 |
| `routeLoading`／`routeError` | 新請求先移除舊 geometry／ETA；載入可取消，錯誤不含原始 URL、精確座標或 exception。 |
| `createRouteRequest` | 用同一份 M1 `onLocate` 成功的 Position 與使用者目的地建立 request，M1 補唯一 requestId、mode、departAt；本身不定位或外傳。 |
| `onPlanRoute` | Flow 保留 ValueChanged<Coordinates>；M1 adapter 核對意圖後建立 canonical request，交 scope 的 Future<void> Function(RouteRequest)，不另建 payload 或 GPS watcher。 |
| `hasRoutingConsent`／`onRoutingConsentChanged` | 預設 false，明確說明接收者、座標及用途；撤回先取消、清除 Live 結果及停止新外傳，再同意仍須新的規劃意圖。 |
| `onCancelRoute`／`onDestinationChanged` | 取消／更換目的地當下同步取消，不等下一次規劃或動畫；遲到結果不得覆蓋新選擇。 |
| `onNavigationOpened` | 僅使用者明確進入／重啟導航才解除 inactive，build、resumed、自動還原或定位完成不代替此操作。 |
| `onNavigationClosed`／`onEmergencyOpened` | 返回首頁、離開導航、切至通話、開啟 SOS 當下取消並鎖 inactive，不等選 110／119。 |
| `onExit`／dispose | M1 先取消路線、位置與非同步工作再退出；涵蓋系統返回與手勢，退出後同一 lifetime 永久拒絕遲到工作。 |

request factory 現有預設為 direct、繞行上限 500 m、assistancePointIds 空陣列。途經操作須明確選 viaAssistance，傳入已查證且同模式 snapshot 可核對的據點 ID；未知／未載入 ID 回錯誤，不補示範點。M1 已將同一 lookup 注入 DefaultRouteService 與 OSRM，目前 snapshot 只有 Mock。

## 正式使用流程

1. 進入安心行不自動定位／查詢。使用者開始導航或更新位置後，M1 呼叫 TownPass 原生位置服務；拒絕、服務關閉、逾時、取消或失敗提供下一步，不補示範座標。
2. 更換目的地（含自訂地點、最近據點、下一據點及「帶我去這裡」）先取消舊意圖。Live 不用 demoPlaces 的家／公司；以據點 ID 作身分，不用排序 index。
3. 外傳前另取得同意：OSRM 收到精確起訖與途經點；新增 Overpass 時另說明接收者、約略網格中心／查詢範圍。定位權限不等於外傳同意。
4. 建立 request 並核對 mode、來源、readiness、同意及 active，通過才 loading。每次等待定位保留 generation；取消、換目的地、SOS、背景或模式切換即失效。Future 完成後重查 mounted、screen、目的地、mode 及 generation，舊定位不得重新 opened 或重試。
5. 僅呈現目前 requestId／mode 結果；成功使用真實 geometry／距離／可取得的時間。失敗顯示原因、重試或使用者選擇外部導航；handoff 不代表 App 內路線成功。
6. RouteFollower 僅消費 M1 更新的位置；顯示定位被拒、偏離、抵達。remainingSeconds 是依路線時間及剩餘距離比例估計，未知保留 null，不聲稱即時交通 ETA 或逐路口指示。
7. SOS、退出、背景及撤回同意立即取消導航與後續外傳；resumed 不自動續傳。求助入口不能被路線 Future 或音訊清理阻擋，SOS 優先中斷另依 M5 契約。

## Live 呈現驗收

- 沿用 #29 已接的 OSM 底圖及 flutter_map 座標投影，驗證正式 geometry／viewport；geometry 為 GeoJSON `[longitude, latitude]`。`DemoMap` 只是沿用類名，不代表資料模式；真實底圖不會使 Mock 路線／點位成為 Live，禁止混用真實資料與 DemoGeo／虛構覆蓋物冒稱 Live。
- 使用 distanceMeters／durationSeconds；duration null 顯示未知，不用 walkMinutes 補 ETA。據點直線距離標明其語意。
- result／candidate 的 warnings、explanations、provider、來源及模式須可讀；載入、取消、無路線、網路失敗、未配置與無資料可區分。
- Live 不顯示 demoAnomalies、虛構避險件數、捷徑、地標或安全保證。walkingNetworkVerified 僅表示 provider 使用步行路網，不證明治安、照明、無障礙或目前通行。
- OSRM 目前 steps=false，共用 RouteCandidate 沒有逐路口指示；routeSteps() 的方位分段不等於正式轉向導航，需要新欄位時另提 Schema 變更。
- 首頁、據點、位置及子畫面同模式，Live 缺值不 fallback Demo。現行通話畫面已移除導航條，不再要求修復不存在的 PiP 地圖。
- 系統撥號／官方管道 handoff 只代表介面已開啟，不代表接通、送達、受理或派遣。

## 檔案範圍與證據

| Owner／範圍 | 後續交付與驗收 |
|---|---|
| M1 小魚：platform/integration、位置 adapter、shared scope | Live 能力注入及 Flow 接線；位置／外傳同意分開；操作端到端、取消／遲到／背景／SOS／撤回、無網路測試。不得只改 flags。 |
| M2 Steven：navigation | 真實 OSRM 直達／途經 provider 測試、RouteFollower、外部導航；失敗、缺同意、取消及 null duration 保持誠實，公共 endpoint 正式容量與可用性有部署決策。 |
| M3 莅紋：Flow、MapView、DemoMap、首頁／求助呈現與 presentation tests | 沿用既有設計接線；真實底圖、同意／撤回、loading／cancel／error、模式分流；320px／大字體／a11y 回歸，iPhone 地圖、定位、背景、SOS 實驗。 |
| M4 信義，M1 接入：據點 repository／lookup | 合法來源、日期、限制、營業／認可可核對；失敗／空資料／未配置分開，便利商店及 AED 不冒稱認證救援據點。 |

已有測試位於 `test/features/safe_walk/`：M2 的 `navigation/default_route_service_test.dart`、`osrm_walking_route_provider_test.dart`、`route_follower_test.dart`、`osm_convenience_store_source_test.dart`、`nearest_store_planner_test.dart`、`google_maps_link_test.dart`；M1 的 `platform/integration/safe_walk_navigation_controller_test.dart`／`safe_walk_navigation_wiring_test.dart`；M3 的流程、版面、無障礙與通話 lifecycle tests。本表盤點內容，不代表本次已執行 PASS。

`navigation/live_smoke_test.dart` 預設 skip，僅 SAFE_WALK_LIVE=1 呼叫真實服務。planner 使用 stand-in 店家，follower 用沿 geometry 合成的位置，Overpass 案例允許 transport error；即使該檔通過，也不能獨自證明真實店家、GPS、App 接線、服務可用性或 iPhone 驗收。provider 證據需記錄 SHA、日期、endpoint、結果與限制，不記錄真實使用者位置。完成相應驗收後可解除隔離，須經 PR／CI 審查。
