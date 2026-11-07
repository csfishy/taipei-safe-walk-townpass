# M3｜莅紋：安心行 UI/UX

先讀根目錄 AGENTS、官方初始化文件、[五人模組契約](../../../../docs/SAFE_WALK_MODULES.md) 與 [顏色規範](../../../../docs/SAFE_WALK_COLOR_SPEC.md)。

## 第一版畫面（2026-11-07，本機開發中，尚未接官方路由）

由 Legacy React 版的設計移植到 TownPass Flutter；只改 `presentation/` 與 `test/features/safe_walk/presentation/`，官方 main、pages、Theme、TPColors、GetX route 都沒有動。

| 畫面 | 檔案 | 重點 |
|---|---|---|
| 入口 | `safe_walk_flow.dart` | `SafeWalkFlow`：切換以下畫面；對外動作全部經 callback 交給 M1 |
| 首頁 | `safe_walk_home_view.dart` | 四個入口由上到下（安心回家、模擬來電、附近求助地點、回報狀況）＋最下方緊急求助；示範模式標示 |
| 地圖 | `safe_walk_map_view.dart`、`demo_map.dart` | 預設回家路線（繞開異常回報，較短但經過異常的路線以虛線對照）、「已繞開 N 個異常回報」標籤、回家／**最近求助地點**切換（中性，不指定任何品牌）、文字路線（方向箭頭逐步）、在地圖上回報狀況與更新既有回報、**可收合的底部資訊框**（點把手或上下滑）、可開關的圖例、最底列左模擬來電右緊急求助 |
| 附近求助地點 | 同上（`MapStartView.points`） | 據點卡片由近到遠，點開看地址、電話、營業、合作認可、資料來源、更新時間，「帶我去這裡」；**載入中（骨架）、載入失敗（可重試）、沒有資料**三種狀態 |
| 模擬來電 | `safe_walk_call_view.dart` | 只朗讀對方台詞（點泡泡重播／停止）；自己的回應只顯示文字；「自己輸入」是輸入**對方要說的話**；地圖縮成 **Google Maps 式子母畫面**（浮在對話上、顯示分鐘數、左右滑可換邊、點一下回地圖）；不要求麥克風 |
| 緊急求助 | `safe_walk_emergency_view.dart` | 單獨一頁：110／119 紅色大按鈕（圖示＋使用時機）、**簡訊報警區塊**（選情況→預覽含時間／GPS／情況／附近據點的內容→勾選附上位置→傳送；示範模式只模擬「已送出」畫面，不會真的傳送）、告訴對方你在哪裡（取得位置中的載入狀態、失敗可重試）、安全提醒、「我現在安全，關閉」 |
| 共用樣式 | `safe_walk_ui.dart` | 全部引用 TPColors／TPTextStyles；陰影沿用官方 TPCard 的柔和投影；按下縮小＋換色、滑鼠移入變色；載入骨架、空值／錯誤訊息元件；系統關閉動畫時所有動畫為 0 |
| 示範資料 | `mock/safe_walk_demo_data.dart` | 虛構街區、示範據點（共用 `AssistancePoint`）；異常回報、來電劇本、簡訊範本為**提案型別**，待 M1 納入 Schema |
| 語音介面 | `safe_walk_speaker.dart` | `SafeWalkSpeaker`；預設 `UnavailableSpeaker`（畫面寫「語音尚未配置，只顯示文字」） |

### 色彩（依 SAFE_WALK_COLOR_SPEC）

- 白字只放在 `primary700`（5.89:1）與 `red600`（5.51:1）上；官方 `TPButton.primary`（白字配 `primary500`，2.39:1）與 `TPButton.alarm`（`red500`）不符合規範，所以沒有直接使用。
- `primary500` 只當品牌點綴、邊框、選取框；異常回報用 `secondary500`／`secondary800`；紅色只用在緊急求助。
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
  speaker: <TTS 或 M5 音訊 Adapter 實作 SafeWalkSpeaker>,
  onLocate: () => platform.getCurrentPosition(mode: ..., userInitiated: true),
  onEmergency: (channel) => platform.requestEmergency(mode: ..., channel: channel, userInitiated: true, allowRealCalls: ...),
  onSendSms: (body) async => <開啟簡訊 App 的 OS handoff；回傳是否成功開啟>,   // null 時只模擬
  onExit: () => Get.back(),
)
```

- 需要官方路由（例如服務卡進入安心行）註冊 `SafeWalkFlow`。
- 回家路線目前用 M3 示範路線；接 M2 `RouteService` 後改用 `RouteResult`。
- 異常回報、來電劇本、簡訊範本需要 Schema。
- 朗讀需要 TTS 套件（pubspec 由 M1 管理）或 M5 Adapter。
- 簡訊報警的收件號碼由 M1 決定；開啟簡訊 App 不代表警方已收到或受理。

## 驗證

- `flutter analyze lib/features/safe_walk/presentation test/features/safe_walk/presentation`：無問題。
- `flutter test test/features/safe_walk/presentation`：7 項流程測試通過（首頁、緊急求助不撥號、地圖已繞開與文字路線、最近求助地點與資訊框收合、求助地點載入／錯誤／空值、來電只朗讀對方、簡訊報警示範傳送）。
- 設計截圖：`M3_SCREENSHOTS=1 flutter test test/features/safe_walk/presentation/safe_walk_screenshots_test.dart --update-goldens`，產出 `screenshots/*.png`；CI 預設略過。
- 本機預覽：`flutter create --platforms=web .` 後執行 `flutter run -d web-server -t lib/features/safe_walk/presentation/preview/safe_walk_preview_main.dart`（`web/` 只在本機，不提交）。
- 未驗：實機、TownPass App 內接線、讀屏、真實朗讀。
