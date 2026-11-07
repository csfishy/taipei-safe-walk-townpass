# 臺北安心行：TownPass Live MVP 架構

協作採 [Feature-First + Soft Ownership + Contract-Based Integration](SAFE_WALK_COLLABORATION.md)：五人皆可跨模組修改功能與測試，Owner 是主要聯絡人，不是作者限制。功能主責負責端到端接線；Level A 不需小魚事前批准，Level B 合併前找對應主責確認，真實外部作用／正式開關等 Level C 需隊長授權與安全驗收。以下技術資料流中的「M1 注入」「M3 呈現」指架構角色，任何成員可完成。

現行政策為 [LIVE-FIRST／NO PRODUCTION MOCK](SAFE_WALK_LIVE_FIRST.md)，驗收以 [Live MVP](SAFE_WALK_LIVE_MVP.md) 為準。2026-11-08 的團隊 main 基線是 `7b99fea`：#49 restore 至 `3c433001`，移除先前 #35 的 P0 接線；正式入口仍 Mock，不能宣稱已 Live。原 `03f98f2b7b5254db73774c4d097eb4d610499c2c` 稽核與測試保留在[歷史規格審查](SAFE_WALK_SPEC_AUDIT.md)，不當成本次驗證。本次只修文件，不改執行期。初始化、五模組及原生入口均已存在，現況見 [Readiness](SAFE_WALK_LIVE_READINESS.md)。

## 官方基底與模組

