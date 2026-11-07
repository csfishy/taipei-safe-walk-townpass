# M3｜莅紋：安心行 UI/UX

**現行政策：LIVE-FIRST DEVELOPMENT + NO PRODUCTION MOCK。** 正式入口只能呈現真實資料與操作結果；Mock／DemoGeo／假異常點／固定 ETA／固定成功不能進入正式流程。Fake／fixtures 僅供隔離測試；未配置回 Unavailable、真實阻塞與下一步。新功能直接完成真實 Provider 到 UI 的閉環，不須先交付 Demo，見 [完成定義](../../../../docs/SAFE_WALK_LIVE_FIRST.md)。

所有成員均可跨 M1～M5 修改功能與相應測試，自行 AI Coding、除錯及建立 PR。修改其他模組時說明目的、影響檔案及原主要負責人，先核對進行中的 PR 避免同時改同一檔；普通 Level A 變更不需小魚事前批准，Level B 合併前確認；Level C 合併前須隊長明確授權及安全／隱私審查，正式啟用前完成適用驗收。完整規則見 [開放協作](../../../../docs/SAFE_WALK_COLLABORATION.md)。

先讀根目錄 AGENTS、[Live MVP](../../../../docs/SAFE_WALK_LIVE_MVP.md)、[Live Readiness](../../../../docs/SAFE_WALK_LIVE_READINESS.md)、[五人模組契約](../../../../docs/SAFE_WALK_MODULES.md)、[導航接線契約](../../../../docs/SAFE_WALK_NAVIGATION_PRESENTATION_CONTRACT.md) 與 [顏色規範](../../../../docs/SAFE_WALK_COLOR_SPEC.md)。初始化文件是歷史紀錄，不再以「不得建立 UI」阻擋正式功能。莅紋是正式 UI/UX 設計主要負責人；任何成員可維護一般 UI／callback／狀態及測試，正式 UI 大型改版須在合併前由莅紋確認。本次只改文件，不改版面或色彩。

## 歷史畫面設計與待修正現況（2026-11-07）

以下表格與互動記錄保留原 UI 的設計／行為，不是允許 Mock 正式交付的現行規範。2026-11-08 main `7b99fea` 經 #49 恢復早期快照，Flow 仍有這些示範資料路徑；#35 的 Live coordinator／UI 已被撤回。正式入口須另以程式 PR 修正，不能把表格中的示範成功或語音未配置當成已完成。

稽核基線 `03f98f2b7b5254db73774c4d097eb4d610499c2c`。已由 M1 從臺北通「服務 > 臺北安心行」與首頁入口卡進入（`SafeWalkCompositionRoot` → `SafeWalkFlow`），畫面與 route API 已合併。`presentation/` 與 `test/features/safe_walk/presentation/` 是主要路徑，功能主責可同一 PR 跨 platform／navigation／資料／音訊完成接線與測試，不再受目錄獨占限制。以下為目前 Mock 畫面盤點，虛構街區、避讓件數及示範 ETA 不是 Live 驗收標準。

