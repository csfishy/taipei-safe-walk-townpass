# M1／M2／M3 導航接線規格

2026-11-07，分支 `integration/m1-navigation-presentation`。本文件是交給 M3 莅紋的操作／資料接線規格；正式版面、地圖呈現與可讀性由 M3 實作及驗收。本輪不重建 TownPass 入口，也不修改 `presentation/`。

本輪從 `origin/main` 的 `bf6265f` 開始；交付前 main 已合併 PR #15 至 `7fa32880302ba8f2d1fc4fba1b3cedea46d81c3a`，本整合分支以 `44f2590` 納入該 main。M2 的 OSRM 每次外傳前重查同意／取消、平行途經請求錯誤觀察，以及 Overpass 請求清理與快取時效修正均已納入；合併後整體回歸的實際結果由本 PR 驗證紀錄記載。真實 OSRM／Overpass 與 iPhone 實機仍未驗，不能把 fake transport 測試當成實測。

提交前 fetch 另發現尚未開 PR／未合併的 `origin/feat/m3-experience` 已到 `3470e01`（相對最初 `bf6265f` 多 12 commits、差異 32 files），其中 `1f3bc1e` 已提供 `SafeWalkFlow(route: RouteResult?, routeLoading: bool, onPlanRoute: ValueChanged<Coordinates>?)` 與 `RouteState`。下文「已合併基線」的缺口不能解讀成 M3 最新分支尚未實作；最新 API 應優先保留，詳見下一節。本輪沒有拉入這 32 個版面、互動與素材檔案，也沒有宣稱未合併成果已存在本 PR。

## 與未合併 M3 API 對接

已只讀檢查 `3470e01` 的 Flow、MapView、DemoMap、CallView、HomeView 及 README。M3 新分支已完成共用 RouteResult 的基本 loading／failure／success 狀態，不需重新開發這些功能，也不要求將既有座標 callback 改成完整 request callback。

| M3 已有介面 | M1 adapter 接法 |
|---|---|
| `SafeWalkFlow.route` | 直接傳入 scope／controller 的 `routeResult`，保留 M3 命名 `route`。 |
| `SafeWalkFlow.routeLoading` | 直接傳 `routeLoading`；M1 開始新請求先清除上一筆 route，避免 loading 時保留舊線。 |
| `SafeWalkFlow.onPlanRoute: ValueChanged<sw.Coordinates>?` | 保留 M3 的 destination callback。由 M1 adapter 以 destination 與同一份 M1 定位結果呼叫 `createRouteRequest`，再轉交 scope 的 `onPlanRoute(RouteRequest)`；不建立另一套 payload，也不新增 GPS watcher。 |
| `RouteState` 的 failure 顯示 | M1 錯誤優先保留為共用 `RouteFailure` 交給 `route`，利用已存在的 reason／status／retry UI。若需呈現 request 尚未建立等錯誤，再協調新增 error 欄位；不要求重做既有錯誤元件。 |

最新 M3 已完成與仍待接線的區分：

