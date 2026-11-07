# M1｜小魚：平台、唯一定位入口、求助與整合

所有成員均可跨 M1～M5 修改功能與相應測試，自行 AI Coding、除錯及建立 PR。修改其他模組時說明目的、影響檔案及原主要負責人，先核對進行中的 PR 避免同時改同一檔；普通 Level A 變更不需小魚事前批准，Level B 合併前確認；Level C 合併前須隊長明確授權及安全／隱私審查，正式啟用前完成適用驗收。完整規則見 [開放協作](../../../../docs/SAFE_WALK_COLLABORATION.md)。

本模組以可驗證的 Live MVP 為交付目標。先讀根目錄 AGENTS、[Live MVP 驗收](../../../../docs/SAFE_WALK_LIVE_MVP.md)、[上線條件表](../../../../docs/SAFE_WALK_LIVE_READINESS.md)、[模組契約](../../../../docs/SAFE_WALK_MODULES.md)及共用 Schema。初始化紀錄只保留當時事實，不再要求等待初始化合併或建立五個分支。

## 主要負責人與契約

- 小魚是平台／共用契約的主要聯絡人，並非獨占修改者。`platform/` 與 `test/features/safe_walk/platform/` 的一般功能／接線可由任何成員完成；共用 contracts/models/Schema、套件、TownPass route、原生設定及 CI/CD 屬 Level B，合併前由對應主要負責人確認。跨模組具體依賴仍只在 `integration/` 組合，這是程式依賴邊界，不是作者權限。
- `PlatformService.getCurrentPosition({required mode, required userInitiated, cancellation})` 回傳共用 `LocationResult`。沒有明確操作不得觸發權限，Mock 不讀裝置 GPS，Live 失敗不得以示範位置補足。
- `requestEmergency({required mode, required channel, required userInitiated, required allowRealCalls, summary})` 回傳 `EmergencyActionResult`；使用者主動開啟 110／119 撥號或官方通報入口是可開發的合法交接能力。開啟撥號器不代表已接通，`officialReceipt` 保持 null。
- 唯讀匯入 `shared/models/safe_walk_models.dart as sw`，不複製 Position 或建立第二套 payload；新增 wire 欄位需獨立 Schema 變更。

## P0 工作分支的實際狀況

本輪從 main `c4410706292ab008774e7b559c98ac59be08708e`（2026-11-07）接續開發受控步行預覽；最終 SHA／PR／CI 待填。以下接線為 WIRED_NOT_VERIFIED，不等於已合併、發布或實機驗收完成，見 [P0 操作與證據](../../../../docs/SAFE_WALK_P0_LIVE_PREVIEW.md)。

| 能力 | 已存在程式 | 正式流程仍缺少 |
|---|---|---|
| TownPass 入口 | 原生 root 預設 Live 步行預覽，Mock 顯式隔離；進入不定位／查路線。官方 `GeoLocatorService` 沿用既有註冊 | iPhone 完整入口驗收；Web 預設 Live provider 未配置 |
| 原生位置 | coordinator 在明確開始／重試、前景與兩份同意後，經 adapter lazy 呼叫 `GeoLocatorService.position()`；每次單次 GPS，有 8 秒逾時、取消、權限、精度與時效檢查 | 真 iPhone 首次授權／拒絕／服務關閉、位置與取消驗收；不補示範座標 |
| 導航控制 | coordinator → 既有 controller → M2 OSRM，scope 交 M3 `SafeWalkLiveMapView`；保護 requestId、模式、撤回、背景／SOS／返回與遲到回應 | gates true 只表示受控預覽程式已接線，不是 LIVE_VERIFIED；真路線／UI／裝置證據待補 |
| 據點 | Mock 模式保留 Mock repository；本輪 Live 不載入示範據點，附近據點／回報顯示未配置 | Live repository 的產品接線、來源／有效性與 UI；不將 M4 其他獨立成果視為本輪已啟用 |
| 音訊 | 預設 `TtsSafeWalkSpeaker.device()` 已接 M5，保留已合併 #26 lifecycle 修正；SOS 優先 stop，離開 dispose | iPhone 真聲音、缺 voice 文字預覽、背景／回前景及中斷驗收 |
| 系統求助交接 | `requestEmergency()` 契約與 Mock SOS 流程存在 | `TownPassPlatformAdapter` 尚無 dial/share/report adapter，任何旗標仍回 `not_configured`；需實作系統撥號/官方入口交接 |
| 附近協助者 | service、RPC transport、匿名 UUID store 與 SQL 已合併；Supabase 有獨立唯讀連線檢查 | **BLOCKED**：可信身分、接收資格、ownership、RLS/RPC、頻率、防濫用、保留刪除與後端/裝置驗證；未接主 App |

