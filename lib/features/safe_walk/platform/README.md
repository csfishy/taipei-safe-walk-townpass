# M1｜小魚：平台、唯一定位入口、求助與整合

**現行政策：LIVE-FIRST DEVELOPMENT + NO PRODUCTION MOCK。** 正式入口只接真實 Provider；Fake／Mock／fixtures 僅供隔離測試，不能由 Production 選用。新功能直接完成使用者操作、同意、真實服務、UI、錯誤／取消的完整流程；無配置回 Unavailable＋阻塞原因＋下一步，不 fallback 到 Mock。完成定義見 [LIVE-FIRST](../../../../docs/SAFE_WALK_LIVE_FIRST.md)。

所有成員均可跨 M1～M5 修改功能與相應測試，自行 AI Coding、除錯及建立 PR。修改其他模組時說明目的、影響檔案及原主要負責人，先核對進行中的 PR 避免同時改同一檔；普通 Level A 變更不需小魚事前批准，Level B 合併前確認；Level C 合併前須隊長明確授權及安全／隱私審查，正式啟用前完成適用驗收。完整規則見 [開放協作](../../../../docs/SAFE_WALK_COLLABORATION.md)。

本模組以可驗證的 Live MVP 為交付目標。先讀根目錄 AGENTS、[Live MVP 驗收](../../../../docs/SAFE_WALK_LIVE_MVP.md)、[上線條件表](../../../../docs/SAFE_WALK_LIVE_READINESS.md)、[模組契約](../../../../docs/SAFE_WALK_MODULES.md)及共用 Schema。初始化紀錄只保留當時事實，不再要求等待初始化合併或建立五個分支。

## 主要負責人與契約

- 小魚是平台／共用契約的主要聯絡人，並非獨占修改者。`platform/` 與 `test/features/safe_walk/platform/` 的一般功能／接線可由任何成員完成；共用 contracts/models/Schema、套件、TownPass route、原生設定及 CI/CD 屬 Level B，合併前由對應主要負責人確認。跨模組具體依賴仍只在 `integration/` 組合，這是程式依賴邊界，不是作者權限。
- `PlatformService.getCurrentPosition({required mode, required userInitiated, cancellation})` 回傳共用 `LocationResult`。沒有明確操作不得觸發權限，Mock 不讀裝置 GPS，Live 失敗不得以示範位置補足。
- `requestEmergency({required mode, required channel, required userInitiated, required allowRealCalls, summary})` 回傳 `EmergencyActionResult`；使用者主動開啟 110／119 撥號或官方通報入口是可開發的合法交接能力。開啟撥號器不代表已接通，`officialReceipt` 保持 null。
- 唯讀匯入 `shared/models/safe_walk_models.dart as sw`，不複製 Position 或建立第二套 payload；新增 wire 欄位需獨立 Schema 變更。

## main 的實際狀況

盤點基線為 main `7b99fea`（2026-11-08，#49 恢復 `3c433001` 快照）。以下 Mock 接線是必須修正的現況，不是允許正式交付的模式；#35 的 Live coordinator／UI 已不在此基線，不沿用其驗證冒稱 main 已接線。