| 畫面 | 檔案 | 重點 |
|---|---|---|
| 入口 | `safe_walk_flow.dart` | `SafeWalkFlow`：切換以下畫面；對外動作全部經 callback 交給 M1 |
| 首頁 | `safe_walk_home_view.dart` | 上方臺北通 `TPAppBar` 主色長條＋右上 `CloseButton`（與 WebView 服務相同）；主卡讀屏標示示範、其他功能之後有低調的示範資料說明（不放 Mock 標籤）；時間情境卡；「安心行」主卡（點擊開始）；其他功能一項一行；最下方緊急求助 |
| 地圖 | `safe_walk_map_view.dart`、`demo_map.dart` | 預設回家路線（繞開異常回報，較短但經過異常的路線以虛線對照）、「已繞開 N 個異常回報」標籤、回家／**最近求助地點**切換（中性，不指定任何品牌）、文字路線（方向箭頭逐步）、在地圖上回報狀況與更新既有回報、**可收合的底部資訊框**（點把手或上下滑）、可開關的圖例、最底列左模擬來電右緊急求助 |
| 附近求助地點 | 同上（`MapStartView.points`） | 據點卡片由近到遠，點開看地址、電話、營業、合作認可、資料來源、更新時間，「帶我去這裡」；**載入中（骨架）、載入失敗（可重試）、沒有資料**三種狀態 |
| 模擬來電 | `safe_walk_call_view.dart` | 先出現**響鈴畫面**（光圈、手機震動約 18 秒後停止、拒絕／接聽；沒有鈴聲）。接聽後使用單一「疑似遭人跟蹤」嚇阻劇本：三段男性角色英文台詞由裝置 TTS 朗讀，中間兩段繁中台詞以大字顯示供使用者照讀；不要求麥克風、不錄音。最後一句英文播放後結束劇本，仍保留立即求助與模擬揭露。劇本 `mock/companion_scenarios.dart` 由 M5 JSON 產生，`safe_walk_companion_sync_test.dart` 檢查同步。語音未配置時以**無聲示範**呈現並註明。 |
| 緊急求助 | `safe_walk_emergency_view.dart` | 單獨一頁：110／119 紅色大按鈕（圖示＋使用時機）、**簡訊報警區塊**（選情況→預覽含時間／GPS／情況／附近據點的內容→勾選附上位置→傳送；示範模式顯示「示範完成／未傳送簡訊」，不會真的傳送）、告訴對方你在哪裡（取得位置中的載入狀態、失敗可重試）、安全提醒、「我現在安全，關閉」 |
| 共用樣式 | `safe_walk_ui.dart` | 全部引用 TPColors／TPTextStyles；陰影沿用官方 TPCard 的柔和投影；按下縮小＋換色、滑鼠移入變色；載入骨架、空值／錯誤訊息元件；系統關閉動畫時所有動畫為 0 |
| 示範資料 | `mock/safe_walk_demo_data.dart` | 虛構街區、示範據點（共用 `AssistancePoint`）；異常回報與簡訊範本為呈現層提案型別，需要跨模組持久 payload 時另提 Level B Schema 變更。來電劇本已沿用共用 `CompanionScenario`，不屬待定 Schema |
| 語音介面 | `safe_walk_speaker.dart` | `SafeWalkSpeaker`；`available == false` 時來電畫面寫「語音尚未配置，播放為無聲示範」，不呼叫 M1／M5 的喇叭 |
| 路線狀態 | `safe_walk_map_view.dart` 的 `RouteState` | 尚未配置（示範路線＋示範起點，不與真實位置混用）、計算中、失敗（原因＋再試一次＋改去最近求助地點）、成功（用 M2 的距離／時間／說明，標示「僅供參考」） |

### 色彩（11/7 使用者決定；相對顏色規範的例外）

- 主色使用臺北通 `TPColors.primary500`，上面放白字與白色圖示，與臺北通長條、服務卡及 `TPButton.primary` 一致。這是使用者 11/7 的決定。
- 白／`primary500` 對比約 **2.39:1**，低於 `SAFE_WALK_COLOR_SPEC.md` 與 WCAG 的對比要求；這項配色不能宣稱符合 WCAG。
- 主色系「文字」放在白底上時仍使用 `primary700`（`SwColors.brandText`）。緊急求助使用 `red600` 搭白字；異常回報使用 `secondary500`／`secondary800`，紅色只用在緊急求助。
- 沒有新增任何色碼。

### 互動與動畫（只在使用者操作時發生）

- 換頁：往深一層由右滑入、返回由左滑入；緊急求助由下方升起。
- 路線：切換目的地時從起點「畫」到終點（地圖上唯一的主動動畫）；分鐘數與「已繞開」標籤輕微放大出現。
- 回家／最近求助地點：選取底塊滑動到選到的那邊。
- 資訊框、文字路線、據點卡片：展開收合用高度動畫；回報成功訊息淡入。

### 為什麼沒有「最近 7-ELEVEN」

