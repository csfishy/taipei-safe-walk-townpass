# 臺北安心行 Live 上線條件表

## 2026-11-12 Live-A 接線增量（feat/offline-live-a）

基底為 `origin/feat/offline-map` 的 `3542156195cff7d032fecf704a5b683e24fa4a79`，並非宣稱本項已合入 main。已核對 `lib/util/tp_route.dart` 的正式 `TPRoute.safeWalk`：使用 `SafeWalkCompositionRoot(liveRoutes: true, consentGranted: true)`，組合根的導航模式為 Live，據點讀取已 commit 的 `assets/safe_walk/osm_help_points_taipei.json`，路線為 Valhalla／OSRM；無需改正式入口開關。下方 2026-11-08 與歷史表的固定 Mock 描述只適用各自記錄的 SHA，不代表本分支現況。

| 能力 | Readiness | 已接線與未驗事項 |
|---|---|---|
| Live-A 本機附近求助清單（R7 增量） | WIRED_NOT_VERIFIED | 全部路線因 `provider_unavailable`、network transport 或逾時失敗時保留本機快照據點；呈現名稱、種類、營業狀態、直線距離／方位、非步行路線警語、快照日期與限制、重試及既有緊急求助。地圖只標點，不生成直線。定位與第三方同意分開；隔離同意流程中本機據點先顯示，重試路線才取得第三方同意，未同意不呼叫路線／犯罪查詢。正常路線成功仍用原候選參數與排序。尚缺真實 iPhone 飛航模式驗收。 |
| Live-A 底圖載入失敗提示（R5 增量） | WIRED_NOT_VERIFIED | SafeWalkMap 十秒內三筆不同載入失敗顯示非阻斷提示，真正成功載入圖磚後隱藏；不把安靜逾時當恢復、不改點位／geometry／避讓圖層。保留測試 provider 注入點，不新增依賴、不預抓圖磚。尚缺裝置上斷線／恢復及讀屏驗收。 |

本項僅完成 [離線需求 §A／D1](SAFE_WALK_OFFLINE.md)；未交付 §B 離線底圖資產或 §C 裝置路網。沒有新增位置寫入裝置儲存、Schema、依賴、外部通知或派遣。隔離測試不代表真實 Provider／裝置成功；本項不得標成 LIVE_VERIFIED。

### PR #101 審查修正

審查原 head `26e9c0e` 時以回歸測試重現：取消路線、變更目的地或起點未中止附近查詢，遲到據點／路線仍會回填；現已將附近工作納入同一取消邊界。另修正僅據點呈現用預設城市視野重排距離的問題，保留本機候選的實際起點排序，地圖以該次已取得的位置顯示起點。測試覆蓋查據點／規劃路線兩階段的取消、改目的地、改起點、背景後返回與 SOS；並驗證已存在的路線切成僅據點後清除路徑、舊圖磚成功事件不隱藏失敗提示、較新的成功載入才恢復。正式入口仍為 Live，D1 仍不依賴第三方同意；Readiness 維持 WIRED_NOT_VERIFIED。

### iPhone 驗收（對應離線需求 §4，尚未執行）

1. 記錄 iPhone 型號、iOS、安裝 build SHA；由 TownPass 首頁或服務正式入口開安心行。使用人工／模擬位置，證據註明限制，不使用真實住家。
2. 在線上開「最近求助地點」，確認原本排序、距離／時間、真實路線及既有避讓正常；確認快照來源。
3. 開飛航模式並保留定位，重新進入、查附近據點。等待路線服務逾時後，確認「僅據點、無路線」、名稱、種類、營業狀態、直線距離與方位、非步行路線警語、2026-11-07 快照及限制皆可閱讀。確認地圖無直線／路徑；可按重試，緊急求助可進入（不撥真電話、不送通報）。
4. 平移至未快取區域，確認三次圖磚錯誤後出現「目前無法載入地圖底圖，標示的位置仍正確」，手勢與標點仍可用。Live-A 不保證飛航模式有完整街道底圖；§4 的 z12–z18／範圍外提示待 Live-B。
5. 在獨立未授第三方同意的測試組合允許定位，確認仍顯示本機清單；重試路線才詢問同意，拒絕保留據點且不送第三方路線／犯罪查詢。正式入口既有 `consentGranted: true` 決策不變。
6. 查詢中重試／改起點、返回、背景、SOS，再讓舊工作完成，確認舊清單／路線不復活。區分服務不可用、無路線、起訖點問題與取消的訊息及下一步。
7. 關閉飛航模式，平移或縮放觸發新圖磚成功後確認提示自動消失；按重試恢復據點路線，確認正常流程。§4 的離線目的地路線／未套用避讓警語待 Live-C，不列本項通過。
8. 記錄實際結果與截圖，包含定位拒絕、資料缺失／覆蓋範圍外、VoiceOver 與放大文字。實機證據完成前維持 WIRED_NOT_VERIFIED。


