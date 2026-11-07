# 臺北安心行：Live MVP 後續工程計畫

依 [Live MVP](SAFE_WALK_LIVE_MVP.md) 與 [Readiness](SAFE_WALK_LIVE_READINESS.md)，本次只交規格；每項後續任務開獨立 PR，不自動 merge。Owner 代表責任分配，不代表已取得新的外部帳號／派遣授權。共同前置：同步 origin/main、保留 M3 設計、單一 Schema 與模組 guard；新 wire 欄位才另開 Schema PR。

審查更新（2026-11-07）：原始計畫依 `03f98f2` 盤點；main `65ee6f7dd9c07710ecf18084b1975b6998287b3e` 已合併 #26 speaker lifecycle 修正與回歸。P1-C 接續裝置驗收與剩餘缺口，不重做已合併修正；#28／#29 仍未合併，後續先核對各自 PR，不將其提案當已完成。

圖磚增量隨 #29 交付：P0-C 沿用已接的 flutter_map／OSM renderer，`DemoMap` 僅是沿用類名，不重做底圖。接續完成 Live 資料／模式、狀態與裝置驗收；R5 整體仍 IMPLEMENTED_NOT_WIRED，底圖子能力 WIRED_NOT_VERIFIED，不先解除 Live gates 或宣稱該 PR 已合併。

## P0：正常流程的真實 GPS、OSRM 與 Live UI

| 任務／Owner | 修改檔案範圍 | 接收 → 輸出契約 | 實際完成標準 | 測試與 iPhone 驗收 | 前置依賴 |
|---|---|---|---|---|---|
| P0-A 平台能力及同意接線：M1 小魚，M3 協作 | platform/integration/safe_walk_composition_root.dart、safe_walk_navigation_controller.dart、townpass_platform_adapter.dart、shared/contracts/safe_walk_navigation_scope.dart、對應 platform 測試；M3 flow／presentation tests 的最小 API 接線 | 主動導航／刷新、定位授權、獨立第三方同意 → LocationResult、RouteRequest、能力狀態、取消 | 沿用 GeoLocatorService；未同意無外送；拒絕／逾時不補 Demo；逐能力配置，組合根傳路線狀態／callbacks 給 Flow | Adapter／Controller／入口整合，取消／撤回／改目的地／背景／SOS 遲到拒絕；iPhone 權限／GPS／刷新 | M2/M3 現有契約；先接到明確隔離驗證配置，公開啟用待 P0-B/C/D 證據 |
| P0-B OSRM、目的地與 RouteFollower：M2 Steven，M1 接線 | navigation/default_route_service.dart、osrm_walking_route_provider.dart、route_follower.dart、consent.dart、對應 navigation 測試；M1 integration | RouteRequest＋點 lookup＋刷新 Position → RouteResult、FollowUpdate／FollowStatus | 真實 geometry／距離／可空時間，選擇／更換目的地；主動更新位置反映進度／偏航／到達，錯誤不回直線或 Mock | Provider fake 邊界、follower 單元、正式流程整合；人工地標真實 OSRM；iPhone 比對實際路線與刷新 | P0-A，endpoint 步行 profile／條款／容量確認；途經真實據點另依 P1-A |
| P0-C 真實地圖與狀態：M3 莅紋，M1 協調套件 | presentation/safe_walk_flow.dart、safe_walk_map_view.dart、safe_walk_home_view.dart、demo_map.dart 的 Demo 邊界、UI 測試；必要 pubspec／平台設定由 M1 | M1 注入 RouteResult／loading／error／mode、意圖 callbacks → 地圖與操作 | 真實底圖／投影與 attribution，實際 geometry／距離／nullable duration；Live 無 DemoGeo、固定 ETA、虛構避險數／地標；同意、取消、換目的地可操作 | Widget 以任意幾何核對呈現；入口至 Provider seam；iPhone 底圖／投影／斷網、小螢幕／大字體／VoiceOver | P0-A/B；底圖來源合法性、套件相容與 M3 設計決策 |
| P0-D Live 導航驗收與逐能力啟用：M1 小魚，M2/M3 共同簽認 | platform/integration 的能力配置、integration／presentation 測試、Readiness 證據與 CI 所需範圍 | P0-A/B/C 實作與測試證據 → 正常入口可用的 Live 導航 | 逐項解除 mode／presentation／provider 閘門，已驗證功能正式流程可達，未配置能力有下一步；維持 Demo 隔離 | 正常入口 E2E＋真實 Provider＋iPhone 權限、位置、路線、取消／背景／SOS；記 SHA／裝置／skip | P0-A/B/C 全部必要證據，不以 bool 翻轉代替驗收 |

