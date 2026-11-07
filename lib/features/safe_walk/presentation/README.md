# M3｜莅紋：安心行 UI/UX

先讀根目錄 AGENTS、官方初始化文件、[五人模組契約](../../../../docs/SAFE_WALK_MODULES.md) 與 [顏色規範](../../../../docs/SAFE_WALK_COLOR_SPEC.md)。

## 畫面（2026-11-07）

已由 M1 從臺北通「服務 > 臺北安心行」與首頁入口卡進入（`SafeWalkCompositionRoot` → `SafeWalkFlow`）。M3 只改 `presentation/` 與 `test/features/safe_walk/presentation/`。

| 畫面 | 檔案 | 重點 |
|---|---|---|
| 入口 | `safe_walk_flow.dart` | `SafeWalkFlow`：切換以下畫面；對外動作全部經 callback 交給 M1 |
| 首頁 | `safe_walk_home_view.dart` | 上方臺北通 `TPAppBar` 主色長條＋右上 `CloseButton`（與 WebView 服務相同）；主卡讀屏標示示範、其他功能之後有低調的示範資料說明（不放 Mock 標籤）；時間情境卡；「安心行」主卡（點擊開始）；其他功能一項一行；最下方緊急求助 |
| 地圖 | `safe_walk_map_view.dart`、`demo_map.dart` | 預設回家路線（繞開異常回報，較短但經過異常的路線以虛線對照）、「已繞開 N 個異常回報」標籤、回家／**最近求助地點**切換（中性，不指定任何品牌）、文字路線（方向箭頭逐步）、在地圖上回報狀況與更新既有回報、**可收合的底部資訊框**（點把手或上下滑）、可開關的圖例、最底列左模擬來電右緊急求助 |
| 附近求助地點 | 同上（`MapStartView.points`） | 據點卡片由近到遠，點開看地址、電話、營業、合作認可、資料來源、更新時間，「帶我去這裡」；**載入中（骨架）、載入失敗（可重試）、沒有資料**三種狀態 |
| 模擬來電 | `safe_walk_call_view.dart` | 先出現**響鈴畫面**（光圈、手機震動、拒絕／接聽；沒有鈴聲）；接聽前可選 M5 的六個劇本。接聽後為 **M5 劇本一問一答**：對方一句、自己回一句，對方才接下一句；沒有上方地圖條，回覆區（快速回覆／完整句子／自己輸入）可收合。只朗讀對方台詞（點泡泡重播／停止），自己的回應只顯示文字；「自己輸入」是輸入**對方要說的話**。劇本 `mock/companion_scenarios.dart` 由 M5 JSON 產生，`safe_walk_companion_sync_test.dart` 檢查同步。語音未配置時以**無聲示範**呈現並註明；不要求麥克風。 |
| 緊急求助 | `safe_walk_emergency_view.dart` | 單獨一頁：110／119 紅色大按鈕（圖示＋使用時機）、**簡訊報警區塊**（選情況→預覽含時間／GPS／情況／附近據點的內容→勾選附上位置→傳送；示範模式只模擬「已送出」畫面，不會真的傳送）、告訴對方你在哪裡（取得位置中的載入狀態、失敗可重試）、安全提醒、「我現在安全，關閉」 |
| 共用樣式 | `safe_walk_ui.dart` | 全部引用 TPColors／TPTextStyles；陰影沿用官方 TPCard 的柔和投影；按下縮小＋換色、滑鼠移入變色；載入骨架、空值／錯誤訊息元件；系統關閉動畫時所有動畫為 0 |
| 示範資料 | `mock/safe_walk_demo_data.dart` | 虛構街區、示範據點（共用 `AssistancePoint`）；異常回報、來電劇本、簡訊範本為**提案型別**，待 M1 納入 Schema |
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

公共服務不能偏好特定品牌，所以第二個目的地改成中性的「最近求助地點」（來源是 M4 的求助地點資料，便利商店只是其中一種類型）。M2 的 7-ELEVEN 查詢若要保留，建議改成「附近便利商店」並維持使用者同意後才查詢。

## 給 M1 的接線需求

```dart
SafeWalkFlow(
  mode: sw.DataMode.mock,          // 顯式傳入
  allowRealCalls: false,
  points: <M4 → M1 提供的 AssistancePoint>,   // null 時用 M3 示範資料
  pointsLoading: <載入中>, pointsError: <錯誤訊息>, onRetryPoints: <重試>,
  route: <RouteService.planRoute 的 RouteResult>,  // null 且 routeLoading=false → 示範路線
  routeLoading: <計算中>,
  onPlanRoute: (destination) => <用目前位置與 destination 呼叫 planRoute，結果傳回 route>,  // 進入、換目的地、按「再試一次」時呼叫
  speaker: <TTS 或 M5 音訊 Adapter 實作 SafeWalkSpeaker>,
  onLocate: () => platform.getCurrentPosition(mode: ..., userInitiated: true),
  onEmergency: (channel) => platform.requestEmergency(mode: ..., channel: channel, userInitiated: true, allowRealCalls: ...),
  onSendSms: (body) async => <開啟簡訊 App 的 OS handoff；回傳是否成功開啟>,   // null 時只模擬
  onExit: () => Get.back(),
)
```

- 官方路由與服務入口已由 M1 完成（`local://safe_walk`）。
- 路線：M3 已提供 `route`／`routeLoading`／`onPlanRoute`；M1 接上 M2 `RouteService` 即可，未接前畫面維持示範路線。求助地點的路線仍是示範。
- 異常回報、來電劇本、簡訊範本需要 Schema。
- 朗讀與鈴聲需要音訊播放（pubspec 由 M1 管理）或 M5 Adapter，須另外核准；目前不發出聲音。
- 簡訊報警的收件號碼由 M1 決定；開啟簡訊 App 不代表警方已收到或受理。

## 臺北通入口（M1 已完成）

- 「服務 > 我的服務」：`MyServiceItemId.safeWalk`（圖示 `assets/svg/icon_safe_walk_24.svg`，臺北通服務 icon 配色）→ `local://safe_walk`。
- 首頁安心行功能卡（PR #11）。

## 語言（中／英）

臺北通設定頁已有「語言」選項（`LanguageViewController`：繁中、English），但官方目前 `onIndexChange` 仍是 TODO，**整個 App 尚未實作切換**，文字都寫死中文。建議安心行先做「跟隨 App 語系」：M3 把畫面文字集中成中英對照表，依 `Localizations.localeOf(context)` 顯示；等 M1 在語言頁呼叫 `Get.updateLocale()` 後，安心行會自動跟著切換，不需要另做一顆語言鈕。

## 驗證

- `flutter test test/features/safe_walk`：除 Windows 上 `contracts_test` 的 CRLF 既有問題外全部通過（CI 上通過）。包含流程、版面回歸、320px／200% 文字、無障礙 guideline、路線接口（計算中／失敗／成功／換目的地重新規劃）。
- 無障礙自動檢查（點擊區域、讀屏名稱、文字對比）不等於 TalkBack／VoiceOver 實測。
- 設計截圖：`M3_SCREENSHOTS=1 flutter test test/features/safe_walk/presentation/safe_walk_screenshots_test.dart --update-goldens`（需 `FLUTTER_ROOT`），產出 `screenshots/*.png`；CI 預設略過。
- 本機預覽完整臺北通：`flutter run -d web-server --web-port 5191 --web-hostname 127.0.0.1`（`web/` 只在本機）。
- 未驗：實機、讀屏實測、真實路線服務、真實朗讀。