## 現行基線與完成規則（2026-11-08）

本輪基線是團隊 main `7b99fea`。#49 restore 至 `3c433001` 後，#35 的 P0 正式接線已不在 main；安心行正常入口仍走 Mock。#39 合入 feature branch 而非 main，#44 仍開放，均不可預先計入主線完成。正式驗收依 [LIVE-FIRST／NO PRODUCTION MOCK](SAFE_WALK_LIVE_FIRST.md) 與 [Live MVP](SAFE_WALK_LIVE_MVP.md)，具體程式證據見 [正式接線盤點](SAFE_WALK_LIVE_WIRING_AUDIT.md)。本文件 PR 不修改執行期，也不宣稱重新測得真實 Provider 或 iPhone 成果。

正式交付必須是真 Provider／Repository／Controller 到正常 UI 的完整使用者流程，包含權限、同意、錯誤、取消及必要裝置驗收。Mock／Fake／fixtures 只限隔離 Unit／Integration tests；Production 不可選 Mock 或 fallback 假成功。未完成回 Unavailable＋真實原因＋下一步，不能只改標籤、固定成功、`readiness` 或 `live=true`。已獨立驗收能力不受其他 BLOCKED 模組全域限制。

| 現行能力／範圍 | Readiness | 此基線的缺口及下一步 |
|---|---|---|
| 正常入口的真實 GPS→同意→OSRM→正式地圖導航 | IMPLEMENTED_NOT_WIRED | 有 Provider／Controller／UI 個別實作，正式組合仍 Mock；完成正常操作、刷新／取消／背景／SOS 接線及真 Provider／iPhone 證據。不能把 #35 舊合併當目前程式。 |
| 真實底圖子能力／裝置 TTS | WIRED_NOT_VERIFIED | 圖磚 renderer 與本機 TTS 已有接線；底圖不證明路線真實，fake engine 不證明聲音。補相同 SHA 的真實裝置與失敗／中斷驗收。 |
| M4 已有犯罪統計來源至正式使用者查詢 | IMPLEMENTED_NOT_WIRED | 已有來源／解析 Repository 不等於 UI 完成；補來源日期、範圍、空／錯誤與取消流程，不冒充即時道路風險。 |
| Supabase 主庫的正式持久資料流程 | NOT_IMPLEMENTED | 既有 client 可達不等於業務持久化；#44 尚待合併，正式 API／UI 流程未完成。身分／正式唯讀權限／RPC／RLS 審查未完成部分為 BLOCKED，依 Level C 驗收，不得將管理 key 放 App。 |
| 真實 SMS／附近協助者通知 | BLOCKED | 可信身分、接收資格、ownership、RLS/RPC、限流、防濫用、保留刪除、同意及後端／裝置送達證據不足；不得以匿名 UUID 或獨立測試頁解封。 |
| 自動警消受理／派遣 | BLOCKED | 缺官方授權，officialReceipt 保持 null；不阻擋使用者主動開系統撥號器／核對後的官方入口，測試不真撥或送案。 |

狀態只用 **IMPLEMENTED_NOT_WIRED、WIRED_NOT_VERIFIED、LIVE_VERIFIED、BLOCKED、NOT_IMPLEMENTED**。本輪沒有新增任何 LIVE_VERIFIED 證據；每項後續程式 PR 必須分列相同 SHA 的 PASS、FAIL、SKIP、未執行與外部／裝置限制。競賽不採 Google Maps、不加入 AED；舊表列出的 builder／來源方案不是現行交付範圍。

CI 的人工 seed 屬隔離資料庫測試，不能接進 Production。main 仍使用 #40 的遠端 Demo 強制 gate，#47 明確啟用修正尚待合併；重設／編譯成功不等於 App 已消費 `safe_walk_demo` 或正式資料已驗收。