第二個目的地沿用中性的「最近求助地點」，由組合根注入 safety_data 據點；目前組合根仍供 Mock。M2 已有不限品牌的 OSM 便利商店來源與 NearestStorePlanner，尚未接 App，不應再描述成未改名的 7-ELEVEN 查詢。來源、營業與認可資訊須如實呈現，便利商店／AED 不直接等於政府認證救援據點；第三方查詢要另取得使用者同意。

## 既有 constructor 與目前接線

以下是目標接線示意，不是可直接貼用的程式，也不代表 main 已完成。正式入口必須為 Live，null／缺 callback 時回明確 Unavailable，不能補 Demo。DataMode wire 保留 mock／live 相容性，mock 僅供隔離測試；Unavailable 沿用既有 failure／reason。

```dart
SafeWalkFlow(
  mode: sw.DataMode.live,          // 正式入口唯一模式；仍須完成真實接線與驗收
  allowRealCalls: false,
  points: <真實來源 → M1 提供的 AssistancePoint>, // 缺配置回 Unavailable，不補 Demo
  pointsLoading: <載入中>, pointsError: <錯誤訊息>, onRetryPoints: <重試>,
  route: <RouteService.planRoute 的 RouteResult>,  // Live null 不得補 Demo
  routeLoading: <計算中>,
  onPlanRoute: (destination) => <用真實位置與 destination 呼叫 planRoute，結果傳回 route>,  // 明確開始／重試，重驗兩份同意及前景狀態
  speaker: <TTS 或 M5 音訊 Adapter 實作 SafeWalkSpeaker>,
  onLocate: () => platform.getCurrentPosition(mode: ..., userInitiated: true),
  onEmergency: (channel) => platform.requestEmergency(mode: ..., channel: channel, userInitiated: true, allowRealCalls: ...),
  onSendSms: (body) async => <開啟簡訊 App 的 OS handoff；回傳是否成功開啟>,   // Live 未配置不可模擬成功
  onExit: () => Get.back(),
)
```

- 官方路由與服務入口已由 M1 完成（`local://safe_walk`）。
- 路線 API 已存在；M1 組合根也已建立 M2 OSRM service 與 shared scope，但尚未把 route／routeLoading／onPlanRoute 傳給 Flow，Flow 也未消費 scope。隨 #29 交付的 `DemoMap` renderer 已接 flutter_map／OSM 底圖及投影，沿用類名而非固定 Demo 畫布；路線／點位仍 Mock，據點路線仍是 DemoGeo.lRoute。仍需真實 GPS、同意、lifecycle、Live 資料與完整模式分流，底圖子能力 WIRED_NOT_VERIFIED 不代表完整 Live UI 或裝置驗收。
- 異常回報與簡訊範本目前是呈現層提案型別；需要跨模組持久 payload 時才提出獨立 Schema 變更。來電劇本已有共用 CompanionScenario／M5 JSON 同步測試，不因接線重建第二套 Schema。
- M1 已預設注入 `TtsSafeWalkSpeaker.device()`，M5 本機 TTS 與離線語音檢查已合併；可用聲音確認後才朗讀，否則文字／無聲預覽。不再把「完全沒有音訊實作」當現況；真實 iPhone 播放與中斷仍須驗收。響鈴目前只有震動，未交付鈴聲音檔。TTS 不需麥克風權限。
- 簡訊報警需核對官方管道／收件號碼；涉及真實發送依 Level C 取得隊長明確授權及安全驗收。開啟簡訊 App 不代表警方已收到或受理。

## Live MVP 交付條件

