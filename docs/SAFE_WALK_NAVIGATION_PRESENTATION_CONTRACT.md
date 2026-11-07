# M1／M2／M3 導航接線契約

2026-11-07（Asia/Taipei）。本契約更新至從 main `c4410706292ab008774e7b559c98ac59be08708e` 開發的 P0 受控真實步行預覽；最終 SHA／PR／CI 待填入本輪 PR。狀態為 **WIRED_NOT_VERIFIED**，不是 LIVE_VERIFIED。現行目標為 [Live MVP](SAFE_WALK_LIVE_MVP.md)，操作與證據見 [P0 預覽](SAFE_WALK_P0_LIVE_PREVIEW.md)，逐能力缺口見 [Live Readiness](SAFE_WALK_LIVE_READINESS.md)。正式 UI/UX、地圖與可讀性由 M3 莅紋維護；M1 管理組合與位置入口，M2 提供路線與跟隨計算。

依 [開放協作規範](SAFE_WALK_COLLABORATION.md) 採 Feature-First、Soft Ownership、Contract-Based Integration。本文 M1／M2／M3 是技術模組及主要聯絡人，不是獨占修改權；指定功能主責可一次完成 platform、navigation、presentation 與相應測試的完整流程，不必等小魚親自接線或先批准普通修改。一般 callback／導航／UI 接線屬 Level A；共用 Contracts／Models／Schema、套件、TownPass route／原生設定、CI 及正式 UI 大型改版屬 Level B，合併前由對應主要負責人確認；正式部署開關及真實外部影響依 Level C 取得隊長明確授權與安全／隱私驗收。

## 本輪接線與缺口

| 範圍 | 本輪工作分支實況 | 尚缺交付 |
|---|---|---|
| TownPass 入口 | 城市服務／首頁已連到 `SafeWalkCompositionRoot` → `SafeWalkFlow`。 | 保留原生殼、GetX route、Theme 與品牌。 |
| M2 路線 | 沿用 `DefaultRouteService`／`OsrmWalkingRouteProvider`；預設 routed-foot OSRM 真服務，M1 transport 控制派送間隔並在派送前重查同意／取消。 | Provider／App／iPhone 證據分開驗收，公共服務容量與維運待確認。 |
| M1 控制 | `SafeWalkLiveNavigationCoordinator` 管理兩份同意、前景／active、位置與每意圖取消；取得有效單次 GPS 後交既有 `SafeWalkNavigationController`，scope 將狀態及 callbacks 交 M3。 | 真 iPhone 授權、位置、背景／返回／SOS 的端到端驗收。 |
| M3 介面 | `SafeWalkFlow` 依模式分流；Live 的 `SafeWalkLiveMapView` 消費 scope，地圖點選／輸入座標選目的地，按開始／重試才 open + plan。舊 constructor API 保留供顯式 Mock。 | iPhone 操作、VoiceOver／大字體與斷網驗收；本輪最終 widget／CI 結果見 PR。 |
| 地圖與模式 | 沿用 flutter_map／OSM renderer；Live 僅畫有效起點、所選目的地與 Provider geometry，不畫 Demo 家／公司、異常或據點；初始臺北視野不代表定位成功。 | 實機投影、視野、圖磚載入／失敗與裝置效能。 |
| 距離／時間 | Live 讀 canonical distance／nullable duration、provider、explanations 及 warnings；未知時間顯示未知，不由 Demo 步速補值。 | 與真路線／實地位置比對；不表示即時路況或路段安全。 |
| 跟隨 | `RouteFollower` 已有進度、偏離、抵達與 remainingSeconds 計算及測試。 | 尚未接 App；先支援使用者主動更新位置。若需連續定位，由功能主責在 platform 沿用 TownPass 服務定義啟停／同意，不在 navigation 另開 GPS。 |
| 便利商店／外部導航 | `OsmConvenienceStoreSource`、`NearestStorePlanner`、`googleMapsWalkingUri` 已存在。 | 尚未接組合根或正式操作；便利商店不是政府認證救援據點。 |

本輪原生組合根預設 `DataMode.live`，顯式 Mock 可獨立注入；mode 在 route lifetime 固定。Live controller 的 presentation/provider gates 描述受控預覽的程式接線，不是裝置驗收章；Web 預設 provider gate 關閉。兩份同意、位置、取消、UI 模式仍逐項核對，不能以 gates true 或 CI 綠燈宣稱 LIVE_VERIFIED。舊文件列 `03f98f2`／`65ee6f7` 的固定 Mock 內容是歷史盤點。

## 模式與共用契約

