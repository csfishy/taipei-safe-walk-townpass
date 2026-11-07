# P0：受控真實步行路線預覽

2026-11-07（Asia/Taipei）。本輪從 main `c4410706292ab008774e7b559c98ac59be08708e` 開發；工作分支 `feature/p0-live-walking-preview`，不是已合併 main 的成果。最終 source SHA、PR、CI artifact 待產生後填入 PR，不用本基線 SHA 代替修補後的證據。本輪不自行合併，不發布 Release／Pages；需完成必要 CI 與非作者審查後再由具權限隊員決定後續。

本輪將 TownPass 原生安心行入口接到主動單次 GPS、獨立同意與既有 M2 OSRM／M3 真實地圖，狀態為 **WIRED_NOT_VERIFIED**，不是 **LIVE_VERIFIED**。這是受控開發預覽，不是已驗收的即時導航、逐路口指示或安全路線保證。Mock 保留為顯式 `DataMode.mock`，Live 查詢失敗不切換 Mock。

## 操作流程

1. 從 TownPass 首頁卡片或城市服務進入安心行，再進入步行路線預覽。進入頁面與載入地圖都不取得 GPS，也不送出路線請求。初始臺北視野是地圖中心，不代表使用者位置。
2. 點地圖選擇目的地，或輸入 WGS84 緯度／經度後按「設定目的地」。更換目的地先取消舊定位與路線；不自動重新查詢，也不用 Demo 的家／公司座標。
3. 分別勾選兩份預設為 false 的同意：使用 TownPass 取得目前位置，以及將精確起訖座標送至揭露的第三方 OSRM 步行服務。系統定位權限不是第三方查詢同意；勾選本身不啟動定位。
4. 按「開始或重試預覽」才明確開啟本次意圖。M1 經 `PlatformService.getCurrentPosition(mode: live, userInitiated: true)` 呼叫既有 `GeoLocatorService.position()`，每次操作只取單次 GPS，不新增 watcher 或背景定位。
5. M1 拒絕 Mock／非 GPS 來源、缺精度／觀測時間、精度超過 100 公尺、超過 60 秒或超前 30 秒的位置。失敗回可理解的原因；不補示範位置。
6. 定位完成後再核對目前意圖、前景、兩份同意及 generation，才建立 canonical `RouteRequest`，交既有 `SafeWalkNavigationController` → `DefaultRouteService` → `OsrmWalkingRouteProvider`。目前只做 direct 路線，途經 IDs 為空；requestId 唯一，起點不由 UI 自造。
7. 顯示同一請求的真實 geometry、`distanceMeters`、Provider 估計時間、來源及 warnings；`durationSeconds == null` 顯示未知。Live 不加入 DemoGeo 路線、示範據點／異常、虛構避險件數、固定步速 ETA 或安全背書。

取消、返回首頁、切到通話、離開功能、背景、開啟 SOS、撤回任一同意，都先取消定位／路線並清除舊位置與結果，遲到成功或錯誤不得復活。回前景或重新勾選同意不自動恢復；需要再按開始／重試。SOS 顯示不等待路線完成；本輪也不因按 SOS 自動取得或分享位置。

目前程式保守地把 `inactive`／`hidden`／`paused`／`detached` 全部視為中止，只有 `resumed` 是前景。若原生定位授權彈窗或系統中斷造成 inactive，本次操作會失效，回前景後需重新按開始／重試；這是程式行為推論，實際 iOS 是否及何時送出該 lifecycle 仍待 iPhone 驗收，不據猜測放寬清理。

## 服務、外傳與平台

| 能力 | 本輪行為與限制 |
|---|---|
| 原生 GPS | TownPass 唯一位置入口，經明確操作與同意才取單次位置；未提供真 iPhone 授權／GPS 證據。 |
| OSRM | 預設 `https://routing.openstreetmap.de/routed-foot/route/v1/driving`；此 host 的 `routed-foot` 選擇步行路網，`driving` 路徑字串不表示本輪改用開車路網。送精確起訖座標；不送筆記、聯絡人或帳號。 |
| 公共服務節流 | 預設 OSRM transport 共用每次派送至少 1 秒的 gate，排隊前／後及派送前重查同意與取消；不儲存 URL／座標。測試注入的 transport 保留自己的政策。公共服務無 SLA，正式容量／部署方案仍待確認。 |
| OSM 底圖 | 向 `tile.openstreetmap.org` 下載目前視野圖磚，服務會看到 IP 與圖磚座標；視野可反映所選目的地或定位附近區域。底圖載入與 OSRM 查詢是不同網路行為；畫面揭露底圖來源，沿用內建 HTTP cache 與可點擊 attribution。 |
| Web | 預設路線 transport 不提供瀏覽器 Live 路由，顯示未配置；不把 Pages／Chrome 編譯成功當成原生 GPS 或真路線驗收。 |