- 正式流程 Live-only；Mock／Fake 僅限隔離測試。main 固定 Mock 是缺口，應修完整 Provider／UI／同意／取消接線，不能只將 readiness 設為 true。已驗收能力不受其他 BLOCKED 能力的全域模式限制。
- 使用者主動開始導航／更新位置才由平台入口取 TownPass 真實 GPS；定位權限與第三方路線查詢同意分開，提供拒絕及撤回。Flow 目前只在使用者進入地圖／換常用目的地／重試時呼叫既有 callback，無初始化自動規劃，但尚無完整 Live 同意／取消操作。
- 沿用既有 TownPass 介面與 #29 的 OSM 底圖 renderer，不因 `DemoMap` 類名重做底圖；接入並驗證正式 M2 RouteResult geometry、viewport、距離及可取得時間。GeoJSON 為 `[longitude, latitude]`；資料模式取決於來源與接線，真圖磚不會使 Mock 覆蓋物成為 Live，iPhone／底圖失敗呈現仍待驗。
- durationSeconds null 顯示未知；目前 RouteState.minutes 與據點卡會呼叫 walkMinutes，Live 必須移除這些示範 ETA。完整呈現 result／candidate warnings、explanations、provider、loading、cancel、error 與下一步。
- Live 不補 DemoGeo 起點、demoPlaces、demoPoints、demoAnomalies、L 形路線、虛構避險件數或示範地標。網路失敗提供錯誤／重試／Unavailable，不偷偷換 Mock，也不以 Google Maps 外連替代競賽 App 內導航；OSRM 路線不宣稱已驗證安全。
- 保留 Flow 已有座標 callback，由平台 adapter 建立 canonical request；最近據點／下一據點／帶我去也必須通知目的地變更及重新規劃。取消、換目的地、離開導航、切至通話、SOS、背景或撤回同意立即取消舊意圖；等待定位的 Future 需 generation 檢查，防止遲到重啟。
- 功能主責可直接在組合根接 RouteFollower 並把結果交 presentation，畫面不另開 GPS；目前尚未接 App。OSRM steps=false，現有幾何方向步驟不等於正式逐路口導航。
- Live 的撥號、簡訊／官方通報入口明示 handoff 狀態，開啟不等於接通、送達、受理或派遣；附近協助者與官方派遣的 BLOCKED 條件不阻擋合法導航、TTS 或使用者主動開啟求助管道。
- 莅紋持續負責設計方向與大型正式 UI 改版的 Level B 確認；一般 UI／callback 修正由任何成員開發並經 Level A Review。色彩依既有規範及下列已記錄例外，本次文件轉向不改版面。

## 臺北通入口（M1 已完成）

- 「服務 > 我的服務」：`MyServiceItemId.safeWalk`（圖示 `assets/svg/icon_safe_walk_24.svg`，臺北通服務 icon 配色）→ `local://safe_walk`。
- 首頁安心行功能卡（PR #11）。

## 語言（中／英）

臺北通設定頁已有「語言」選項（`LanguageViewController`：繁中、English），但官方目前 `onIndexChange` 仍是 TODO，**整個 App 尚未實作切換**，文字都寫死中文。建議安心行先做「跟隨 App 語系」：M3 把畫面文字集中成中英對照表，依 `Localizations.localeOf(context)` 顯示；等 M1 在語言頁呼叫 `Get.updateLocale()` 後，安心行會自動跟著切換，不需要另做一顆語言鈕。

## 驗證

- 現有 `test/features/safe_walk/presentation/` 包含流程、版面回歸、320px／200% 文字、無障礙 guideline、路線接口（計算中／失敗／成功／換目的地規劃）、劇本同步及通話 lifecycle 測試。這是內容盤點，測試結果須附當次 SHA／CI run，不把既往分支結果當成本次 PASS。
- 無障礙自動檢查（點擊區域、讀屏名稱、文字對比）不等於 TalkBack／VoiceOver 實測。
- 設計截圖：`M3_SCREENSHOTS=1 flutter test test/features/safe_walk/presentation/safe_walk_screenshots_test.dart --update-goldens`（需 `FLUTTER_ROOT`），產出 `screenshots/*.png`；CI 預設略過。
- 本機預覽完整臺北通：`flutter run -d web-server --web-port 5191 --web-hostname 127.0.0.1`（`web/` 只在本機）。
- 未有充分完成證據：iPhone 實機／讀屏、真實路線服務與 Live 地圖全流程、裝置實際朗讀。Mock／fake transport 或 screenshot test 不等於 LIVE_VERIFIED；啟用條件見 Live Readiness。
