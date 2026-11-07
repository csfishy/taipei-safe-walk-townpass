# 臺北安心行：TownPass 原生架構基線

2026-11-07，正式取代 React 主 App 方向；初始化 PR 待確認合併。本文件描述模組與接點，不定義 UI 版面或 Widget 架構。

## 官方基底與保留範圍

- 官方來源：<https://github.com/taipei-doit/TownPass>，完整 Git 歷史，Base `c8e5d4d3f8f699f3d9d6cd68e129ed4da12037b3`，版本記錄見 `SAFE_WALK_UPSTREAM.json`。
- Flutter 3.47.6／Dart 3.13.5，依 `.fvmrc` 與官方 lock；GetX、json_serializable、geolocator、url_launcher 沿用官方依賴，不自行全量升級。
- `lib/main.dart` 的原始 MyApp／Theme／initServices、`lib/page/` 的官方畫面、`TPRoute`、`TPColors`、登入會員、原生 branding、iOS／Android 與 LICENSE 保留。
- `origin` 是團隊 Public Repo（2026-11-07 使用者確認保留 Public）；`upstream` 保留官方，只讀同步。新 Repo 的 main 先是官方基底，安心行變更經 migration PR 審查後才成為共同基線。

## 新增模組邊界

`lib/features/safe_walk/` 下的 platform／navigation／presentation／safety_data／companion／shared 為同一個 Flutter App 內的模組；不新增五個 App、後端或資料庫。

| 模組 | 交付接點 | 本次不包含 |
|---|---|---|
| M1 platform | PlatformService、TownPass 資料 Adapter、位置／求助服務契約 | SOS 畫面、官方案件發送 |
| M2 navigation | RouteService、座標／路徑模型與測試 | 地圖頁、第二份 GPS 訂閱 |
| M3 presentation | 設計權與交付邊界 README | 所有新畫面與預設 Widget Tree |
| M4 safety_data | Parser、Repository、來源與正規化模型 | 自建資料服務、假即時資料 |
| M5 companion | 無 UI Controller／Audio Adapter 契約與測試接點 | 通話頁、假報案／真人接聽 |
| shared | 單一 JSON Schema、Dart models、validator／語意檢查、取消協定 | 第二套獨立欄位定義 |

詳細輸入輸出、狀態與所有權見 `SAFE_WALK_MODULES.md`／`SAFE_WALK_SCHEMA.md`。

## 官方接點與最小侵入計畫

1. **位置**：官方 `GeoLocatorService.position()` 已處理服務與權限；M1 的 Adapter 可以按明確使用者操作取得該服務並轉為安心行 Position。模組載入／測試不可自動取位置。M2 只接收 Position，處理座標不等於另外啟動 GPS。
2. **GetX**：`TPRoute.page`／Bindings 仍由官方殼管理。本次不新增安全步行路由、不修改 `initServices()`；未來由 M1 在 M3 設計確認後協調 service 註冊與路由，不讓五人各改 main.dart。
3. **城市服務入口**：官方 `MyServiceItem`／`PinnedServiceItemWidget` 最終交由 `TPRoute.openUri()`。本次只記錄接點，不新增服務圖示、卡片或條目。
4. **WebView 相容方案**：保留 `TPWebView`／`TPInAppWebView` 與 `flutterObject` bridge。現有訊息封裝是 `{name, data}`，包括 `location`、`phone_call` 等；安心行 Schema payload 並不自動等於 bridge 封裝。若主辦要求以 WebView 交付，M1 應另外核對來源、使用者同意與回傳映射，再經審查增加 Adapter，不重做官方 WebView 或假稱已接通。
5. **Theme／色彩**：只新增 `SAFE_WALK_COLOR_SPEC.md`，引用原有 TPColors。舊 React Design System 為 Legacy，不是本架構的強制 UI 規範。

## Schema 與獨立開發

保留 React Schema 1.0.0 原始欄位、nullable、strict unknown-field 拒絕、mock/live 及受理限制，改用 Dart Model／Adapter。原始 JSON Schema 為唯一來源，產出型別與 runtime schema bundle須可重產並檢查；fixtures 用於不啟動官方 UI 的資料／服務測試。失敗必須有明確狀態，未設定的 live provider 不回 mock 假成功。

## Legacy 成果保留與遷移順序

<https://github.com/csfishy/taipei-safe-walk> 保留原 Git 歷史、React App、文件、M2 查詢及預發佈 PR，不覆蓋／關閉／刪分支。M5 `feat/m5-companion` 的 `4a4d259` 也保留；已發現的音訊暫停／遲到 Promise／callback 清理問題須在 Dart 控制器工作時用測試防止重現，不能機械搬移 React hooks。

先合併本初始化 PR，再由五位從相同 Commit 建分支，以模組 PR 分別移植資料、服務與邏輯。M3 決定所有新增畫面；本輪不移植 CSS、預設首頁、地圖、SOS 或陪伴版面。舊錄音／第三方資料若未交付或未驗證，不列為已移植。

## 交件與授權

官方 GPLv3 LICENSE 不更換。2026 競賽資料及 AGPL 要求的證據、原生／WebView 交付形式與待確認事項見 `SAFE_WALK_COMPETITION_LICENSE.md`；工程上能編譯不等於已通過主辦資格或法律審核。