- Flow 已把 `routeState` 傳給 MapView。常用目的地的主地圖 path 可讀 `RouteCandidate.geometry`，經緯度轉換使用具名 latitude／longitude；距離、時間與第一則 explanation 亦可讀取。不過 renderer 仍是固定 DemoGeo 投影、虛構街道與固定家標記，任意真實 OSRM 起訖的 viewport／標記仍未正確驗收，不能因此開放 Live。
- 最新 MapView 的「最近求助地點」、下一個據點及「帶我去這裡」仍只改 `_pointIndex` 並畫 `DemoGeo.lRoute`，不呼叫 Flow 的座標規劃 callback。routeResult 為 Live 時該 badge 仍可能依常用目的地的 `RouteState.live` 顯示，而目前選中的據點 path 是 demo，這一模式分流須由 M3 修正／驗證。
- Flow 的 `_placePath` 已供給 CallView 的 `routePath`、`routeMinutes`、`routeStatus` 與 destination；最新已改成上方 `_NextStep` 導航條，不能再概括為「最新通話畫面固定 DemoGeo.homeRoute」。但 standalone 預設 routePath 仍是 DemoGeo.homeRoute、缺 position 仍可能用 DemoGeo.start，且 `_NextStep` 仍以 `routeSteps()` 產生方位指示、以示範速度補未知時間，不能當正式逐路口導航。
- 最新首頁可優先讀 `RouteState.minutes`，但 null 時仍 fallback `walkMinutes(routeMeters(_placePath ?? placeRoute(...)))`，失敗／未知 ETA 會補示範分鐘；`avoidedCount(_anomalies)` 及首頁讀屏的「已繞開」仍源自 demo。`3470e01` 已移除首頁固定 Mock badge，HomeView 仍沒有 mode 參數；明確 Mock／Live 揭露與 Live 不補 demo 尚待接線，不要求恢復舊版版面。
- `RouteState.minutes` 在 durationSeconds 為 null 時仍以 `walkMinutes` 補估算；MapView 只取第一則 explanation，尚未完整呈現 result／candidate warnings 及 provider。null route 且未 loading 時視為未配置、落回示範；Flow 仍初始化 demoPlaces／demoAnomalies，null points 仍可能回 demo。上述規則須按 mode 分流，Live 不能利用 demo fallback。
- 最新 Flow 的 initState 有 post-frame `_planRoute()`，即使還在安心行首頁也可能送出目的地 callback；此 callback 不是取得 GPS 或把座標送 OSRM 的明確使用者操作，更不是第三方同意。M1 adapter 在 Live 必須維持 active／consent／readiness 閘門，M3 再把 Live 首次請求改接明確操作；不能把 post-frame callback 接成自動定位外傳。
- 同意／撤回、cancel、目的地變更立即取消、navigation opened／closed、SOS-open 通知、Live mode 與 provenance 仍待雙方接線及驗證。最新 Flow 也尚未消費本輪 scope。本輪 scope wiring tests 不能替代這一未合併版本的 UI 端到端驗收。

後續先由 M3 對其分支提交 PR，再保留上述既有 API 以 M1 adapter 接入；將剩餘 lifecycle、同意與資料分流需求交給莅紋，不把 32 個檔案直接納入本輪 M1 分支，也不另造替代畫面。

## 本輪邊界與完成定義

- M1 在 `platform/integration/` 管理單一導航控制器、M2 `DefaultRouteService` 注入、模式／同意閘門、取消及過期結果抑制，沿用共用 `RouteRequest`／`RouteResult`。
- 已合併 main 的 `SafeWalkFlow`／`SafeWalkMapView` 沒有 route callbacks 或 `RouteResult` 輸入；上節的未合併 M3 版本已有初版接口。因此「M2 可由 M1 控制器呼叫」不代表「本輪現有地圖已畫出 OSRM 路線」。原生入口維持 Mock，Live UI readiness 為 false。
- M1 透過 `shared/contracts/safe_walk_navigation_scope.dart` 的程序內 `SafeWalkNavigationScope` 提供資料及操作。M3 可使用 `SafeWalkNavigationScope.of(context)`，或由組合根把同樣欄位傳入新增的 constructor 參數；不 import platform 的控制器實作。獨立 preview／測試可用 `maybeOf(context)`，缺少 scope 時保留明確 Mock Demo；不能因此提供 Live 或把 Live 失敗回退 Mock。目前 M3 尚未消費 scope，使用者的地圖操作不會觸發 RouteService；本輪完成的是 service／binding 接點，M3 最後一段 UI 接線仍待交付。
- 現有 Mock Demo 可照原操作。新增 M2 Mock 路線是資料層驗證能力，不能把它冒稱已取代 M3 的示範路線。
- 不新增 GPS watcher。M1 既有 `PlatformService` 是唯一定位入口；M2 僅使用同一份共用 `Position`。切換模式清除舊位置、路線、目的地／據點與其錯誤，重新由明確使用者操作取得所需資料。
- 共用 canonical Schema 與生成模型不因 UI 接線而複製或改名。下列 UI loading／同意／可用性是程序內狀態，不是新的 route wire payload。
- M1 已把同一個 `pointLookup` 注入 `DefaultRouteService` 與 OSRM provider；只讀取已通過 parser 與模式檢查的 `_points` 記憶體 snapshot，依 ID 回傳，不新增 GPS、Repository 或 Overpass 查詢。原生組合根固定 Mock，因此此 snapshot 目前只有 Mock 據點。途經 Mock 僅示範共用資料交換與驗證，不能宣稱已可實際途經據點導航。
- 組合根新增 `WidgetsBindingObserver`：生命週期非 resumed 時立即取消路線並將導航鎖為 inactive，resumed 不自行恢復。導航初始亦為 inactive；只有明確使用者進入導航的 `onNavigationOpened` 才解除此閘門。`onPlanRoute` 同時檢查 route lifetime 及 active，退出後的殘留 callback 不可重新規劃。