## 歷史：2026-11-07 原始盤點與增量

以下至文末完整保留當時 SHA、PR 狀態、測試名稱與證據；不是 `7b99fea` 的重新實測，也不授權沿用舊 Mock／Demo、Google Maps 或 AED 方案。現行規範與基線以本文前段為準，舊數字不得挪作本 PR 的 PASS。

盤點日期：2026-11-07（Asia/Taipei）。程式基線：`origin/main` 的 `03f98f2b7b5254db73774c4d097eb4d610499c2c`（已合併 #22／#27）。本文件記錄已合併程式與現存測試；本次文件 PR 不啟用 Live 常數、權限、RPC 或通知。功能驗收以 [Live MVP](SAFE_WALK_LIVE_MVP.md) 為準，工程排序見 [P0–P2 計畫](SAFE_WALK_LIVE_PLAN.md)。

審查更新（2026-11-07）：main `65ee6f7dd9c07710ecf18084b1975b6998287b3e` 已合併 PR #26 的統一 speaker lifecycle 修正與回歸測試，R9 依此增量更新，仍為 WIRED_NOT_VERIFIED，缺少實際 iPhone 驗收。其他文件明列 `03f98f2` 的盤點及 #26 待審敘述是原始快照，不應據此重做已合併工作；#28／#29 仍未合併，不預先計入完成。

協作權限依 [開放協作規範](SAFE_WALK_COLLABORATION.md)。本表的 Owner 是主要聯絡人／證據確認角色，不限制檔案作者；所有成員可在維持 Schema、依賴注入及 Guard 下跨模組修改與測試，功能主責對完整流程負責。一般接線採 Level A，Level B 變更合併前由對應主要負責人確認；正式部署開關、敏感位置／通知、Supabase 身分／RPC／RLS 及其他高風險真實外部操作仍需 Level C 隊長明確授權與安全／隱私驗收。除下述 #29 底圖增量外，程式與測試仍是原盤點 SHA 的快照，不因協作政策變更而宣稱 Live 驗證完成。#26 在本次協作盤點時已合併最新 main；本 stacked 分支已承接 #31 納入 #26 的更新，以下「盤點時未合併」保留原快照，後續工程以最新 main 核對，不視為仍待合併的阻塞。

圖磚增量（隨 PR #29 交付）：`DemoMap` 沿用類名，renderer 已改用 flutter_map／OSM 真實圖磚及座標投影；底圖子能力為 WIRED_NOT_VERIFIED，R5 整體 Live UI 為 IMPLEMENTED_NOT_WIRED。路線／點位仍為 Mock，Live gates 未開，未完成真實資料整合或 iPhone 驗收。本段及 R5 記錄該增量，不改寫 `03f98f2` 原盤點，也不預先宣稱 PR 已合併或 LIVE_VERIFIED。

## 狀態與證據規則

| 狀態 | 意義 |
|---|---|
| IMPLEMENTED_NOT_WIRED | 實作存在，但正式操作流程未能使用該能力；包含被模式/旗標或介面接線隔離的 provider |
| WIRED_NOT_VERIFIED | 已接入操作流程或明確的內部整合邊界，仍缺必要真實 Provider／裝置驗收 |
| LIVE_VERIFIED | 所列範圍的正式接線、權限、同意、取消/失敗、安全及真實 Provider／必要 iPhone 驗收均有可追溯證據 |
| BLOCKED | 缺少必要身分、安全、資料權限或官方授權，不能公開啟用 |
| NOT_IMPLEMENTED | 正式能力尚無實作，只有契約、Mock 或需求 |

Mock unit test、建構 provider、API 可達、截圖或 CI 綠燈都不足以標示 LIVE_VERIFIED。以下各列「不可啟用」指本基線不能公開啟用該完整能力，不禁止隔離且明確同意的開發驗證。本基線沒有足夠證據將任何完整 Live 產品流程標成 LIVE_VERIFIED。TTS 已實際注入，不會被此盤點改成永久 Mock。

## 能力、接線與阻塞

程式路徑前綴：`lib/features/safe_walk/`。本表 ID 與下一表逐列對應，共同構成每項功能的完整上線紀錄。

