# 臺北安心行：五模組持續開發契約

目標及正式驗收以 [Live MVP](SAFE_WALK_LIVE_MVP.md) 為準，現況見 [Readiness](SAFE_WALK_LIVE_READINESS.md)。初始化已合併，M3 已有畫面，M2 已有具體 Provider，M5 已有控制器／TTS；不再以「第一輪只有抽象／README」限制開發。

所有權：M1 小魚 platform／shared／route／pubspec／CI／整合；M2 Steven navigation；M3 莅紋 presentation（正式 UI/UX 設計權）；M4 信義 safety_data；M5 奶爸 companion。業務模組只依賴自身／shared，M1 的 platform/integration/ 組合實作。

## M1｜平台與跨模組

PlatformService.getCurrentPosition 接 required DataMode、userInitiated、選用 cancellation，輸出 LocationResult（LocationSuccess／LocationFailure）。沿用 TownPass 原生位置服務，拒絕未主動操作；允許／拒絕／逾時／不可用、過期／精度與取消語意保留。Location 沒有 cancelled wire status，取消在程序邊界處理，不能新造 enum。

requestEmergency 接 mode、channel、userInitiated、allowRealCalls、選用 IncidentSummary，輸出 EmergencyActionResult。現有 Adapter 仍無真實 dialer handoff；後續實作系統撥號／官方入口，不能把旗標當能力。officialReceipt 固定 null，開啟撥號器不等於接通；分享前逐次驗證同意。附近通知另維持 BLOCKED。

M1 組合根管理能力模式／同意、取消與 requestId，注入 M2/M4/M5 及 M3 callbacks。定位權限不代表同意第三方傳送座標。各能力可獨立啟用，Unavailable 不回 Mock。

## M2｜路線、追蹤與外部導航

RouteService.planRoute(RouteRequest, cancellation) → RouteResult。沿用 requestId、mode、origin、destination、departAt、preference、maxExtraDistanceMeters、assistancePointIds；不自造第二套 JSON。RouteSuccess 帶候選 geometry／distanceMeters／nullable durationSeconds／provider／限制；RouteFailure 路線必空，保留 cancelled 等既有狀態。

DefaultRouteService／OsrmWalkingRouteProvider 已存在；pointLookup 由 M1 注入，不能直接 import M4。GeoJSON wire [lng, lat]，位置為具名 lat/lng，不能混淆。Live 用步行路網，不以直線補錯；途經 ID／模式／來源／已知關閉驗證保留。取消、撤回同意及換目的地使舊結果失效。

RouteFollower 已有程序內 FollowUpdate／FollowStatus，消費 M1 Position，後續透過 M1 注入 UI；不新增 GPS watcher。NearestStorePlanner／OsmConvenienceStoreSource／googleMapsWalkingUri 已實作但尚未接正式 App；查詢同意與外部交接由 M1 協調。OSM 商店不直接視為認證救援。詳細見 navigation/README 與 [呈現契約](SAFE_WALK_NAVIGATION_PRESENTATION_CONTRACT.md)。

## M3｜正式 UI/UX

既有 SafeWalkFlow、首頁、地圖、通話及求助頁由莅紋維護，沿用 TownPass Theme／TPColors。輸入為 M1 注入的 LocationResult、RouteResult、據點／統計、陪伴狀態、能力模式及 loading/error；輸出為定位、同意、目的地、規劃、取消、更新位置、求助與離開等使用者意圖。

現在 Flow 已有路線參數／callbacks，但組合根尚未完整傳入，DemoMap／ETA／DemoGeo 不可當成 Live 完成。M3 負責真實底圖／投影、可空時間、實際距離、取消／錯誤與能力顯示。正式功能完成後可由正常流程操作，不能永久只留展示入口。新增程序內參數由 M1/M3 協調，不任意改 Schema 或重做設計。

## M4｜來源、Parser 與 Repository

SafetyDataParser.parseAssistancePoint／parseAreaStatistics 消費正規化 Map，回 shared models，先結構後語意驗證。SafetyDataRepository.getAssistancePoints／getAreaStatistics 接 required mode 與選用 cancellation，回 List；例外沿 Future 傳遞，空 List 只代表成功查詢無資料。

Mock fixture／live 原始來源分開。sourceUrl、retrievedAt、dataUpdatedAt、license、coverage、limitations 保留；nullable 不補假值。ContractSafetyDataParser／MockSafetyDataRepository 及 violent_crime 真實來源 Repository 已存在，但一般真實據點 Repository 仍缺；M2 的 OSM source 不等於 M4 交付。全市犯罪 snapshot 不塞入 district-only AreaStatistics，不作即時道路風險。

M1 將驗證過資料注入 lookup／UI；資料失敗、無資料、未配置分開。認可／營業／現場可協助為不同證據。

## M5｜控制器、TTS 與清理

CompanionController.start(CompanionScenario, cancellation)、pause、stop(CompanionStopReason)、dispose → Stream<CompanionEvent>；state 維持 idle／playing／paused／ended／error，reason 與 state 分開。CompanionAudioAdapter 的 playAsset／pause／stop／dispose 用於核准本機資產，不任意播放 URL；audioSrc null 不冒稱已播放。

LocalCompanionController 與 CompanionTtsSpeaker 已存在。裝置 TTS 經 M1 TtsSafeWalkSpeaker 接入現有 M3 通話頁；此為程序內語音路徑，不需為無錄音劇本修改 Schema。無可用引擎則文字預覽，不要求麥克風。

停止、離開、背景、SOS 與 dispose 清除音訊、timer、遲到工作，不能前景恢復擅自續播。真實引擎／實機證據仍須補，不把 fake engine 測試當 LIVE_VERIFIED。UI 變更由 M3，speaker 組合由 M1，語音引擎由 M5 協作。

## 開發、審查與 Schema

五個模組分支已建立；新任務從最新 origin/main 建獨立分支，各自同步，不 force push。Mock 可獨立開發與回歸，正式目標是通過驗收後接入 Live。跨模組／套件／官方 route 交 M1 協調，M3 管設計。

Schema 1.0.0 維持單一來源、strict、nullable、模式隔離、官方回執 null 及語意。Unavailable 是能力語意，不加 wire enum。必要新 payload 欄位另開 Schema PR。PR 附真實 SHA／測試／skip／build／裝置證據；不自動 merge、不寫 upstream。後續任務依 [P0–P2 計畫](SAFE_WALK_LIVE_PLAN.md)。