## M3 需要接收的資料與操作

以下是本輪 M1 scope 的資料／操作邊界及待補呈現需求，不是要求將 M3 最新 `SafeWalkFlow` 全部改成同名參數。已有的 `route`／`routeLoading`／座標 `onPlanRoute` 優先保留，由上節 M1 adapter 映射；其餘同意與 lifecycle callbacks 交 M3 接入。簽名以共用型別為邊界，不讓 presentation import M2／M1／M4 實作。

| 參數／callback | 建議型別與責任 |
|---|---|
| `mode` | 既有 `sw.DataMode`，所有頁面及子母畫面必須接收；模式不由有沒有位置或結果推斷。 |
| `liveNavigationAvailable` | `bool`；目前 false。false 時不得提供可進入 Live 導航的操作，也不能用 debug flag 繞過。 |
| `liveNavigationUnavailableReason` | `String?`；說明未配置或 UI 尚未完成，不能顯示成網路查詢成功。 |
| `routeResult` | `sw.RouteResult?`；唯一成功／失敗 payload。null 表示尚未規劃或已清除，不能自動補 DemoGeo 路線。 |
| `routeLoading` | `bool`；新請求立即清除舊 geometry／ETA；載入期間提供取消，避免顯示上一個目的地的路線。 |
| `routeError` | `String?`；可讀錯誤，與 `RouteFailure.reason` 一致；不包含 URL、精確座標或原始 exception。 |
| `createRouteRequest` | 共用 scope 的 `SafeWalkRouteRequestBuilder`；以同一份 M1 `onLocate` 回傳的 `sw.Position` 及選擇的 `sw.Coordinates` 建立 canonical request，M1 補唯一 requestId、mode、departAt。它本身不定位、不外傳。 |
| scope 的 `onPlanRoute` | `Future<void> Function(sw.RouteRequest)`；交 M1 控制器，不直接呼叫 provider。此為 M1 scope 內部簽名，M3 最新 Flow 的同名 callback 保留 `ValueChanged<sw.Coordinates>`，由 adapter 建立／核對 requestId、mode、origin、departAt。 |
| `onCancelRoute` | `VoidCallback`；同步發出取消意圖，不等網路 Future 或換頁動畫結束。取消後停止 loading、清除舊線，遲到成功／錯誤不能重新顯示。 |
| `onDestinationChanged` | `VoidCallback`；變更目的地先取消，即使尚未重新定位或按下規劃。 |
| `hasRoutingConsent` | `bool`；預設 false、只存本次記憶體狀態。定位權限及 SOS 附上位置選項不能當成此同意。 |
| `onRoutingConsentChanged` | `ValueChanged<bool>`；僅明確同意操作傳 true。撤回先取消請求並清除 Live 結果；不得自動重試、沿用上次同意或改跑 Mock。 |
| `onNavigationOpened` | `VoidCallback`；只在使用者明確進入／重新開啟導航時呼叫，解除 inactive 閘門。不得在 build、定位完成、resumed 或自動還原畫面時呼叫；呼叫本身不定位、不規劃。 |
| `onEmergencyOpened` | `VoidCallback`；按下緊急求助、進入 SOS 當下就通知 M1，取消並鎖為 inactive。既有 `onEmergency(channel)` 是選 110／119 後的動作，時間太晚，不能替代此 callback。 |
| `onNavigationClosed` | `VoidCallback`；離開地圖／導航顯示、返回首頁、切至通話或頁面隱藏立即呼叫，取消路線並鎖為 inactive。回來不自行恢復或送出座標；須由使用者明確進入導航後重新規劃。 |
| `onExit` | 保留既有 callback；M1 先停止路線、位置等非同步工作，再退出。系統返回、手勢退出、route dispose 也須涵蓋。 |

`onPlanRoute` 使用 M1 `createRouteRequest(origin: ..., destination: ..., preference: ..., maxExtraDistanceMeters: ..., assistancePointIds: ...)` 建立的共用 request。origin 沿用既有 M1 `onLocate` 的成功結果，不在 UI 另開定位；Live destination 必須由使用者明確選取或來自已核對的同模式據點，不可從 `SavedPlace` 的示範家座標補出 Live request。具體 constructor 參數名稱可以與莅紋協調，資料所有權與取消時機不可省略。`liveNavigationUnavailableReason` 是 M3 額外建議呈現的欄位，目前 scope 沒有此欄；可依 `liveNavigationAvailable == false` 顯示未開放說明，或由 M1 後續補入。