| ID／功能 | Owner | 狀態 | 已存在的程式 | 尚缺接線／未完成阻塞 | 資料來源／外部依賴 | 使用者同意與安全要求 | 是否可啟用 Live |
|---|---|---|---|---|---|---|---|
| R1 TownPass 主動 GPS | M1 小魚；M3 莅紋呈現 | IMPLEMENTED_NOT_WIRED | `platform/townpass_platform_adapter.dart` lazy 包裝既有 `GeoLocatorService.position()`；官方服務已註冊；有模式、取消、逾時、精度與時間檢查 | root `_locate()` 固定 Mock；主動開始/更新位置、拒絕/逾時 UI 與正式模式未接好 | TownPass geolocator、iOS 定位服務 | 明確操作才取位置；OS 權限與第三方同意分離；不補示範位置、不外傳日誌 | 否；完成真 GPS 流程及 iPhone 驗收後評估 |
| R2 OSRM 步行路線 | M2 Steven；M1 小魚接線；M3 莅紋呈現 | IMPLEMENTED_NOT_WIRED | `navigation/default_route_service.dart`、`osrm_walking_route_provider.dart`、HTTP transport；root 已建構 OSRM | mode/gates 關閉；Flow 未接 scope 路線/同意；真 geometry、距離/可用 ETA、目的地選擇未完整接入 | `routing.openstreetmap.de/routed-foot`；公開 fair-use demo 無可用性保證，正式容量須確認或配置合約/自管服務 | 起訖座標送第三方需獨立可撤回同意；失敗不切 Mock；walkingNetworkVerified 只指步行網路，非安全認證 | 否；真 endpoint、取消/失敗、地圖及裝置證據未齊 |
| R3 路線控制／scope 邊界 | M1 小魚 | WIRED_NOT_VERIFIED | `platform/integration/safe_walk_navigation_controller.dart`、`shared/contracts/safe_walk_navigation_scope.dart`；root 已提供 snapshot/callbacks、模式與 requestId 驗證 | Flow 尚未消費 scope；換目的地、撤同意、背景、SOS 的正式端到端閉環待完成 | M1 位置、M2 RouteService、M3 UI | 取消立即清路線，遲到結果不得復活；模式與 requestId 一致 | 否；內部接線不等於產品導航完成 |
| R4 RouteFollower／位置進度 | M2 Steven；M1 小魚接位置；M3 莅紋呈現 | IMPLEMENTED_NOT_WIRED | `navigation/route_follower.dart` 的進度/偏離運算及測試 | 主 App 尚未消費 RouteFollower；需消費 M1 位置更新、真路線並接進度/偏離/重算 UI | RouteResult geometry、M1 有效 GPS；不另開 GPS watcher | 使用者啟動/停止；背景/離開清理；精度差/過期不冒稱進度正確 | 否；實走與位置更新策略待驗 |
| R5 真實地圖與 Live UI | M1 小魚（活動後統一維護） | WIRED_NOT_VERIFIED | 正式 liveRoutes 入口已使用真實地圖；Live-B 共用 SafeWalkBasemap 接主地圖與住家選點，臺北完整 Protomaps MBTiles、2026-11-11 OSM 快照、隨附 Noto 繁中；SHA 複製／失敗回退／範圍外與來源揭露已接線 | iPhone／Android 實機飛航模式、FPS／記憶體／VoiceOver 與包大小待驗；雙平台編譯與當次測試證據見 Live-B PR，不以 Windows 渲染代替裝置驗收 | 原生預設離線；Web／離線檔失敗用 OSM 線上圖磚；ODbL、Protomaps CC0／BSD、Noto OFL；z16–z19 overzoom | 本機底圖不外傳位置；線上回退揭露檢視範圍與 IP；不改定位／路線同意，不儲存敏感位置 | 否；WIRED_NOT_VERIFIED，依 SAFE_WALK_OFFLINE §B5／§4 完成裝置證據後評估 |
| R6 已查證求助據點 | M4 信義；M1 小魚注入；M2 Steven路線；M3 莅紋呈現 | NOT_IMPLEMENTED | `safety_data/contract_safety_data.dart` parser、Mock repository；M1 snapshot lookup 與 M2 via ID 驗證 | 尚無正式 Live assistance source；Mock 查詢 Live 拋不可用；需來源正規化、查證/更新與 UI | 合法開放資料；逐來源授權、取得/更新日期、coverage、limitations | 無資料/查詢失敗/未配置分開；AED/商店不等同認證救援；未知營業不填假值 | 否；來源、查證、provider、查詢/途經驗收缺少 |
| R7 附近便利商店／外部導航 | M2 Steven；M1 小魚 handoff；M3 莅紋操作 | IMPLEMENTED_NOT_WIRED | `osm_convenience_store_source.dart`、`nearest_store_planner.dart`、`google_maps_link.dart`；有 consent/取消及路徑演算法 | Overpass/planner 未接 composition；link builder 尚無正式開啟流程、失敗狀態/同意 UI | OSM/Overpass、OSRM、Google Maps／系統 URL handler | 位置傳第三方須同意；商店只是查得場所，不假稱政府救援；失敗由使用者選外部導航 | 否；真查詢、正確場所/座標及 iPhone handoff 待驗 |
| R8 全市月別暴力犯罪資訊 | M4 信義；M1 小魚整合；M3 莅紋呈現 | IMPLEMENTED_NOT_WIRED | `safety_data/violent_crime/taipei_violent_crime_repository.dart`、CSV normalizer、GetConnect fetcher、6h cache/取消 | 未接 composition/UI；module-local `CityMonthlyCrimeStatistics` 不適用 district `AreaStatistics`，不得硬塞 | data.taipei metadata／主計處 CSV；保留來源、license、取得/更新、全市月別限制 | 不宣稱行政區、道路、逐時風險；不把歷史率變成即時安全路線 | 否；Dart 真資料抓取、呈現與裝置驗收待補 |
| R9 裝置內建陪伴 TTS | M5 奶爸；M1 小魚 speaker；M3 莅紋通話 UI | WIRED_NOT_VERIFIED | `companion/companion_tts.dart`、`platform/integration/tts_safe_walk_speaker.dart`；root 預設 device speaker，Flow/Call 已接；#26 統一 speaker lifecycle 修正與回歸已於 `65ee6f7` 合併 | 真 iPhone、缺 voice、背景/遲到 readiness、離開/SOS 競態仍待裝置驗收；保留已合併修正與回歸，不重做 #26 或以其 CI 代替實機證據 | 裝置本機 voice／flutter_tts；無可用引擎文字預覽 | 不要求麥克風；不偽裝真人/警消；只用本機 voice；停止/背景/SOS 優先中斷 | 否；不等待附近通知授權，但須本列必要裝置驗收 |
| R10 本機核准音訊資產播放 | M5 奶爸；M3 莅紋 UI | NOT_IMPLEMENTED | `CompanionAudioAdapter` 契約、`LocalCompanionController` 與 fake adapter 測試 | 具體核准資產播放器/可用音檔未提供；不得把文字預覽當播放完成 | 經授權本地資產、裝置音訊 session | 停止/離開/背景/SOS 清理；不錄音/不要求麥克風；保留資產授權 | 否；R9 TTS 可滿足 MVP，此資產能力另驗 |
| R11 110／119 撥號與官方通報入口 | M1 小魚；M3 莅紋操作 | WIRED_NOT_VERIFIED | `townpass_platform_adapter.dart` 在 Live、使用者主動點選、`allowRealCalls` 開啟時，以 `tel:110`／`tel:119` 開啟手機撥號畫面（回傳 `dial_link_activated`），失敗回 `failed`；求助頁新增「線上報案（臺北通）」，開啟 TownPass 既有的 `local://online_police`；正式入口 `tp_route.dart` 已開啟 `allowEmergencyDialer` 與該入口 | 沒有實機證據：iPhone／Android 的撥號畫面、無電話功能裝置、取消與失敗；緊急聯絡人沒有號碼（`not_configured`）；官方簡訊報案號碼尚未核對，簡訊卡片仍是未配置 | 系統撥號器、TownPass 既有線上報案服務 | 使用者主動、不等 GPS；只開啟撥號畫面，使用者自己按撥號；開啟不代表接通／受理、officialReceipt null；測試不真撥 | 否；實機驗收後再評估 LIVE_VERIFIED |
| R12 Supabase 連線基礎 | M1 小魚 | IMPLEMENTED_NOT_WIRED | `platform/supabase/safe_walk_supabase_config.dart`、`supabase_connection.dart`、`tool/check_supabase_connection.dart`；RPC transport 共用設定 | 獨立 CLI 診斷不等於 App 業務接線；業務表/權限/通知須獨立驗證 | 配置的 Supabase HTTPS Data API、公開 client key | 建構不連線；probe 不讀寫資料/不 RPC/不取位置；secret/service_role 不進 client | 否（業務）；既有唯讀工具可明確執行，不能據此開通知 |
| R13 附近協助者位置通知 | M1 小魚；M3 莅紋呈現 | BLOCKED | `nearby_emergency_service.dart`、`nearby_alert_transport.dart`、`anonymous_helper_id.dart`、`supabase/nearby_emergency.sql` 及 #27 獨立測試入口 | anon RPC 信任 caller UUID，無可信身分/ownership、接收資格、頻率防濫用、保留/刪除；未接 App，未證明後端/裝置送達 | Supabase PostgREST/PostGIS、可信身分、後端權限與接收管道 | 分享同意不能替代身分權限；須跨帳號拒絕、RLS/RPC、濫用/刪除測試；不得匿名 UUID 向陌生人公開通知 | 否；所有必要安全/後端/裝置條件完成前維持 BLOCKED |
| R14 警消案件自動派遣 | M1 小魚對接官方；其餘模組不自行發送 | BLOCKED | 共用 schema 官方回執限制；沒有授權案件 adapter | 無官方授權/正式介接/受理規格，不存在可啟用派遣 | 官方核准環境、授權、正式回執 | 不偽造受理編號，officialReceipt null；不以真緊急案件作一般測試 | 否；不得藉 R11 系統入口或 R13 附近通知宣稱派遣 |

