# 臺北安心行：TownPass Live MVP 架構

現行目標是 [Live MVP](SAFE_WALK_LIVE_MVP.md)／Production Readiness；本次僅調整文件，不改執行期旗標。程式快照為團隊 main 03f98f2b7b5254db73774c4d097eb4d610499c2c（2026-11-07，Asia/Taipei）。初始化、五模組及原生入口均已存在；現況見 [Readiness](SAFE_WALK_LIVE_READINESS.md)，證據見 [規格審查](SAFE_WALK_SPEC_AUDIT.md)。

## 官方基底與模組

官方來源 [taipei-doit/TownPass](https://github.com/taipei-doit/TownPass)，歷史 base c8e5d4d3f8f699f3d9d6cd68e129ed4da12037b3，見 SAFE_WALK_UPSTREAM.json。保留 Git 歷史、GPLv3 LICENSE、品牌、登入、Theme、TPColors 與官方服務。Flutter 3.47.6／Dart 3.13.5 沿用 .fvmrc／lock，不全量升級。React Repo 是 Legacy 參考。

lib/features/safe_walk/ 是同一 Flutter App 內的五模組及 shared。既有 Supabase 連線不代表通知安全已完成；初始化「不新增資料庫」不禁止必要的後續工程。

| 模組／Owner | 持續交付 | 邊界 |
|---|---|---|
| M1 小魚 platform | 唯一原生位置入口、能力／同意協調、官方入口／route、組合、求助 handoff | 跨模組實作組合限 integration/；不越權派遣 |
| M2 Steven navigation | OSRM、RouteService、RouteFollower、目的地／據點路線及外部導航 URI | 不另取 GPS、不接管地圖 UI、不保證安全 |
| M3 莅紋 presentation | 既有畫面、Live 底圖／投影、路線／狀態呈現、同意操作 | 正式 UI/UX 設計權；不直接取 GPS／呼叫其他模組實作 |
| M4 信義 safety_data | 合法公共資料、來源、Parser、Repository、品質 | 不把統計當即時風險或一般據點當認證救援 |
| M5 奶爸 companion | 控制器、裝置 TTS／本機音訊、清理與中斷 | 不錄音、不要求麥克風、不冒稱真人或警消 |
| shared（M1 協調） | Schema／生成 models、程序內 scope／取消契約 | 不新增第二套 payload；Unavailable 不新增 wire enum |

## 正式操作資料流

1. TownPass 首頁卡片／城市服務 → local://safe_walk → TPRoute.safeWalk → SafeWalkCompositionRoot。既有入口保留 M3 設計與返回行為。
2. 使用者啟動導航／更新位置 → M1 TownPassPlatformAdapter → 既有 GeoLocatorService.position() → LocationResult。不在載入時自取 GPS，不新增第二份監聽；必要時使用者主動刷新。
3. 使用者另同意起終點送至揭露的第三方 → M1 RouteRequest → M2 DefaultRouteService／OsrmWalkingRouteProvider → RouteResult。取消、改目的地、撤回同意、背景及離開使舊請求失效。
4. M1 將 RouteResult／loading／error／callbacks 注入 M3；M3 用真實底圖／投影呈現 geometry、距離及可取得的時間。M1 將刷新位置交 RouteFollower，再交進度給 M3，不用 DemoGeo 補失敗。
5. M4 資料經 Parser／語意驗證，由 M1 注入 M2 lookup／M3 列表；途經據點核對 ID、來源、認可／營業資訊。查詢失敗不偽裝無資料。
6. M5 裝置 TTS 已有組合接線，按使用者操作播放，無語音則文字預覽。SOS 先停止語音，再由使用者主動交接系統撥號／官方入口；與附近協助者及官方派遣分開。

目前第 2–5 步尚未完整 Live 接線：組合根固定 Mock，雖有 OSRM 實例與 scope，未將路線參數傳給 Flow；RouteFollower／真實據點未接入。隨 #29 交付的底圖增量保留 `DemoMap` 類名，renderer 已接 flutter_map／OSM 真實圖磚及座標投影，底圖子能力為 WIRED_NOT_VERIFIED；路線／點位仍 Mock，Live gates 未開，不能當作完整導航已驗收。本段增量不改寫 `03f98f2` 原快照。TTS 已有真實引擎接線，也不代表 iPhone 已通過。

## 模式、服務與驗收

Mock 僅供測試、離線開發及標示 Demo。Live 逐能力完成配置、同意、失敗處理與驗收；Unavailable 顯示未配置／服務失敗／資料不足及下一步，不回假成功。不以改 DataMode 或 readiness bool 代替工程，也不永久以全域 Mock 阻擋已驗證能力。

能力配置是 M1 程序內整合契約，不變更 wire DataMode；M3 可分別呈現 Live 導航、文字預覽、未配置據點。位置、路線、來源不可 mock/live 混用，既有 strict／nullable／語意驗證保留。

OSRM 程式預設 routing.openstreetmap.de/routed-foot 真實步行接點，並註明 fair-use、無可用性保證。MVP 記錄服務條款、負載及錯誤交接；Production Readiness 完成可維運 endpoint／容量方案。walkingNetworkVerified 僅表示步行路網，不代表治安、照明、無障礙或目前通行已查證。

## Schema、安全與部署

canonical payload 維持 schemas/safe_walk/v1/contracts.schema.json；strict unknown fields、nullable、來源／模式隔離、officialReceipt 固定 null 與語意檢查不弱化。進度／能力狀態優先使用程序內契約，必要新 wire 欄位另提 Schema PR。

附近協助者維持 BLOCKED 至可信身分、接收資格、ownership、RLS/RPC、限流、保留刪除、同意及後端／裝置測試完成；匿名 UUID 不是授權。官方案件自動派送需官方授權。兩者不阻擋導航、查詢、TTS 與使用者主動求助入口。

PR／CI 不等於實機、正式發行或競賽／授權核准；保留 [部署](BUILDS.md) 與 [競賽授權紀錄](SAFE_WALK_COMPETITION_LICENSE.md) 前提。origin 是團隊推送目標，upstream 只讀。初始化事實見 [歷史紀錄](SAFE_WALK_INITIALIZATION.md)，後續按 [工程計畫](SAFE_WALK_LIVE_PLAN.md) 逐能力完成。
