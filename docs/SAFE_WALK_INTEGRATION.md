# 臺北安心行：持續整合與 Live 交接

> 歷史適用範圍：以下至文末是 2026-11-07、`03f98f2` 的整合快照，保留原 SHA、測試與當時模式，不是目前 main 新實測或正式 Mock 授權。2026-11-08 的 main 基線 `7b99fea` 已由 #49 restore，#35 正式 P0 接線不在目前檔案；#39 僅合入 feature branch、#44 仍開放。現行規範依 [LIVE-FIRST／NO PRODUCTION MOCK](SAFE_WALK_LIVE_FIRST.md)，不要求先 Mock／Demo，Production 不得使用 fixtures 或模擬 fallback；完整真流程尚未完成即 Unavailable＋原因＋下一步。更新現況見 [Readiness](SAFE_WALK_LIVE_READINESS.md)。

快照：2026-11-07（Asia/Taipei），團隊 main 03f98f2b7b5254db73774c4d097eb4d610499c2c。現行驗收以 [Live MVP](SAFE_WALK_LIVE_MVP.md) 為準；本文件取代早期 M1 入口 PR 的「本輪只能 Mock」交付目標。初始化測試原始事實保留於 [歷史紀錄](SAFE_WALK_INITIALIZATION.md)，逐項文件變更見 [審查報告](SAFE_WALK_SPEC_AUDIT.md)。

協作方式依 [開放協作規範](SAFE_WALK_COLLABORATION.md)：M1–M5 是主要聯絡人與技術位置，所有成員可跨模組修改功能及測試，由功能主責交付完整使用流程。一般接線／callback 不需小魚事先批准或親自寫；共用契約、套件、TownPass route／原生設定、CI／正式 UI 大改依 Level B 合併前確認，真實外部影響與正式部署開關依 Level C 授權／驗收。

## 既有入口與組合

| 接點 | 現況 |
|---|---|
| TownPass 首頁／城市服務 | 首頁新聞上方功能卡與 MyServiceItemId.safeWalk，沿用同一服務目錄；城市服務預設釘選及編輯列表已整合。 |
| URI／GetX | local://safe_walk → TPRoute.safeWalk（/safe_walk）；local:///safe_walk 的 host 為空，不是相同入口。 |
| 組合根 | platform/integration/safe_walk_composition_root.dart 的 SafeWalkCompositionRoot；跨模組實作例外限此 namespace，不取消其他業務模組隔離。 |
| 位置／資料 | TownPassPlatformAdapter 與 MockSafetyDataRepository；目前入口仍固定 Mock，沒有 Live 導航開關。 |
| 導航 | 已建立 DefaultRouteService＋OsrmWalkingRouteProvider 與 Controller／Scope；Flow 路線參數／callbacks 尚未接妥。 |
| 陪伴 | TtsSafeWalkSpeaker.device() 已建立／prepare，M3 通話頁已接；本機語音未可用時文字預覽，尚缺 iPhone 證據。 |
| 生命週期 | 組合根已有 WidgetsBindingObserver、背景取消導航及 TTS foreground 控制，退出／dispose 取消工作；需完成各路徑實機驗證。 |

這是同一 TownPass Flutter App 的原生整合，不自動等於主辦核准的 WebView 微服務交付。首頁卡片參考 TownPass-self 的排列方式；正式產品 UI 仍由 M3 莅紋維護，不移入該 Repo 其他功能。

## 從目前接線到 Live

下表 Owner 是技術與驗收聯絡角色，不要求另等該成員開 PR；功能主責可在同一 PR 完成所需接線，維持非重疊檔案協調與相同契約。