P0-A/B/C 可按約定介面平行開發，整合／驗收按表列前置依賴，P0-D 最後啟用。P0-A 以注入合成資料測 Flow，不將真 GPS／geometry 與 Mock 起點、路線／點位混用而冒充 Live；不以 `DemoMap` 類名判定能力。先沿用 #29 底圖補接線與自動驗證，逐子能力如實記錄狀態，缺少真實資料整合或裝置證據時不宣稱已上線。

## P1：據點、外部導航、語音與官方求助交接

| 任務／Owner | 修改檔案範圍 | 接收 → 輸出契約 | 實際完成標準 | 測試與 iPhone 驗收 | 前置依賴 |
|---|---|---|---|---|---|
| P1-A 真實據點：M4 信義，M1/M2 協作 | safety_data 的來源 Adapter／Repository／parser、fixtures／tests；M1 points lookup；M2 via 路線 | 合法來源＋mode＋取消 → List<AssistancePoint>／明確錯誤 | 完整 provenance／座標／日期／限制，可由 M1/M2 查詢及規劃；空資料、失敗、未配置分開；認可／營業證據不杜撰 | 真實來源 fetch／parse、Schema／語意、lookup／途經整合；iPhone 日期／限制／空錯誤／路線 | 來源／授權／品質查核，P0 資料契約；OSM/AED 不自動認證 |
| P1-B 最近據點與外部導航：M2 Steven，M1/M3 協作 | navigation/nearest_store_planner.dart、osm_convenience_store_source.dart、google_maps_link.dart；M1 handoff；M3 操作 | Position、合法據點、查詢同意／使用者選擇 → 路線／walking URI／錯誤 | 接既有 planner，不把直線最近稱步行最近；無路線可主動開外部導航，未點擊不開；未知店況揭露 | URI／planner／撤回同意／快取測試、正式按鈕整合；iPhone 外部 App 有／無／取消／斷網 | P0-A/B/C，P1-A 或明確來源／限制的 OSM 資料，外傳同意 |
| P1-C 裝置 TTS 完整驗收：M5 奶爸，M1/M3 協作 | companion/companion_tts.dart、platform/integration/tts_safe_walk_speaker.dart／speaker 介面、presentation/safe_walk_call_view.dart、相關測試 | 劇本／本機 voice／使用者操作／lifecycle → 實際播放回執或文字預覽 | 保留已接引擎及 #26 已合併 lifecycle 修正；驗晚到 ready、排隊／停止、背景／離開／SOS；不用麥克風，前景不擅自續播 | 保留 fake engine＋頁面生命週期回歸；補真實 iPhone 離線播放、無 voice、音量與中斷證據，不以 CI 代替裝置驗收 | 已合併 #22/#24/#26（#26 merge `65ee6f7`）；從最新 main 接續剩餘驗收，可與 P0 平行但排程 P1 |
| P1-D 110／119／官方通報入口：M1 小魚，M3 協作 | platform/townpass_platform_adapter.dart／handoff adapter、integration、presentation/safe_walk_emergency_view.dart／flow、tests | 主動求助＋mode／能力＋必要分享同意 → EmergencyActionResult／外部開啟結果 | 真實系統撥號及官方管道，失敗／取消可理解，officialReceipt null；不聲稱接通／受理，不連動陌生人通知 | fake launcher URI／平台失敗／SOS 語音中斷；iPhone 只開系統畫面，不撥真實緊急號碼、不送報案 | 官方 URL 來源核對與裝置可用性；不需等待附近協助者解除 BLOCKED |

## P2：統計、輔助功能與效能