request factory 預設 `preference: sw.RouteKind.direct`、`maxExtraDistanceMeters: 500`、`assistancePointIds: []`。途經操作必須明確傳入 `viaAssistance` 與目前 snapshot 可核對的 ID；未知／未載入 ID 回錯誤，不能補示範據點。即使 Mock 途經 request 通過，仍只是資料層示範，不是真實途經步行導航。

M3 不需要接收 cancellation token、transport、provider、GPS subscription 或另一套 route model。M1 控制器的 notifier 可由組合根轉成上述 immutable inputs；presentation 維持只依賴自身及 shared。

目前 M1 的控制器為 `SafeWalkNavigationController`，提供 `planRoute(RouteRequest)`、`setRoutingConsent(bool)`、`cancelRoute()` 及 `dispose()`，以及表中的模式、同意、可用性、結果／loading／error getters。scope 的 `onDestinationChanged` 已映射取消；`onNavigationClosed`、`onEmergencyOpened` 已映射取消及 inactive 閘門，`onNavigationOpened` 映射明確重新進入。組合根固定 Mock，`livePresentationReady`／`liveProviderReady` 仍為 false：M3 正式接線與實際 Live／native provider 驗證尚未完成，PR #15 已合併不等於可直接開啟 Live。App 也沒有接入 Overpass 查詢；本文件的 Overpass 操作要求是後續接入條件，不能列為本輪 App 已提供的功能。

上述 callbacks 目前只有 M1 scope 映射，現有 M3 UI 尚未呼叫 `onDestinationChanged`、`onNavigationOpened`、`onNavigationClosed` 或 `onEmergencyOpened`。現有 `_emergency(channel)` 在使用者選 110／119 後才取消並鎖住導航，只是後備處理；不能宣稱按下 SOS 開頁或切換目的地的使用者操作已完成即時取消。透過 scope callbacks 的 wiring tests 只驗證 M1 邊界及資料流程，不等於 M3 使用者操作端到端接線或真實路線呈現已驗。

## 操作順序與狀態

| 使用者操作／結果 | M1／M3 約定 |
|---|---|
| 進入安心行 | Mock；不自動定位、不自動規劃、不送 OSRM／Overpass。保留既有 Demo 操作。 |
| 明確進入導航 | M3 呼叫 `onNavigationOpened`，才能接受後續 `onPlanRoute`；不以進入安心行首頁或 rebuild 取代此操作。 |
| 開始規劃 | 先取消舊請求、移除舊線與錯誤；核對 mode、origin source、destination 來源及 readiness／consent；通過後才 loading。 |
| 更換家／公司／自訂地點、最近據點、下一個據點、「帶我去這裡」、刪除目前目的地 | 立即取消前一請求；更新選擇後依同一模式重建 request。不是只在下一次 `planRoute` 時取消。目的地用據點 ID，不用排序中的 index 作為永久身分。 |
| 成功 | 只顯示目前 requestId／mode 的 `RouteSuccess`；從候選路線取得 geometry、距離、時間及說明，保留所有 warnings。 |
| 失敗 | 顯示 `no_route`／`provider_unavailable`／`invalid_input` 的清楚原因與可用重試；routes 為空。OSRM／Overpass 失敗不得換成 Mock 或 L 形路線。 |
| 取消／舊請求遲到 | 結束 loading；不保留可誤認為有效的 geometry／ETA，不把取消顯示成路線成功。過期結果不覆寫新選擇或 SOS。 |
| 開啟 SOS | 先同步 `onEmergencyOpened`／取消，不等使用者選電話、不等 GPS／路線完成、不等音訊清理完成；求助入口持續可用。 |
| 返回、切離導航、背景、退出／dispose | 立即取消並鎖為 inactive；非 resumed 的背景轉換由組合根 observer 執行，畫面內切換由 M3 callbacks 執行。resumed 不自動解鎖或續傳；退出後 lifetime 永久拒絕同一 route 的規劃。 |
| 同意撤回 | 取消現有請求、停止後續外傳、清除 Live route，顯示未同意；再次同意仍需新的使用者規劃操作。 |