官方來源 [taipei-doit/TownPass](https://github.com/taipei-doit/TownPass)，歷史 base c8e5d4d3f8f699f3d9d6cd68e129ed4da12037b3，見 SAFE_WALK_UPSTREAM.json。保留 Git 歷史、GPLv3 LICENSE、品牌、登入、Theme、TPColors 與官方服務。Flutter 3.47.6／Dart 3.13.5 沿用 .fvmrc／lock，不全量升級。React Repo 是 Legacy 參考。

lib/features/safe_walk/ 是同一 Flutter App 內的五模組及 shared。正式持久資料以 Supabase 主資料庫為整合方向，#44 尚待合併／安全審查；#39 僅合入 feature branch，不是 main 成果。既有 Supabase 連線不代表業務存取或通知安全已完成；初始化「不新增資料庫」不禁止必要的後續工程，管理憑證不得進 App。

| 模組／主要聯絡人 | 持續交付 | 架構與資料邊界（非作者限制） |
|---|---|---|
| M1 小魚 platform | 唯一原生位置入口、能力／同意協調、官方入口／route、組合、求助 handoff | 跨模組實作組合限 integration/；不越權派遣 |
| M2 Steven navigation | OSRM、RouteService、RouteFollower、目的地／據點路線 | navigation 不另取 GPS、不直接依賴 UI；競賽不採 Google Maps，不保證安全 |
| M3 莅紋 presentation | 既有畫面、Live 底圖／投影、路線／狀態呈現、同意操作 | 重大 UI 設計合併前確認；presentation 不直接取 GPS／呼叫其他模組實作 |
| M4 信義 safety_data | 合法公共資料、來源、Parser、Repository、品質及持久資料整合 | 不把統計當即時風險或一般據點當認證救援；競賽不加入 AED |
| M5 奶爸 companion | 控制器、裝置 TTS／本機音訊、清理與中斷 | 不錄音、不要求麥克風、不冒稱真人或警消 |
| shared（M1 協調） | Schema／生成 models、程序內 scope／取消契約 | 不新增第二套 payload；Unavailable 不新增 wire enum |

跨模組檔案修改與直接 import 分開：實作組合仍集中 platform/integration/，業務模組只依賴自身與 shared，保留 M1 Composition Root／DI，禁止隨意循環及反向依賴。現有 baseline guard 只檢查依賴路徑與歷史，沒有 GitHub 作者／目錄修改權檢查，故本次不修改或關閉它。共用 Schema／模型不複製、生成型別不手改；相關變更由任何人開發，依 Level B 確認。

## 正式操作資料流

1. TownPass 首頁卡片／城市服務 → local://safe_walk → TPRoute.safeWalk → SafeWalkCompositionRoot。既有入口保留 M3 設計與返回行為。
2. 使用者啟動導航／更新位置 → M1 TownPassPlatformAdapter → 既有 GeoLocatorService.position() → LocationResult。不在載入時自取 GPS，不新增第二份監聽；必要時使用者主動刷新。
3. 使用者另同意起終點送至揭露的第三方 → M1 RouteRequest → M2 DefaultRouteService／OsrmWalkingRouteProvider → RouteResult。取消、改目的地、撤回同意、背景及離開使舊請求失效。
4. M1 將 RouteResult／loading／error／callbacks 注入 M3；M3 用真實底圖／投影呈現 geometry、距離及可取得的時間。M1 將刷新位置交 RouteFollower，再交進度給 M3，不用 DemoGeo 補失敗。
5. M4 資料經 Parser／語意驗證，由 M1 注入 M2 lookup／M3 列表；途經據點核對 ID、來源、認可／營業資訊。查詢失敗不偽裝無資料。
6. M5 裝置 TTS 已有組合接線，按使用者操作播放，無語音則文字預覽。SOS 先停止語音，再由使用者主動交接系統撥號／官方入口；與附近協助者及官方派遣分開。

目前第 2–5 步尚未完整 Live 接線：組合根固定 Mock，雖有 OSRM 實例與 scope，未將路線參數傳給 Flow；RouteFollower／真實據點未接入。隨 #29 交付的底圖增量保留 `DemoMap` 類名，renderer 已接 flutter_map／OSM 真實圖磚及座標投影，底圖子能力為 WIRED_NOT_VERIFIED；路線／點位仍 Mock，Live gates 未開，不能當作完整導航已驗收。本段增量不改寫 `03f98f2` 原快照。TTS 已有真實引擎接線，也不代表 iPhone 已通過。

## 模式、服務與驗收

新功能直接以真 Provider 完成正常入口至結果、錯誤／取消與必要裝置驗收；不要求先 Mock／Demo／Prototype。Mock／Fake／fixtures 只供隔離 Unit／Integration tests，Production 不能選 Mock 或以模擬 fallback 補失敗。未完成為 Unavailable＋真實原因＋下一步，不回假成功。不以改 DataMode 或 readiness bool 代替工程，也不以全域 Mock 阻擋已驗證能力。

能力配置是 M1 程序內整合契約，不變更 wire DataMode；既有 mock 值保留相容但只限隔離測試。M3 可分別呈現真實導航、無 TTS 引擎的文字預覽、未配置據點及下一步。Production 不注入人工位置、路線或來源，既有 strict／nullable／語意驗證保留。

OSRM 程式預設 routing.openstreetmap.de/routed-foot 真實步行接點，並註明 fair-use、無可用性保證。MVP 記錄服務條款、負載及錯誤交接；Production Readiness 完成可維運 endpoint／容量方案。walkingNetworkVerified 僅表示步行路網，不代表治安、照明、無障礙或目前通行已查證。

## Schema、安全與部署

canonical payload 維持 schemas/safe_walk/v1/contracts.schema.json；strict unknown fields、nullable、來源／模式隔離、officialReceipt 固定 null 與語意檢查不弱化。進度／能力狀態優先使用程序內契約，必要新 wire 欄位另提 Schema PR。

附近協助者維持 BLOCKED 至可信身分、接收資格、ownership、RLS/RPC、限流、保留刪除、同意及後端／裝置測試完成；匿名 UUID 不是授權。官方案件自動派送需官方授權。兩者不阻擋導航、查詢、TTS 與使用者主動求助入口。

PR／CI 不等於實機、正式發行或競賽／授權核准；保留 [部署](BUILDS.md) 與 [競賽授權紀錄](SAFE_WALK_COMPETITION_LICENSE.md) 前提。origin 是團隊推送目標，upstream 只讀。初始化事實見 [歷史紀錄](SAFE_WALK_INITIALIZATION.md)，後續按 [工程計畫](SAFE_WALK_LIVE_PLAN.md) 逐能力完成。