| 任務／Owner | 修改檔案範圍 | 接收 → 輸出契約 | 實際完成標準 | 測試與 iPhone 驗收 | 前置依賴 |
|---|---|---|---|---|---|
| P2-A 犯罪統計資訊：M4 信義，M3 顯示／M1 注入 | safety_data/violent_crime/、M1 integration、M3 資訊區與測試 | 已實作 TaipeiViolentCrimeRepository snapshot → 明確全市期間／來源／限制資訊 | 真實來源、取得／更新時間、快取／失敗；不塞 district-only AreaStatistics，不做逐路段／逐時風險或安全路線推算 | Repository 假來源／真實來源分別驗；整合 UI／iPhone 斷網／期間／限制 | P0 整合基線；若新 wire 真的必要，先獨立 Schema PR |
| P2-B 輔助操作與效能／Production Readiness：M1 小魚協調，M2 路線、M3 體驗、M4 更新、M5 音訊各自負責 | 各自模組及 tests、CI／readiness／部署文件 | 測量結果、負載／服務條款與使用情境 → 有證據的優化／維運配置 | 取消與快取不外洩／混模式，底圖／路由容量與更新策略可維護；完成適用簽署、部署及復原 | 基準量測前後、整合回歸與 iPhone 長操作／耗用／背景；不以主觀流暢當證據 | P0/P1 主要流程穩定、真實使用測量與部署條件 |

## BLOCKED：不得以導航驗收順帶啟用

| 任務／Owner | 檔案範圍／接收輸出 | 解封必要條件與測試 | 前置依賴 |
|---|---|---|---|
| 附近協助者通知：M1 小魚（後端／安全協作） | platform/nearby_emergency/、既有 supabase/nearby_emergency.sql、必要新增 migration、supabase connection；身分／資格／位置與同意 → 授權通知結果 | 可信身分、接收資格、ownership、RLS／RPC、限流／防濫用、保留／刪除；真實後端負向權限及裝置收送／撤回測試；不得以匿名 UUID 直接開放。已合併 #27 測試頁不等於安全完成 | 後端授權設計及受控測試環境；完成前 BLOCKED |
| 官方警消案件自動派送：M1 小魚 | 未來獨立官方 adapter／契約；核准資料 → 官方真實回執 | 取得官方授權與正式接口、必要隱私／安全／端到端受控測試；目前 officialReceipt null，不擅加欄位或派遣 | 官方授權；未取得維持 BLOCKED；不阻擋主動撥號／官方入口 |

## 下一階段第一個 Codex 提示詞

> 在 taipei-safe-walk-townpass 最新 origin/main 建立 feature/m1-live-navigation-wiring 分支，先讀 AGENTS、SAFE_WALK_LIVE_MVP、LIVE_READINESS、NAVIGATION_PRESENTATION_CONTRACT 與 M1/M2/M3 README，核對所有未合併 PR／CI／工作樹。實作 P0-A：由 M1 小魚維護 platform/integration 與必要 shared 程序內 scope，與 M3 莅紋協作最小修改 presentation/safe_walk_flow.dart 與對應 presentation tests，保留既有 route／routeLoading／onPlanRoute API，新增必要的 error、同意、取消、目的地及 lifecycle 參數或消費 shared scope；不假設這些參數已存在。沿用 TownPassPlatformAdapter／GeoLocatorService，在使用者啟動導航／更新位置時讀真實 GPS；定位權限和第三方路線查詢同意分開。把既有 Controller 的 RouteResult、loading、error、取消、換目的地與同意 callbacks 正確傳到 Flow，接上 navigation opened／closed 的生命週期；不再只建立未消費 scope。未同意不送 OSRM，拒絕／逾時不補 Demo，撤回／背景／離開／SOS 與換目的地取消並忽略遲到結果。加入逐能力配置的可測接點，以注入合成資料驗 Flow／callbacks；真 GPS／路線查詢的隔離驗證不得與 Mock 起點、路線／點位混用而冒充 Live。保留明確使用者同意的隔離驗證路徑；保留公開入口的 Live gate，直到 P0-B/C/D 真實底圖、Provider 與 iPhone 證據完成，不能只改常數。沿用 #29 已接底圖 renderer，DemoMap 僅是類名；不要重做 M3 設計、啟用附近通知／官方派遣、加 GPS watcher 或改 JSON Schema。新增有意義的 Adapter／Controller／入口整合測試，驗請求與 geometry 確實到達 Flow、同意前無外送、取消不復活；跑 lock、generation、Schema --check、module guard、scoped analyze 與適當既有測試。列出真實 Provider／iPhone 未驗項目並更新 Readiness；commit、push 團隊 origin、建 PR，不 merge。