同意提示須說明「將精確起點、目的地及選擇的途經座標送往第三方 OSRM 步行路線服務」，提供拒絕與撤回。若新增 Overpass 附近便利商店操作，另說明接收者與網格中心／查詢範圍；未同意不得發送任何查詢。空清單與查詢失敗分開呈現，不能將 OSM 標註缺漏解讀成附近沒有求助管道。

M3 若以「等待 `onLocate` → 建立 request → `onPlanRoute`」串接，須為每次規劃意圖保留 generation。更換目的地、取消、離開、SOS、背景或模式切換立即讓舊 generation 失效；定位 Future 完成後，核對 mounted、目前 screen／目的地／mode 與 generation 均仍相符，才提交 request。不可在舊定位完成時重新呼叫 `onNavigationOpened` 或自動重試；controller 的取消不能代替 UI 對舊規劃意圖的核對。

## 顯示資料規則

1. `RouteCandidate.geometry.coordinates` 是 GeoJSON `[longitude, latitude]`；轉畫圖座標時使用具名 `longitude`／`latitude`。不得當成 `[lat, lng]`，也不能把真實路線放在固定虛構街道上。
2. 使用 candidate 的 `distanceMeters`／`durationSeconds`；時間 null 顯示未知，不用 `walkMinutes()` 的示範速度補 ETA。據點排序的直線距離不得標成真實步行距離。
3. `RouteResult.warnings` 及每條 candidate 的 `warnings`／`explanations` 必須可讀；顯示 provider 與模式，不只換顏色。
4. `walkingNetworkVerified` 僅表示 M2 使用步行路網，不能顯示成已驗證治安、照明、無障礙、安全或即時可通行。OSRM 沒有異常避讓能力；Live 不顯示 demo 的「已繞開 N 個異常回報」或虛構捷徑對照。
5. M2 OSRM 目前請求 `steps=false`，共用 RouteCandidate 也沒有逐路口指示。可先呈現路線預覽與距離／時間；不能把 `routeSteps()` 的方位分段當成正式轉向導航。若需要正式逐步導航，M1／M2 另協調 Schema 與 provider，再交 M3 呈現。
6. Live 的位置、目的地、據點、異常回報、首頁摘要與通話子母地圖必須同一模式；缺少正式資料就清楚留空／未配置。不能在 `points == null`、`position == null` 或 route 失敗時落回 DemoGeo／demoPlaces／demoPoints／demoAnomalies。
7. 設備定位許可、OSRM 同意、SOS 分享位置及真實撥號開關是不同用途，不能互相代用。導入路線不得變更既有 Mock SOS 的不撥號、不傳送、`officialReceipt: null` 邊界。

## 交由 M3 的具體檔案修改

| 檔案 | 需要 M3 修改的接點；不要求重排版面 |
|---|---|
| `presentation/safe_walk_flow.dart` | 保留未合併分支已有 `route`／`routeLoading`／座標 callback，透過 M1 adapter 接線；補同意／lifecycle 操作，Live 不以 post-frame 自動規劃；使用者明確進入導航才呼叫 opened，目的地變更、`_go`、`_openEmergency`、返回及 dispose 立即通知取消／closed；等待定位後核對意圖 generation；用 maybeOf 保留獨立 Mock preview；Live 不初始化 demoPlaces／demoAnomalies、不讓 null points 或首頁未知 ETA 補 Demo。 |
| `presentation/safe_walk_map_view.dart` | 保留未合併分支已有 `RouteState` loading／failure／success 顯示與常用目的地 geometry 輸入；補取消、完整 warnings／provider／未知 ETA、模式與同意操作，將換據點／帶我去等仍為 demo 的目的地事件交 M1；Live 不顯示虛構避讓數、L 形路線、demo steps。 |
| `presentation/demo_map.dart` | 保留 Mock 用途。其投影範圍、街道、家標記與捷徑固定於 DemoGeo，尚不能正確呈現任意真實路線；由 M3 決定 Live 地圖 renderer／viewport，並驗證起訖點與縮放。不要由 M1 另造一張正式地圖。 |
| `presentation/safe_walk_home_view.dart` | 接收 mode、readiness、nullable 距離／時間或對應摘要狀態；main 固定 Mock badge、未合併3470e01已移除該badge，兩者均須清楚模式揭露，不要求重排。最新已有 RouteState.minutes 的優先資料，但未知／失敗時的示範分鐘與 demo 避讓數不能進 Live。 |
| `presentation/safe_walk_call_view.dart` | main 的 `_Pip` 固定 DemoGeo 路線；未合併新版已由 Flow 傳 routePath／minutes／status 至 `_NextStep`，保留此接點。補 mode 與 provenance，禁止未知時間補示範速度、示意 routeSteps 當正式轉向；未完成 Live 地圖的導航條可暫不顯示。保持模擬通話揭露與已完成的來電 session／離開清理。 |
| `presentation/mock/safe_walk_demo_data.dart` | 保留原 Demo，只能被明確 Mock 分支使用；既有 LatLng 是畫圖用值，不能作為新的跨模組 Route／Position payload。 |
| `presentation/safe_walk_emergency_view.dart` | 路線導入不影響原 SOS 模式限制；明確保留定位及分享的獨立同意，確認附近據點來自目前模式；沒有路線也能操作求助。 |
| `presentation/README.md` 與 presentation tests | M3 更新正式介面、狀態與實際驗收結果；新增取消時序、錯誤／撤回、模式分流、主地圖／子母地圖同源及無 demo fallback 測試。 |