| 能力 | 已有程式 | 後續交接／主要聯絡人 |
|---|---|---|
| 真實 GPS | Adapter lazy 呼叫既有 GeoLocatorService，含錯誤／精度／時間檢查 | M1 接正常導航與主動刷新；M3 提供權限與失敗狀態；不得用 Demo 座標補失敗。 |
| OSRM 路線 | Provider、RouteService、Controller、同意／取消邏輯 | M1 傳 RouteResult／loading／error／callbacks 到 Flow；M2 真實 endpoint 驗證；M3 Live 呈現。 |
| 地圖／時間 | M3 有 Flow 路線 API，仍使用 DemoMap／DemoGeo、部分固定估時 | M3 接真實底圖／投影、顯示實際距離與 nullable duration；移除 Live Demo 值。 |
| 跟隨／目的地 | RouteFollower、NearestStorePlanner 已實作，UI 有有限 Demo 目的地 | M2／M1 接主動更新位置與目的地更換；M3 顯示進度、偏航、到達／取消。 |
| 據點 | 目前 root 三個 Mock 據點，M2 有真實 OSM source；M4 有獨立犯罪資料來源 | M4 交有效據點 Repository／來源，M1 注入 lookup，M2 核對途經，不能把 AED／OSM 當認證救援。 |
| TTS | 真實本機引擎已接 | M5／M1／M3 驗晚到語音、離開、背景、SOS、無語音及 iPhone 播放；非「完全未配置」。 |
| 110／119／官方入口 | PlatformService 契約存在，Adapter 仍回 notConfigured | M1 實作主動系統交接；M3 文案不得宣稱已接通／受理。 |
| 附近協助者 | Supabase client／附近 service／SQL 與 #27 獨立 Live 測試頁已合併；測試頁不在正常 TownPass 入口 | BLOCKED；M1 先完成身分、ownership、RPC/RLS、防濫用、保留刪除與測試，不因連通或三個 dart-define 就公開啟用。 |

固定 DataMode.mock、livePresentationReady: false、liveProviderReady: false 是目前誠實隔離閘門，解除條件／Owner／證據見 [Readiness](SAFE_WALK_LIVE_READINESS.md)。不能只翻常數，也不能把常數當永久規格。附近通知／官方派遣封鎖不阻擋其他能力獨立上線。

## 共用契約與失敗

platform/integration 的程序內能力配置與依賴注入協調正式流程，任何功能主責皆可修改；shared 的 DataMode 仍為 mock/live。Unavailable 使用既有失敗／not_configured 語意，不改 Schema。資料、位置、路線來源模式必須相符；無資料、載入錯誤、未配置分開。網路失敗可重試或由使用者選外部導航，不能暗中轉 Demo。

定位授權與第三方傳送座標同意分開；撤回、改目的地、背景、離開與 SOS 取消舊請求，遲到結果不得重啟。M2 不新增 GPS 訂閱，M3 不直接 import 其他業務模組實作。

## 驗證與 iPhone 交付

本次文件 PR 的實際驗證記於 [審查報告](SAFE_WALK_SPEC_AUDIT.md)；不沿用早期 174 tests、無 background observer 或語音未配置的舊狀態當現況。後續整合要驗：

1. 正常 TownPass 首頁／城市服務進入與返回，重進／背景／離開不殘留工作。
2. 主動 GPS 權限允許／拒絕／永久拒絕、逾時與精度／時間，不外洩位置 log。
3. 查詢同意前無第三方請求；同意後實際 OSRM geometry／距離／可空時間呈現；撤回／取消／改目的地不回舊結果。
4. 真實底圖／投影、RouteFollower 主動更新、偏航／到達、斷網／錯誤／外部導航選擇。
5. 真實據點的來源／日期／限制、空資料／錯誤／未配置與認可／營業資訊。
6. iPhone TTS 離線播放、無語音文字預覽、停止、背景／系統中斷、晚到 prepare、SOS 優先停止。
7. 系統撥號畫面／官方管道 handoff 的取消與失敗；不撥真實緊急電話或發通報作測試。
8. 小螢幕、大字體、VoiceOver、減少動態效果；缺陷由 M3 維護。

PR 的 check-and-build 可產生 Android／Web／unsigned iPhone IPA artifacts；PR 不發 Release／Pages，main push 成功後依既有工作流自動 prerelease。產物須核對 run、source SHA／synthetic merge SHA、build-info，不能用舊 Release 代替。

unsigned IPA 沒有簽章／provisioning profile，不能直接安裝或當 TestFlight。授權隊員在 macOS 對相同 commit 配 Team／簽章並安裝到測試 iPhone，再記錄裝置證據；Windows 不宣稱本機 iOS build。細節見 [建置](BUILDS.md)／[預發佈](PRERELEASE-NOTES.md)。

verify_native_release.py 的 ZIP／metadata／部分 header 檢查不等於完整原生格式、可安裝或實機導航驗收；Android package／版本與 iOS device／simulator 的具體保證須對照實際驗證器，不能擴大 PASS。憑證、私鑰、profile、UDID 不入 Repo。原生／WebView 交件及授權待確認見 [競賽紀錄](SAFE_WALK_COMPETITION_LICENSE.md)。