| 能力 | 已存在程式 | 正式流程仍缺少 |
|---|---|---|
| TownPass 入口 | `TPRoute.safeWalk` 已建立 `SafeWalkCompositionRoot`；官方 `GeoLocatorService` 由既有 `main.dart` 註冊 | 入口的 Live 能力選擇與誠實狀態 |
| 原生位置 | `TownPassPlatformAdapter` lazy 呼叫既有 `GeoLocatorService.position()`，具操作/模式閘門、8 秒逾時、取消、權限與不可用映射 | composition 的 `_locate()` 固定 Mock；需要主動啟動導航/更新位置、定位同意 UI 及 iPhone 驗收 |
| 導航控制 | `SafeWalkNavigationController` + `SafeWalkNavigationScope` 已組合 M2 `DefaultRouteService` 與 OSRM provider，保護 requestId、模式、取消及遲到回應 | root 固定 `DataMode.mock`、`livePresentationReady: false`、`liveProviderReady: false`；M3 Flow 尚未消費 scope 的路線/同意 callbacks |
| 據點 | 目前注入 `MockSafetyDataRepository`，驗證同模式 snapshot 後供 M2 lookup | M4 真實據點 repository、來源/有效性與 Live UI；`_loadPoints()` 目前固定 Mock 並拒絕 Live 混入 |
| 音訊 | 預設 `TtsSafeWalkSpeaker.device()` 已接 M5 裝置 TTS，#26 lifecycle 修正已包含，SOS 優先 stop，離開時 dispose | iPhone 真聲音、無 voice 的 Unavailable／文字預覽、背景／回前景及非同步競態驗收；不把 #37 已被 #49 撤回的增量當成本基線成果 |
| 系統求助交接 | `requestEmergency()` 契約與 Mock SOS 流程存在 | `TownPassPlatformAdapter` 尚無 dial/share/report adapter，任何旗標仍回 `not_configured`；需實作系統撥號/官方入口交接 |
| 正式入口 Live 閉環（整合 #57／#58／#59） | `TPRoute.safeWalk` 以 `SafeWalkCompositionRoot(liveRoutes: true)` 保留 M3 地圖、Valhalla 15／50 公尺產品避讓與 OSRM 降級揭露；定位、路線外傳、Supabase 路線外框查詢及 OSM 圖磚各有操作／同意邊界。家須先儲存，未設定不查路線；地圖僅顯示真實 provider geometry、已取得的位置或使用者選點。犯罪參考來自受限唯讀 repository，本機回報由使用者標記，Live 不載入示範異常／場所。「回報狀況」接回 #58 資料庫資訊頁，每次進入只查無位置的現況與來源時效，不觸發 GPS 或路線；有證據的邊界與產品緩衝分開。未配置據點、SOS／SMS 明示不可用。離開、背景、取消／撤回會中止遲到工作 | **WIRED_NOT_VERIFIED**：隔離測試不等同真實 Supabase／路線 provider 或 iPhone 驗收。未查詢／無資料不代表安全，產品 50 公尺不冒充官方犯罪邊界。 |
| 附近協助者 | service、RPC transport、匿名 UUID store 與 SQL 已合併；Supabase 有獨立唯讀連線檢查 | **BLOCKED**：可信身分、接收資格、ownership、RLS/RPC、頻率、防濫用、保留刪除與後端/裝置驗證；未接主 App |

上述舊基線的固定 Mock 入口由 P0-3 增量修正；只有隔離測試可選用舊 Mock 路徑。不能以未驗證為由在正式入口供應假資料，也不能只改 readiness／live=true 冒稱完成。未完成能力回 Unavailable，其他已符合驗收的真能力獨立接入；附近通知 BLOCKED 不阻擋合法 GPS、OSRM、唯讀資料查詢或 TTS。

## 位置與同意

位置失敗沿用 `denied`／`timeout`／`unavailable`／`unsupported`；取消可拋 `SafeWalkCancelledException`，由平台接線忽略過期回應或以 unavailable 加清楚訊息呈現，不新增 wire status。Adapter 拒絕缺少實測精度、native mocked、精度超過 100 公尺、超過 60 秒或超前 30 秒的位置；不得補 DemoGeo。

定位權限與將起訖座標送往第三方 OSRM／Overpass 的同意必須分開。使用者撤回第三方同意、換目的地、取消、SOS、離開或背景中斷應取消目前路線並清除舊結果。navigation 只消費平台入口取得的位置，不另註冊 GPS watcher；必要時由使用者主動更新。位置及危難筆記不寫入日誌，正式流程不得默默外傳。

## 求助與附近通知的不同條件

求助不等待定位成功。求助接線先中斷陪伴及路線，再執行使用者選擇的系統交接；不以介面成功或受理編號暗示已接通、警方已接案或派遣。未獲官方授權不得自動送警消案件。

附近協助者不是官方警消通報。`supabase/nearby_emergency.sql` 的 security-definer RPC 目前接受呼叫者 UUID 並授權 anon，沒有身分與資料所有權核對；表級 RLS 本身不能補上缺口。不得僅憑匿名 UUID、公開 key、按下同意或增加 Live 旗標就公開傳送陌生人的精確位置。部署前提與既有唯讀連線證據見 [Supabase](../../../../docs/SAFE_WALK_SUPABASE.md)。

## 驗證與後續交付

既有 `townpass_platform_adapter_test.dart`、`safe_walk_integration_test.dart`、`integration/safe_walk_navigation_controller_test.dart`、`integration/safe_walk_navigation_wiring_test.dart`、TTS／Supabase／nearby 測試供回歸使用，多數採 fake 或本機伺服器。歷史測試數量不代表目前全部通過；本輪執行結果以 PR 驗證紀錄為準。測試 scope 不等於 M3 已顯示真實路線，Mock unit tests 不等於 LIVE_VERIFIED。

P0 先完成 GPS、第三方同意、M2 OSRM、M3 真實地圖與 RouteResult 接線；P1 再接合法真實據點、外部導航、裝置 TTS 驗收與官方求助交接。每次啟用依 [上線條件表](../../../../docs/SAFE_WALK_LIVE_READINESS.md)附真實 Provider 及 iPhone 證據，以 PR 與 CI 審查，不自行 merge 或改動官方 upstream。