原生入口已由固定 Mock 改為受控 Live 預覽，Mock 保留為顯式獨立模式。不得以 Live 字樣替尚未驗收能力背書；查詢失敗／取消不切回 Mock。不同能力分別驗收，附近通知尚未就緒不能阻擋合法 GPS、路線、資料查詢、TTS 或主動系統求助入口的後續工程。

## 位置與同意

位置失敗沿用 `denied`／`timeout`／`unavailable`／`unsupported`；取消可拋 `SafeWalkCancelledException`，由平台接線忽略過期回應或以 unavailable 加清楚訊息呈現，不新增 wire status。Adapter 拒絕缺少實測精度、native mocked、精度超過 100 公尺、超過 60 秒或超前 30 秒的位置；不得補 DemoGeo。

定位權限與將起訖座標送往第三方 OSRM／Overpass 的同意必須分開。使用者撤回第三方同意、換目的地、取消、SOS、離開或背景中斷應取消目前路線並清除舊結果。navigation 只消費平台入口取得的位置，不另註冊 GPS watcher；必要時由使用者主動更新。位置及危難筆記不寫入日誌，正式流程不得默默外傳。

本輪兩份同意預設 false；地圖點選／輸入座標只設定目的地，按「開始或重試預覽」才 `openNavigation` + `planDestination`。撤回任一同意、背景、返回、通話或 SOS 清位置／路線並鎖 inactive，回前景／再勾選不自動查詢。Live request 由 coordinator 以有效 GPS 建立，舊 request factory API 留給顯式 Mock；Web 預設未配置 Live 路由。

## 求助與附近通知的不同條件

求助不等待定位成功。求助接線先中斷陪伴及路線，再執行使用者選擇的系統交接；不以介面成功或受理編號暗示已接通、警方已接案或派遣。未獲官方授權不得自動送警消案件。

附近協助者不是官方警消通報。`supabase/nearby_emergency.sql` 的 security-definer RPC 目前接受呼叫者 UUID 並授權 anon，沒有身分與資料所有權核對；表級 RLS 本身不能補上缺口。不得僅憑匿名 UUID、公開 key、按下同意或增加 Live 旗標就公開傳送陌生人的精確位置。部署前提與既有唯讀連線證據見 [Supabase](../../../../docs/SAFE_WALK_SUPABASE.md)。

## 驗證與後續交付

既有 `townpass_platform_adapter_test.dart`、`safe_walk_integration_test.dart`、`integration/safe_walk_navigation_controller_test.dart`、`integration/safe_walk_navigation_wiring_test.dart`、TTS／Supabase／nearby 測試供回歸使用，多數採 fake 或本機伺服器。歷史測試數量不代表目前全部通過；本輪執行結果以 PR 驗證紀錄為準。測試 scope 不等於 M3 已顯示真實路線，Mock unit tests 不等於 LIVE_VERIFIED。

P0 先完成 GPS、第三方同意、M2 OSRM、M3 真實地圖與 RouteResult 接線；P1 再接合法真實據點、外部導航、裝置 TTS 驗收與官方求助交接。每次啟用依 [上線條件表](../../../../docs/SAFE_WALK_LIVE_READINESS.md)附真實 Provider 及 iPhone 證據，以 PR 與 CI 審查，不自行 merge 或改動官方 upstream。