## 逐能力測試與實機證據

本表列現存測試及還需要的證據；「存在」僅表示已核對檔案/內容，本次實跑另見 PR／CI，不重用舊 PR 的 PASS 數量。測試路徑前綴：`test/features/safe_walk/`。

| ID | 單元測試 | 整合測試 | 真實 Provider 測試 | iPhone 實機驗收 |
|---|---|---|---|---|
| R1 | `platform/townpass_platform_adapter_test.dart`，注入 reader 覆蓋權限/逾時/取消/精度/過期/Mock 隔離 | `platform/safe_walk_integration_test.dart` 現為 Mock；待真 GPS→request→UI | 未提供 TownPass 真定位成功/拒絕/逾時證據 | 未提供；需首次授權/拒絕/關閉服務、主動重試/不補假座標 |
| R2 | `navigation/osrm_walking_route_provider_test.dart`、`default_route_service_test.dart`、transport tests（fake/local HTTP） | `platform/integration/safe_walk_navigation_controller_test.dart`、`safe_walk_navigation_wiring_test.dart`；待正式 Flow | `navigation/live_smoke_test.dart` 預設 skip；需 opt-in 確實成功與失敗紀錄，腳本不等於 App | 未提供；真 GPS→同意→路線/距離/時間、斷網/取消 |
| R3 | controller tests 有 gate/模式/撤回/遲到結果 | wiring tests 驗證 scope，不驗現有 M3 地圖 | 隨 R1/R2/R5 補正式端到端 | 未提供；換目的地/離開/SOS/背景不能復活舊結果 |
| R4 | `navigation/route_follower_test.dart` 用模擬位置驗進度/偏離 | 尚無主 App follower 整合 | live smoke 可用真 geometry 但位置仍模擬，須真位置對照 | 未提供；受控實走、偏離/精度差/停止/背景 |
| R5 | 既有 flow/layout/a11y tests；#29 新增 `presentation/demo_map_test.dart`，以 fake tiles 驗 viewport、換目的地及 attribution；結果以相同 SHA 實跑為準 | 仍為 Mock flow/screenshots；待正式 RouteResult/同意/錯誤與 Live 資料整合 | renderer 已接 OSM 圖磚，不等於真實 GPS/OSRM 至正式地圖的端到端證據 | 未提供；底圖斷網、縮放/定位/路線一致、safe area、VoiceOver、無假數字 |
| R6 | `safety_data/contract_safety_data_test.dart` 為 parser/Mock；待 live source 正反案例 | snapshot/途經 ID 有 fake 測試；待真據點→M2/M3 | 未提供合法來源抓取、查詢失敗/空/缺欄證據 | 未提供；點位來源/更新/未知營業、途經真路線 |
| R7 | `navigation/osm_convenience_store_source_test.dart`、`nearest_store_planner_test.dart`、`google_maps_link_test.dart` | planner 用替身據點，未接正式 UI | opt-in Overpass smoke 可接受 transport failure；PASS 本身不足，需真查得與來源核對 | 未提供；主動開外部導航、不可開啟/取消/斷網 |
| R8 | `safety_data/violent_crime/violent_crime_normalizer_test.dart`、`taipei_violent_crime_repository_test.dart` 用 fixture/fake | 未接 UI；待全市月別語意/錯誤呈現 | 須 Dart 真 metadata/CSV 解析；Legacy Node 記錄不能代替 | 未提供；來源/日期/全市月別/未知值顯示 |
| R9 | `companion/companion_tts_test.dart`、`platform/integration/tts_safe_walk_speaker_test.dart` 用 fake/native channel | `presentation/safe_walk_call_lifecycle_test.dart`、`safe_walk_companion_sync_test.dart` 及平台整合；保留 #26 已合併的統一 lifecycle 回歸，本次文件修正不宣告重跑 | 未有裝置 voice 實際輸出/無 voice 完整證據 | 未提供；播放/停止/離開/背景/SOS/延遲準備不復活聲音、無麥克風提示 |
| R10 | `companion/companion_controller_test.dart`、state/scenarios tests 用 fake audio | 具體資產 adapter/UI 尚缺 | 無具體播放器與授權資產證據 | 未提供；播放/停止/session 中斷與釋放 |
| R11 | `townpass_platform_adapter_test.dart` 以假 launcher 驗證：Live＋點選＋開啟才呼叫 `tel:110`／`tel:119`、示範／未開啟／未點選／緊急聯絡人都不開啟、launcher 回 false 或丟例外都回 `failed` 且不顯示例外內容；結果皆通過共用 Schema 且 officialReceipt 為 null | `safe_walk_emergency_entry_test.dart`（預設不開、正式設定才開、示範忽略開關、線上報案只在注入時出現且先停語音）、`townpass_entry_test.dart`（正式入口設定與求助頁）；以相同 SHA 實跑為準 | 不真撥 110/119；仍需驗 OS 撥號畫面與官方入口 | 未提供；只開撥號器／官方管道，不按通話、不送案件，文案不稱接通 |
| R12 | `platform/supabase/safe_walk_supabase_config_test.dart`、`supabase_connection_test.dart`（local HTTP） | 共用設定/transport 基礎，無正式業務整合 | #25 記錄真專案唯讀 PostgREST probe 成功，只證明連線，非 RPC/RLS；本輪不重跑 | 未提供；CLI 診斷不能替代裝置業務流程 |
| R13 | `platform/nearby_emergency/nearby_emergency_test.dart` 用 fake，不保證後端權限 | #27 的 `nearby_live_test_page_test.dart` 用 fake 驗停用／SOS；尚無可信身分、跨帳號權限、防濫用後端測試 | 未驗必要 RPC 授權、頻率、TTL/刪除與實際接收；測試頁存在不是測試完成 | 未提供；只限安全測試身分/同意裝置，禁止陌生人或真危難 |
| R14 | schema 誠實性/officialReceipt 限制 | 無授權介接 | 無官方核准測試證據 | 無；官方授權/測試環境先行 |