- Mock 僅供測試、離線開發及明確展示。缺 scope 的 standalone preview 可保留 Mock；正式版本優先提供各自已驗證的 Live 能力，TTS、撥號、資料查詢不必與導航共用一個全域開關。
- Live 使用真實平台／來源，具備權限、同意、provider 及必要測試；失敗、取消或未配置提供原因與下一步，不能落回 Mock、DemoGeo、虛構直線或「已送出」假成功。
- `DataMode` wire enum 仍只有 mock／live；Unavailable 使用既有 failure／reason 及程序內可用性語意，本文件不新增 Schema enum。canonical JSON Schema 是唯一 payload 來源。
- presentation 程式僅依賴自身與 shared，不直接 import platform 控制器、navigation provider 或 safety_data repository；跨模組實作組合集中 `platform/integration/`，以共用型別及 callbacks 注入。任何成員可修改上述各目錄；這是 import／組合邊界，不是作者或檔案權限。
- 位置許可、第三方查詢同意、SOS 附上位置與撥號是不同用途；官方受理／派遣授權及 `officialReceipt` 真實性限制繼續有效。

## 輸入與操作邊界

scope 名稱以 `shared/contracts/safe_walk_navigation_scope.dart` 為準。Live UI 只交目的地，起點與 canonical request 由 M1 取得／建立；舊 Flow constructor 與 request API 保留供顯式 Mock，不作 Live 捷徑。

| 資料／操作 | 契約 |
|---|---|
| `mode` | 顯式 DataMode，頁面與子畫面同源，不從有沒有位置或結果推斷。 |
| `liveNavigationAvailable` | 表示目前組合具有受控預覽的 UI／provider 接點；不是 LIVE_VERIFIED。false 顯示未配置，不取 GPS 或改用 Mock；Web 預設 false。 |
| `routeResult` | canonical RouteResult，由 controller 經 scope 交 Live UI；null 表示未規劃／清除／未配置，Live 不補示範路線。 |
| `routeLoading`／`routeError` | 新請求先移除舊 geometry／ETA；載入可取消，錯誤不含原始 URL、精確座標或 exception。 |
| `position`／`locationLoading`／`locationError` | M1 單次定位的 canonical Position 與操作狀態；不是持續定位或假起點。中斷時清除；位置來源、精度及時間須有效。 |
| `hasLocationConsent`／`onLocationConsentChanged` | 預設 false；只同意取得位置，不等於 OS 權限已授予或同意傳第三方。勾選不取 GPS，撤回即取消並清除當前導航。 |
| `onPlanDestination(Coordinates)` | Live UI 在明確開始／重試時先 `onNavigationOpened`，再只交使用者選定的目的地。M1 每次取單次 GPS，回覆後重查意圖／前景／兩份同意才建 canonical request；不另建 GPS watcher。 |
| `createRouteRequest`／`onPlanRoute` | 舊 request API 保留給顯式 Mock／既有測試；Live root 拒絕繞過 coordinator 直接傳入自造起點。 |
| `hasRoutingConsent`／`onRoutingConsentChanged` | 預設 false，明確說明接收者、座標及用途；撤回先取消、清除 Live 結果及停止新外傳，再同意仍須新的規劃意圖。 |
| `onCancelRoute`／`onDestinationChanged` | 取消／更換目的地當下同步取消，不等下一次規劃或動畫；遲到結果不得覆蓋新選擇。 |
| `onNavigationOpened` | 本輪只由明確開始／重試按鈕解除 inactive；僅進地圖、build、resumed、自動還原或定位完成不代替此操作，也不單獨取 GPS。 |
| `onNavigationClosed`／`onEmergencyOpened` | 返回首頁、離開導航、切至通話、開啟 SOS 當下取消並鎖 inactive，不等選 110／119。 |
| `onExit`／dispose | 組合層先取消路線、位置與非同步工作再退出；涵蓋系統返回與手勢，退出後同一 lifetime 永久拒絕遲到工作。 |

Live coordinator 建立 direct、繞行上限 500 m、assistancePointIds 空陣列的 request。本輪 Live 據點未接入，不發途經或 Overpass 查詢。未來途經操作須明確選 viaAssistance，傳入已查證且同模式 snapshot 可核對的據點 ID；未知／未載入 ID 回錯誤，不補示範點。

## 正式使用流程

1. 進入安心行不自動定位／查詢。使用者開始導航或更新位置後，M1 呼叫 TownPass 原生位置服務；拒絕、服務關閉、逾時、取消或失敗提供下一步，不補示範座標。
2. 本輪以地圖點選／緯經度輸入選目的地，更換先取消舊意圖，不自動重查。Live 不用 demoPlaces 的家／公司；最近／下一據點等未接入，未來接入時以據點 ID 作身分，不用排序 index。
3. 外傳前另取得同意：OSRM 收到精確起訖與途經點；新增 Overpass 時另說明接收者、約略網格中心／查詢範圍。定位權限不等於外傳同意。
4. 建立 request 並核對 mode、來源、readiness、同意及 active，通過才 loading。每次等待定位保留 generation；取消、換目的地、SOS、背景或模式切換即失效。Future 完成後重查 mounted、screen、目的地、mode 及 generation，舊定位不得重新 opened 或重試。
5. 僅呈現目前 requestId／mode 結果；成功使用真實 geometry／距離／可取得的時間。失敗顯示原因、重試或使用者選擇外部導航；handoff 不代表 App 內路線成功。
6. 本輪是單次位置的路線預覽，尚未接入 RouteFollower 的進度／偏航／抵達。後續 follower 只消費 M1 更新的位置；remainingSeconds 是依路線時間及剩餘距離比例估計，未知保留 null，不聲稱即時交通 ETA 或逐路口指示。
7. SOS、退出、背景及撤回同意立即取消導航與後續外傳；resumed 不自動續傳。求助入口不能被路線 Future 或音訊清理阻擋，SOS 優先中斷另依 M5 契約。