以上列出已合併 main 與未合併新版的差異，以及仍需 M3／M1 adapter 完成的接點；不要求重做 M3 新版已實作的 route 狀態、geometry 輸入、來電互動或素材。本輪 M1 不修改這些檔案，也沒有把未合併版本當成本輪已接入。TownPass 首頁卡片、城市服務目錄與 GetX route 已存在，不列為重建項目。

## Live 入口開放前驗收

- M3 能以 M1 提供的 RouteSuccess 畫出任意真實起訖座標範圍的 geometry，距離／nullable 時間正確；首頁與子母畫面不殘留 DemoGeo。
- 使用者同意前零第三方請求；拒絕、撤回、途經查詢中撤回、目的地變更、開啟 SOS、系統返回與背景都能停止後續請求／遲到更新。另驗證舊定位 Future 不得在取消後重新提交 request，resumed 不自動解鎖，必須由明確使用者再次進入。M2 PR #15 的同意重查、平行錯誤處理、Overpass 取消及快取 TTL 修正已合併納入本分支；合併後整體測試結果見本 PR，仍須完成真正 Live／native 操作驗收。
- 真實 GPS 的來源／時間／精度經 M1 驗證，不用示範座標補缺值；Live 途經據點來源與營業資料由 M1／M4 核對，尚未整合者維持未配置。
- OSRM 無路線／逾時／離線與 Overpass 失敗各自可見；不回退 Demo。不宣稱路線通過治安、照明或無障礙安全驗證。
- 跑共用 Schema check、scoped／完整 analyze、M1／M2 unit、TownPass 入口／SOS 整合與 M3 狀態測試；用真實服務的 smoke／iPhone 實機結果另列，不以 fake transport 的成功替代。

Live 開放是上述共同驗收後的 M1 接線工作。只完成 UI callback 或只把 `mode` 改成 live 都不足以開放入口。

## 下一次 iPhone IPA 前的交付區分

可以為本輪 Mock 整合建立新的 PR CI unsigned IPA，前提是本 PR 的檢查與 iOS job 實際成功；包內仍應維持 Mock，不能標示已完成 Live 導航。Windows 本機無 Xcode，不宣稱本機已編譯或裝機。

若下一版 IPA 要宣告 Live 路線預覽，還缺 M3 上述介面及真實地圖呈現、M1 正式接入 callbacks、明確第三方同意、provider／真實資料來源與實機網路／取消回歸。PR #15 修正已納入，不再是待合併阻塞；真實 OSRM／Overpass 與 iPhone 未驗仍需如實記錄。正式逐步步行導航還缺 M2／Schema 的指示契約及實作。

iPhone 安裝仍須團隊現有 macOS 簽署／provisioning 流程與測試裝置；unsigned IPA 不能直接安裝，也不等於 TestFlight。從相同 commit 實機確認 TownPass 入口／返回、拒絕定位、背景取消、SOS 可操作、VoiceOver／大字體與不混用示範資料，結果逐項記錄。既有簽署與 CI 說明見 [TownPass 整合紀錄](SAFE_WALK_INTEGRATION.md)。