`SAFE_WALK_LIVE=1` 只是允許測試連外，不能推論通過、真資料完整或裝置完成。真實 Provider 紀錄需附 commit、endpoint/資料版本、日期、成功/失敗案例、是否取裝置定位及去識別結果；不附精確個資位置或 key。iPhone 紀錄需裝置/iOS、安裝 build SHA、操作與結果；Windows 不宣稱本機 iOS build 或實機完成。

## SafeWalkCompositionRoot 的解除條件

以下設定是當前隔離，不是永久不可修改規則。本文件 PR 保留程式值；後續工程 PR 須附以下證據並依 Level A／B／C 完成審查，不能只改常數；正式部署開關採 Level C。

功能主責可直接完成下列接線及測試；表內主要負責人提供技術／證據確認，不是唯一實作者。一般 composition 接線採 Level A；如改 shared 契約採 Level B；正式啟用依 Level C。

| 現行設定／位置 | 何時可解除 | 必要測試證據 | 主要聯絡人／驗收角色 |
|---|---|---|---|
| 導航 controller `mode: sw.DataMode.mock`；`_locate()`、`_loadPoints()`、Flow、SOS 也各固定 Mock | 導航有獨立 Live session/capability 配置；R1/R2/R3/R5 模式/同意/provider/UI 一致；據點/求助可各 Unavailable，不需全產品共用 Mock 開關 | 模式隔離、無偷偷 fallback、真 GPS、route request/result、換目的地、取消/背景/SOS、Live 無 DemoGeo/假 ETA 的整合及 iPhone 證據；未開能力狀態誠實 | M1 小魚主責；M2 Steven 路線、M3 莅紋 UI 審查；M4 信義供真據點 |
| `livePresentationReady: false` | M3 真底圖/投影完成，Flow 消費 scope 或由 M1 adapter 傳入，真 RouteResult/距離/可得 ETA、同意及 loading/cancel/error/Live-Demo 區別完成 R5 | widget/投影/可及性、M1→M3 真 request/result 端到端及 iPhone 操作；Live 無虛構避險件數/地標/ETA | M3 莅紋確認 UI 證據；功能主責更新 composition，M1 小魚為平台聯絡人 |
| `liveProviderReady: false` | 已合併 consent/cancellation 修正經回歸；foot endpoint/使用條件、真 geometry/距離/時間、逾時/取消/撤同意完成 R2，由功能主責在組合層配置 provider | 真 OSRM 成功/失敗/斷網/取消、單元與整合、requestId/模式保護、iPhone 正式路線；有途經點時加來源/ID/有效性 | M2 Steven 確認 provider；功能主責配置、隊長授權正式啟用；M1 小魚為平台聯絡人；M4 信義確認據點 |
| `_loadPoints()` Mock 與拒絕 Live snapshot | R6 來源/同模式查詢完成，按能力注入 Live repository；Demo 保留獨立 Mock repository | parser/來源追溯、失敗/空/未配置、取消/模式隔離、M2 lookup 與 iPhone 顯示 | M4 信義確認資料；功能主責完成跨模組接線；M1/M2/M3 為技術聯絡人 |
| `allowRealCalls: false`／無 handoff adapter | R11 使用者主動系統交接已完成並於正式入口開啟（`allowEmergencyDialer: true`），不需等 R13/R14；實機驗收前維持 WIRED_NOT_VERIFIED | URI／launcher 單元與整合測試已有；iPhone 只開撥號／官方入口、取消與失敗仍待實機；無真緊急通話 | 功能主責可跨 platform／UI 實作；M1 小魚／M3 莅紋為技術聯絡人；真實外部操作依 Level C，不授權官方派遣 |