目前沒有新增 Google Maps／Overpass 自動查詢、外部導航交接、連續追蹤或 RouteFollower 產品流程。`walkingNetworkVerified` 只描述 Provider 使用步行路網，不表示治安、照明、無障礙或現場可通行已驗證。

Live 的附近據點與回報入口清楚顯示未配置，不拿 Mock 據點補畫面。本輪沒有接入 Live AED／便利商店／犯罪統計、附近協助者通知、警消案件、SMS 或派遣；`officialReceipt` 保持 null，SOS 不宣稱已通知或受理。M5 本機 TTS 保留既有生命週期與文字預覽降級，其 iPhone 驗收另計。

## 可追溯的驗證與待驗

| 證據 | 本輪實際狀態 | 能證明的範圍 |
|---|---|---|
| Coordinator 假平台／假路線 | 專屬 45 項測試通過、兩檔嚴格分析通過；本機 log：`p0-live-coordinator-tests.log`／`p0-live-coordinator-analyze.log`（repo 外 `.init-tools/`）。 | 獨立同意、有效位置、canonical request、取消／改目的地／背景／SOS／撤回與遲到回應；不等於真 GPS。 |
| HTTPS 人工公開地標 probe | 2026-11-07 22:05:30 +08，臺北 101 → 臺北車站，預設 routed-foot endpoint 回 HTTP 200／Ok，6078.2 m、4864.8 s、284 geometry points。摘要與原始回覆在 repo 外 `p0-osrm-smoke-20261107-220531.json`。 | 只證明當時服務可達及回傳路線；不是 Dart Provider、App 入口或 iPhone 端到端證據。使用公開地標人工座標，沒有取裝置 GPS。 |
| Dart Provider smoke | 2026-11-07 約 22:15 +08，僅 OSRM 第一個具名案例，1／1 通過；經 `DefaultRouteService`／`OsrmWalkingRouteProvider` 回 6078 m／4865 s／284 points。repo 外 log：`p0-osrm-dart-smoke-20261107.log`。 | 只驗人工公開地標與真 Provider 解析；follower 284 點／arrived 是沿 geometry 合成重播，不是 GPS。不查 Overpass／planner／Google，不驗 App UI／iPhone。 |
| 預設 transport 節流 | 假時鐘／假 transport 8／8 測試及兩檔嚴格分析通過。 | 驗派送節流、取消與同意，不是公共服務容量／可靠性保證。 |
| Live UI／原生接線整合 | Live UI 21/21 通過；實際 composition → 既有 M2 Provider parser → FlutterMap 的假 GPS／HTTP 接線測試 17 通過、1 個 Web-only 案例在原生執行時跳過。包括同意、目的地／背景／SOS／遲到回應及真 geometry 呈現。 | 320／375／390／393／430、844×390 橫向、1280×800、200% 字體及鍵盤為 widget 檢查；不是實機或真 GPS。 |
| 完整測試、Schema／guard／分析 | 最後完整測試 648 通過／18 跳過（14 張 opt-in 截圖、3 個 opt-in 真服務案例、1 個 Web-only 案例）；真 OSRM 首案例已另外明確執行。Schema --check、正常 module guard、lockfile 不變通過；Safe Walk 嚴格分析無問題，全專案 --no-fatal-infos 有 17 項既有官方樣式 info、無 error／warning。CI 結果記錄於 PR。 | Fake 測試與 CI 只能證明相應 SHA 的工程檢查，不能升級為 LIVE_VERIFIED；預設 full analyze 的 info 不改寫成無問題。 |
| PR／CI／三平台預覽產物 | PR、run URL、最終 SHA、PR CI artifact 待產生；目前 pubspec 為 `0.0.12-pre.1+1`，不是本輪發布證據。本輪不發布 Release／Pages、不自行 merge。 | 各檢查與產物須對應最終 SHA，舊 main／其他 PR 綠燈不代替；非作者審查仍需完成。 |
| iPhone／實機 | 待驗：首次授權／拒絕／服務關閉、原生授權彈窗／系統中斷的 lifecycle、單次 GPS、真路線／位置一致、斷網、撤回、背景／SOS／返回、字體／VoiceOver。 | 需記錄裝置、iOS、安裝 build SHA、日期、操作與結果；若彈窗造成 inactive，確認回前景須重按開始且不自續。本輪 Windows 沒有實機證據。 |

單元／widget 測試不得取真 GPS、撥真緊急電話或向真服務送出測試危難個案。實機路線驗證使用公開地標，不在 repo、log、截圖或 PR 留下真實住家、聯絡人與行走軌跡。

CI 的 unsigned iOS IPA 沒有簽章／provisioning profile，不能直接安裝或當作 TestFlight 版本；需要 Mac／Xcode、適用的 Apple 開發身分與 provisioning，重新簽署後才能在授權裝置安裝。Windows 下載 IPA 不等於完成 iPhone 測試。建置流程見 [BUILDS](BUILDS.md)，後續逐能力驗收見 [Readiness](SAFE_WALK_LIVE_READINESS.md)。