非 resumed 的 lifecycle（含 inactive）一律使本次意圖中止。原生定位授權彈窗若觸發 inactive，回前景後需使用者重新開始；此為程式推論，彈窗／系統中斷在 iOS 上的實際事件順序仍須實機驗收，不能記為已測。

## Live 呈現驗收

- 沿用 #29 已接的 OSM 底圖及 flutter_map 座標投影，驗證正式 geometry／viewport；geometry 為 GeoJSON `[longitude, latitude]`。`DemoMap` 只是沿用類名，不代表資料模式；真實底圖不會使 Mock 路線／點位成為 Live，禁止混用真實資料與 DemoGeo／虛構覆蓋物冒稱 Live。
- 使用 distanceMeters／durationSeconds；duration null 顯示未知，不用 walkMinutes 補 ETA。據點直線距離標明其語意。
- result／candidate 的 warnings、explanations、provider、來源及模式須可讀；載入、取消、無路線、網路失敗、未配置與無資料可區分。
- Live 不顯示 demoAnomalies、虛構避險件數、捷徑、地標或安全保證。walkingNetworkVerified 僅表示 provider 使用步行路網，不證明治安、照明、無障礙或目前通行。
- OSRM 目前 steps=false，共用 RouteCandidate 沒有逐路口指示；routeSteps() 的方位分段不等於正式轉向導航，需要新欄位時另提 Schema 變更。
- 首頁、據點、位置及子畫面同模式，Live 缺值不 fallback Demo。現行通話畫面已移除導航條，不再要求修復不存在的 PiP 地圖。
- 系統撥號／官方管道 handoff 只代表介面已開啟，不代表接通、送達、受理或派遣。

## 檔案範圍與證據

下表列主要聯絡人與技術驗收範圍；功能主責可跨列修改並交付同一條使用者流程。PR 說明跨模組目的、影響檔案及原主要負責人，開始前確認沒有其他人同時修改同一檔案。

| 主要聯絡人／技術範圍 | 後續交付與驗收 |
|---|---|
| M1 小魚：platform/integration、位置 adapter、shared scope | Live 能力注入及 Flow 接線；位置／外傳同意分開；操作端到端、取消／遲到／背景／SOS／撤回、無網路測試。不得只改 flags。 |
| M2 Steven：navigation | 真實 OSRM 直達／途經 provider 測試、RouteFollower、外部導航；失敗、缺同意、取消及 null duration 保持誠實，公共 endpoint 正式容量與可用性有部署決策。 |
| M3 莅紋：Flow、MapView、DemoMap、首頁／求助呈現與 presentation tests | 沿用既有設計接線；真實底圖、同意／撤回、loading／cancel／error、模式分流；320px／大字體／a11y 回歸，iPhone 地圖、定位、背景、SOS 實驗。 |
| M4 信義資料聯絡、M1 小魚平台聯絡：據點 repository／lookup | 合法來源、日期、限制、營業／認可可核對；失敗／空資料／未配置分開，便利商店及 AED 不冒稱認證救援據點。 |

已有測試位於 `test/features/safe_walk/`：M2 的 `navigation/default_route_service_test.dart`、`osrm_walking_route_provider_test.dart`、`route_follower_test.dart`、`osm_convenience_store_source_test.dart`、`nearest_store_planner_test.dart`、`google_maps_link_test.dart`；M1 的 `platform/integration/safe_walk_navigation_controller_test.dart`／`safe_walk_navigation_wiring_test.dart`；M3 的流程、版面、無障礙與通話 lifecycle tests。本表盤點內容，不代表本次已執行 PASS。

`navigation/live_smoke_test.dart` 預設 skip，僅 SAFE_WALK_LIVE=1 呼叫真實服務。planner 使用 stand-in 店家，follower 用沿 geometry 合成的位置，Overpass 案例允許 transport error；即使該檔通過，也不能獨自證明真實店家、GPS、App 接線、服務可用性或 iPhone 驗收。provider 證據需記錄 SHA、日期、endpoint、結果與限制，不記錄真實使用者位置。完成相應驗收後可解除隔離，須經 PR／CI 審查。