controller 的 mode 存活期間固定；切換須新 session 並取消/清理舊結果。不能只把 controller 換 Live，讓 `_locate()`、M4 snapshot 或 Flow 留 Demo。TTS、查詢、撥號交接按能力獨立驗收/可用性；未完成回 Unavailable，不回 Mock 假成功。

## 未合併工作與安全阻塞

`03f98f2` 原始盤點時，#26（speaker 共用 lifecycle，head `f919e6218546a2572219d81abb7fc80d5e28c37c`）、#28（知識圖譜）、#29（OSM 圖磚）均未合併；完整 SHA／CI 原始快照見 [審查報告](SAFE_WALK_SPEC_AUDIT.md)。審查更新至 `65ee6f7` 時，#26 已合併，後續保留其修正與回歸並補 R9 裝置證據；#28／#29 仍待審查，不計入主線完成或裝置驗收。

歷史：#27 新增 `platform/nearby_emergency/nearby_live_test_main.dart`／`nearby_live_test_page.dart` 與 fake Widget tests，當時以 NEARBY_LIVE_ENABLED、URL、公開 key 三項設定隔離，未接正常 TownPass。PR #41 已移除匿名配置並停用 nearby transport，只保留額外 SMS 測試旗標與分別同意的隔離入口，未新增 LIVE_VERIFIED 證據。附近通知仍 BLOCKED；目前限制與後端撤權未部署狀態見[安全狀態](SAFE_WALK_NEARBY_SECURITY.md)。

R13 必須完成可信身分/通知資格、資料所有權、RLS/RPC 授權與跨帳號拒絕、頻率/濫用保護、位置保留到期/刪除、明確同意及真後端/裝置測試，才可重新評估。匿名 UUID 不是身分或授權。R14 無官方授權時保持 BLOCKED。兩者不阻擋 R1–R11 的合法實作/分項驗收。
