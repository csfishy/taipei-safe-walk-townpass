# 臺北安心行 · Taipei Safe Walk

[![Safe Walk CI](https://github.com/csfishy/taipei-safe-walk-townpass/actions/workflows/safe_walk.yml/badge.svg)](https://github.com/csfishy/taipei-safe-walk-townpass/actions/workflows/safe_walk.yml)
[![check-and-build](https://github.com/csfishy/taipei-safe-walk-townpass/actions/workflows/build.yml/badge.svg)](https://github.com/csfishy/taipei-safe-walk-townpass/actions/workflows/build.yml)

臺北安心行是以臺北市政府 **TownPass** Flutter App 為基底開發的協作專案，參與「2026 臺北城市通微服務黑客松」。目標是讓使用者在夜間或不熟悉的路段，能查看步行路線、附近便利商店、公共安全相關資訊與求助管道，並可使用模擬陪伴語音功能。

> **重要：** 本專案為競賽開發中的作品，**不是官方市政服務**，不能取代 110、119 或任何官方求助管道。專案目前仍在 LIVE-FIRST 收斂中，各功能是否可用請以下方 [目前狀態](#目前狀態) 為準。

## 目錄

- [功能總覽](#功能總覽)
- [目前狀態](#目前狀態)
- [快速開始](#快速開始)
- [專案結構](#專案結構)
- [架構與模組分工](#架構與模組分工)
- [技術框架](#技術框架)
- [近期應用技術](#近期應用技術)
  - [守護區的區域警報](#守護區的區域警報)
- [資料、隱私與安全原則](#資料隱私與安全原則)
- [測試與驗證](#測試與驗證)
- [CI、預覽版與網站](#ci預覽版與網站)
- [建置](#建置)
- [協作流程](#協作流程)
- [文件索引](#文件索引)
- [官方來源與授權](#官方來源與授權)
- [免責聲明](#免責聲明)
- [致謝](#致謝)

## 功能總覽

| 功能 | 說明 | 狀態 |
|---|---|---|
| 步行路線規劃 | 以 OSRM 步行路網計算路線，回傳實際 geometry、距離與可取得的時間 | 已實作，尚未接入正式入口 |
| 路線跟隨 | 依 M1 提供的定位更新計算進度與偏離路線 | 已實作，尚未接入正式入口 |
| 50 公尺避讓路線 | 對回報點與有座標的犯罪參考點套用 50 公尺產品避讓緩衝，並以真實路網重新規劃 | 規格已定（見 [Live MVP](docs/SAFE_WALK_LIVE_MVP.md#50-公尺避讓規格)），程式經 PR #59 合併；驗收以 Readiness 為準 |
| 附近便利商店 | 以 OSM 查詢附近便利商店，並可選擇交由使用者自行開啟外部導航 | 已實作，尚未接入正式入口 |
| 全市月別暴力犯罪統計 | 來源抓取與解析已完成，用於呈現全市歷史統計（非即時路段風險） | 已實作，尚未接入 UI |
| 北北基犯罪參考資料 | 持久 Supabase 資料，App 只透過受限唯讀介面查詢 | 唯讀 Repository 與 SQL 已合併，尚未接入正式流程 |
| 陪伴語音模擬 | 使用裝置內建 TTS 播放模擬陪伴內容；無可用引擎時顯示文字預覽 | 已接線，待實機驗收 |
| 本機核准音訊 | 播放經授權的本地音檔 | 未實作 |
| 110／119 系統撥號與官方通報入口 | 使用者主動點選後開啟手機撥號畫面（自己按撥號），並可開啟臺北通既有的線上報案服務；app 不會代撥、代報或派遣 | 已接線於正式入口，待實機驗收；簡訊報案號碼尚未核對，仍未配置 |
| 附近協助者位置通知 | 通知附近已加入的協助者 | 受阻（BLOCKED）：缺可信身分、權限與防濫用機制 |
| 守護區區域警報 | 協助者主動設定最多 3 個區域，SOS 落在範圍內時納入通知對象；透過 App 內橫幅接收 | 已隔離實作；後端部署、資格／防濫用與雙裝置驗收待完成，維持 BLOCKED |
| 警消案件自動派遣 | 自動送出警消案件 | 受阻（BLOCKED）：無官方授權；`officialReceipt` 恆為 `null` |

進入點：安心行會從 TownPass **首頁新聞上方的「臺北安心行」功能卡片**，或「城市服務」的釘選項目開啟，兩處進入同一個原生功能頁，返回後回到原本的 TownPass 畫面。

## 目前狀態

本專案採 **LIVE-FIRST DEVELOPMENT + NO PRODUCTION MOCK** 政策：正式交付只接受真實、可操作、可驗證的完整使用者流程。Mock、Fake、fixtures 只能用於隔離測試，不能由正式入口選用；能力尚未完成時回報 **Unavailable**、真實原因與下一步，不以示範資料假裝成功。

能力狀態使用下列五種標記（與 [Live Readiness](docs/SAFE_WALK_LIVE_READINESS.md) 一致）：

| 標記 | 意義 |
|---|---|
| IMPLEMENTED_NOT_WIRED | 已實作，但正式操作流程尚未使用 |
| WIRED_NOT_VERIFIED | 已接入流程，但缺真實 Provider 或裝置驗收 |
| LIVE_VERIFIED | 已有可追溯的正式接線、權限、同意、失敗處理與真實驗收證據 |
| BLOCKED | 缺必要身分、安全、資料權限或官方授權，不能公開啟用 |
| NOT_IMPLEMENTED | 尚無正式實作 |

依 [Live Readiness](docs/SAFE_WALK_LIVE_READINESS.md) 的 2026-11-08 基線（main `7b99fea`），截至該基線：

- **正式入口仍固定使用 Mock 資料**，導航、據點與求助流程尚未切換為真實 Provider，這是待修正的缺口。
- 目前**沒有任何能力被標為 LIVE_VERIFIED**。
- 真實 GPS、OSRM 路線、TTS 等能力的個別實作或接線已存在，但仍需正式入口接線與實機驗收。
- 附近協助者通知與警消派遣維持 BLOCKED。

main 之後又有新的合併（例如 PR #59），文件基線與程式可能不同步。請以各 PR 的程式、CI 結果與最新 Readiness 文件為準，不要把本段視為最新驗收結論。

## 快速開始

### 環境需求

| 工具 | 版本或說明 |
|---|---|
| Git | 任何近期版本 |
| Python 3 | 須為真正可執行的直譯器（Windows 不要使用 Microsoft Store 的 `python` 別名） |
| Flutter / Dart | **Flutter 3.47.6**／**Dart 3.13.5**，版本固定於 [.fvmrc](.fvmrc)，建議使用 [FVM](https://fvm.app/) |
| Android SDK | 建置或執行 Android 時需要 |
| Xcode | 建置 iOS 時需要（僅 macOS；Windows 無法本機編譯 iOS） |
| Chrome | 執行 Web 與 Chrome 測試時需要 |

### 取得原始碼

```bash
git clone --branch main https://github.com/csfishy/taipei-safe-walk-townpass.git
cd taipei-safe-walk-townpass
git fetch origin
```

### 安裝依賴與產生檔案

若使用 FVM，先執行 `fvm install`，並把下列 `flutter`、`dart` 指令分別換成 `fvm flutter`、`fvm dart`。**不要**以套件 upgrade 或重建 lockfile 來排除版本差異。

順序很重要：**先產生 metadata，再執行 `pub get`**。

```bash
flutter --version
dart --version
python3 tool/release_metadata.py
flutter pub get --enforce-lockfile
dart run build_runner build
dart run tool/generate_safe_walk_contracts.dart --check
dart run tool/check_safe_walk_baseline.dart
```

`tool/release_metadata.py` 會產生 `assets/build-info.json`（版本、build number、source commit、Flutter 版本）。這個檔案與 Dart 生成產物都不手改；Schema 產物則必須與版控中的來源保持一致。

Windows 可改用：

```powershell
py -3 tool/release_metadata.py
```

若已安裝 WSL 與 Linux 版 Python 3，也可在 clone 根目錄執行 `wsl python3 tool/release_metadata.py`。WSL 不是必要條件。

### 執行

```bash
flutter devices
flutter run -d chrome          # Web
flutter run -d <裝置 ID>        # Android 或 iOS 實機／模擬器
```

Android、iOS 執行前需先安裝對應 SDK、模擬器或準備實機。執行時請勿使用真實緊急電話、官方登入或真實通報流程做測試。

## 專案結構

```text
.
├── lib/
│   ├── main.dart                  # 官方 TownPass 入口（沿用）
│   ├── page/                      # 官方 TownPass 頁面（沿用）
│   ├── util/                      # 官方共用元件、TPColors、TPRoute（沿用）
│   └── features/safe_walk/        # 臺北安心行功能
│       ├── shared/                # 共用 models、contracts、取消協定
│       ├── navigation/            # 路線、OSRM、RouteFollower、避讓、便利商店（M2）
│       ├── safety_data/           # 犯罪統計、犯罪參考資料、據點資料（M4）
│       ├── companion/             # 陪伴控制器、TTS、音訊（M5）
│       ├── platform/              # 定位、求助、Supabase、通知（M1）
│       │   └── integration/       # 跨模組組合根（composition root）
│       └── presentation/          # 安心行 UI（M3）
├── schemas/safe_walk/v1/          # JSON Schema：payload 的唯一來源
├── test/                          # 官方與安心行測試、fixtures
├── tool/                          # 產生器、一致性檢查、發佈與 metadata 工具
├── scripts/                       # 示範資料庫重設與 Python 測試
├── supabase/                      # SQL：犯罪參考資料、示範資料、附近通知
├── docs/                          # 規格、架構、狀態、建置與協作文件
├── assets/、fonts/                 # 官方資產與字型
├── android/、ios/、web/            # 平台工程
└── .github/workflows/             # CI 與預覽建置
```

## 架構與模組分工

本專案是**同一個 Flutter App**，採 Feature-First、軟性所有權與契約式整合：

- **Feature-First**：安心行功能集中在 `lib/features/safe_walk/`，不改寫官方 App 的殼與主題。
- **軟性所有權**：每個模組有主要聯絡人與主要負責範圍，但**任何成員都可以修改各模組的功能程式與測試**，不以資料夾限制作者。
- **契約式整合**：業務模組只依賴自身與 `shared/`，透過依賴注入組合；具體的跨模組實作組合放在 `platform/integration/`。

| 模組 | 主要聯絡人 | 主要範圍 |
|---|---|---|
| M1 平台 | 小魚 | `platform/`、`shared/`、composition、套件與 route、原生設定、CI |
| M2 導航 | Steven | `navigation/`：OSRM、RouteFollower、目的地與據點路線 |
| M3 呈現 | 莅紋 | `presentation/`：正式 UI/UX 設計方向與重大改版 |
| M4 公共安全資料 | 信義 | `safety_data/`：來源、Parser、Repository、資料品質 |
| M5 陪伴 | 奶爸 | `companion/`：控制器、TTS／音訊、清理與中斷 |

### 資料契約

- **JSON Schema 是單一來源**：`schemas/safe_walk/v1/contracts.schema.json`。Dart 模型與 runtime schema 由 `dart run tool/generate_safe_walk_contracts.dart` 重新產生，再以 `--check` 驗證一致。不要手改生成檔，也不要在各模組另外定義相同 payload 的型別。
- **座標與時間**：經緯度採 WGS84；內部使用 `Coordinates(lat, lng)`，GeoJSON 使用 `[lng, lat]`；距離以公尺、時間以秒計；時間保留 RFC3339 字串與時區。
- **未知值**：Schema 允許 `null` 的欄位保持 `null`，不以 `0`、空字串或 `false` 代替未知。
- **資料模式**：`DataMode` 的 `mock` 值僅供測試與相容，正式入口不得選用。

### 取消與生命週期

使用者取消、改目的地、撤回同意、離開頁面、進入背景或觸發 SOS 時，相關計時器、音訊與延遲的非同步結果都必須失效並清理，不能回傳過期的成功結果。

## 技術框架

| 類別 | 技術 | 用途 |
|---|---|---|
| 應用框架 | Flutter 3.47.6、Dart 3.13.5（以 [.fvmrc](.fvmrc) 固定） | 單一程式碼支援 Android、iOS 與 Web |
| 基底 App | TownPass Flutter（臺北市政府，GPLv3） | 官方殼、登入、路由、主題與既有服務 |
| 狀態與路由 | GetX（`get`） | 官方 App 的路由與頁面狀態 |
| 地圖與路線 | `flutter_map`、`latlong2`、OpenStreetMap 圖磚、Valhalla `pedestrian`／`exclude_polygons`／`use_lit`、OSRM 備援、`RouteFollower` | App 內步行路線、產品緩衝避讓、夜間照明偏好及前景偏離重規劃；[日夜與自動規劃](#日夜照明與自動路線規劃)依下表說明 |
| 定位與感測 | `geolocator`、`sensors_plus` | 使用者主動觸發的定位與裝置感測 |
| 據點與犯罪參考資料 | OSM Overpass API（便利商店，ODbL）；臺北市統計資料庫月別暴力犯罪 CSV；Supabase 唯讀查詢（RPC，僅使用公開金鑰） | 附近據點與歷史統計參考；不是即時路段風險 |
| 語音與音訊 | `flutter_tts`（裝置 TTS）、`audioplayers`（模擬陪伴鈴聲，屬 Level B 依賴） | 模擬陪伴語音與提示音 |
| 本機儲存 | `shared_preferences` | 使用者設定的「家」，只存在裝置上 |
| 資料契約 | JSON Schema（`schemas/`）、`json_serializable`、`build_runner` | 單一來源的 payload 契約與生成的 Dart Model |
| 測試與 CI | `flutter_test`、`flutter analyze`、GitHub Actions（`safe_walk.yml`、`build.yml`、`demo_database_ci.yml`）、Codemagic（iOS） | 單元與 Widget 測試、契約一致性檢查與建置 |

官方 TownPass 原有的 WebView、通知、掃碼、圖片選取等能力沿用其既有套件，本專案不另外改寫。

## 近期應用技術

以下依 2026-11-08 GitHub `main` 近期已合併功能整理，核對版本為 [`1e89dfe`](https://github.com/csfishy/taipei-safe-walk-townpass/commit/1e89dfef47bb723f23743ddda571c2b6f9360c4c)。本節記錄合併程式的技術應用；遠端部署、已安裝 App 與實機驗收須分別核對對應版本。

| 功能／PR | 應用技術 | 實際用途 |
|---|---|---|
| 設定頁與首頁版面（[#87](https://github.com/csfishy/taipei-safe-walk-townpass/pull/87)） | Flutter Widgets、`TPAppBar`／`TPColors`、`MediaQuery.textScalerOf`、`Expanded`／`SingleChildScrollView` | 以既有 TownPass 元件建立安心行設定頁，集中家的位置與協助者設定；首頁一般字級固定版面，大字級時切換可捲動內容，並處理儲存後與系統返回的頁面狀態 |
| 地圖回報「已排除」（[#89](https://github.com/csfishy/taipei-safe-walk-townpass/pull/89)） | Supabase RPC、PostgreSQL 交易與 advisory lock、UUID、JSON 回應驗證 | `safe_walk_map_report_resolve` 只處理選定的回報 UUID；App 核對 `reportId`／`removed` 回應後才移除標示並更新避讓。伺服器保存已排除 UUID／時間以阻止舊提交重建，支援冪等重試；失敗保留標示與重試入口 |
| 日夜判斷與夜間路燈偏好（[#88](https://github.com/csfishy/taipei-safe-walk-townpass/pull/88)） | Dart `dart:math`、NOAA／Meeus 太陽位置演算、開源 Valhalla `pedestrian` costing、OpenStreetMap `lit` 標記 | 依起點經緯度與請求當下時間在本機計算太陽高度，以 −0.833° 為日夜門檻；夜間的最短、15 公尺與 50 公尺避讓請求均帶 `costing_options.pedestrian.use_lit = 1.0`，並在路線警示揭露偏好是否套用 |
| 犯罪資料來源與授權（[#90](https://github.com/csfishy/taipei-safe-walk-townpass/pull/90)） | Flutter `SwDataSource` 資料來源模型、來源／授權 URL、中繼資料揭露 | 在 App 的來源卡片明列犯罪快照 10 個資源採用[政府資料開放授權條款－第 1 版](https://data.gov.tw/license)；移除當時卡片中缺少完整來源資訊的參考圖資項目。離線定位使用的圖資與開源套件另見[犯罪資料定位流程](#犯罪資料定位流程與開源技術) |
| 守護區區域警報（[#79](https://github.com/csfishy/taipei-safe-walk-townpass/pull/79)） | PostGIS `geography(Point,4326)`／GiST／`ST_DWithin`、Supabase Auth、PostgreSQL 受限 RPC／RLS、Flutter 前景輪詢 | 儲存本人守護區，依 SOS 事件位置選出符合區域或即時距離的協助者，伺服器與 App 分別去重；設定、接收及限制見[守護區說明](#守護區的區域警報) |
| 緊急聯絡人配對與通知（[#91](https://github.com/csfishy/taipei-safe-walk-townpass/pull/91)） | Supabase Auth 匿名 session、`auth.uid()`、私有資料表與 RLS、PostgreSQL／`pgcrypto`、受限 RPC、`shared_preferences`、前景輪詢與生命週期控制 | 以隨機 8 碼、24 小時有效的一次性邀請碼建立聯絡人關係，資料庫只存 SHA-256 雜湊；RPC 處理配對、撤銷與嘗試次數限制。SOS 將聯絡人納入不受距離限制的收件人，前景每 10 秒輪詢並顯示 App 內橫幅；啟動時只還原既有身分，聯絡人不必上傳位置 |

### 日夜、照明與自動路線規劃

以下依 [main `13ccee1`](https://github.com/csfishy/taipei-safe-walk-townpass/commit/13ccee1063ac5781a0ce3b50247fb163aaae43a9) 的路線程式盤點，記錄日夜判斷、夜間照明與前景自動規劃的技術及實作狀態。

| 情境／能力 | 狀態 | 技術與目前行為 |
|---|---|---|
| 自動規劃與偏離後改道 | 已接線，待實機驗收 | 開啟地圖、變更起點／目的地或回報點變動時觸發路線規劃。Valhalla `pedestrian` 配合 `exclude_polygons` 產生一般與避讓候選，並核對回傳路線與緩衝距離；前景 GPS 與 `RouteFollower` 偵測所有候選皆偏離時重新規劃，偏離觸發的自動重規劃間隔至少 15 秒 |
| 黑夜判斷 | 已實作 | Dart 在本機依起點經緯度、請求當下時間與 NOAA／Meeus 太陽位置演算判斷日夜；太陽高度低於 −0.833° 視為夜間，每次規劃重新判斷 |
| 夜間照明偏好 | 已接線，待實機驗收 | 夜間 Valhalla 請求帶 `costing_options.pedestrian.use_lit = 1.0`，優先考量 OSM `lit` 路段標記；目前未使用官方路燈點位或實測照度排序，不保證沿途實際有燈 |

首頁的時間情境卡依本機 18:00–06:00 顯示夜間提醒；路線規劃另用上述太陽高度判斷，兩者目前不同。自動規劃只在上述操作與前景導航條件下觸發，沒有背景持續追蹤；OSRM 備援會揭露未套用避讓與照明偏好。

程式依據：[路線情境偏好](https://github.com/csfishy/taipei-safe-walk-townpass/blob/13ccee1063ac5781a0ce3b50247fb163aaae43a9/lib/features/safe_walk/navigation/route_preference.dart)、[自動規劃與導航生命週期](https://github.com/csfishy/taipei-safe-walk-townpass/blob/13ccee1063ac5781a0ce3b50247fb163aaae43a9/lib/features/safe_walk/platform/integration/safe_walk_composition_root.dart)、[地圖操作與重新規劃](https://github.com/csfishy/taipei-safe-walk-townpass/blob/13ccee1063ac5781a0ce3b50247fb163aaae43a9/lib/features/safe_walk/presentation/safe_walk_flow.dart)。

### 守護區的區域警報

守護區讓協助者指定願意接收 SOS 的地點；後端依事件位置決定收件對象。這是 SOS 的區域通知條件，使用者進出該區域本身不會觸發警報。以下依 [main `13ccee1`](https://github.com/csfishy/taipei-safe-walk-townpass/commit/13ccee1063ac5781a0ce3b50247fb163aaae43a9) 的實作整理。

| 項目 | 功能與規則 | 應用技術 |
|---|---|---|
| 設定與管理 | 主動加入協助者後，從「安心行設定 → 附近協助者」管理最多 3 個圓形守護區；App 可選半徑 500 或 1,000 公尺，確認後才取得目前位置建立。伺服器將中心經緯度四捨五入至小數第 3 位（約 100 公尺量級） | Flutter 設定卡片、`NearbyHelperAreas` 能力介面、`nearby_helper_set_areas`／`nearby_helper_get_areas` RPC；設定 RPC 含 10 秒限流檢查 |
| 區域命中與收件人 | SOS 發生時，合併「500 公尺內且即時位置未過期」與「守護區涵蓋事件位置」的協助者，排除發送者、依協助者 ID 去重並按距離取最多 50 位；配對聯絡人另計，重複對象只投遞一次 | PostGIS `geography(Point,4326)`、GiST 空間索引、`ST_DWithin` 距離判斷，搭配 PostgreSQL 條件合併／分組、唯一鍵與 `ON CONFLICT` |
| 通知接收 | App 在前景每 10 秒查詢寄給本人的 SOS，以 `alertId` 去重並顯示橫幅。SOS 有效 30 分鐘；在有效期內恢復前景可讀取仍有效的通知 | `nearby_sos_send`／`nearby_helper_fetch_alerts` RPC、`NearbyHelperController`、App 生命週期與輪詢控制 |
| 身分與存取 | 以 Supabase Auth session 的 `auth.uid()` 決定本人，不接受客戶端自報身分；守護區只由本人管理，client 不可直接讀取資料表 | 匿名 Auth／JWT、私有 schema、RLS、撤銷直接表權限及僅授 `authenticated` 的受限 RPC |
| 保留與退出 | 即時位置只保留最新一筆，有效期 10 分鐘，前景約每 4 分鐘更新；守護區不隨該位置時效消失，可單獨移除，退出協助或刪除帳號時一併清除 | 伺服器有效期檢查、本人區域更新 RPC、退出清除與外鍵級聯刪除 |

目前採 **App 內通知**，尚無 FCM／APNs 背景推播；在背景或關閉 App 時不主動提醒。匿名身分不等於協助者資格審核，伺服器也無法證明守護區中心就是協助者所在位置。截至上述版本，後端仍待 PostGIS 執行驗證、受審查的前向 migration、資格／防濫用與雙裝置驗收，整體維持 **BLOCKED**；程式已合併不代表已部署或完成實機驗收。

實作依據：[守護區設計與限制](https://github.com/csfishy/taipei-safe-walk-townpass/blob/13ccee1063ac5781a0ce3b50247fb163aaae43a9/docs/SAFE_WALK_NEARBY_HELPER_DESIGN.md#L128)、[PostGIS 與 RPC](https://github.com/csfishy/taipei-safe-walk-townpass/blob/13ccee1063ac5781a0ce3b50247fb163aaae43a9/supabase/nearby_helper/001_nearby_helper.sql)、[前景接收控制器](https://github.com/csfishy/taipei-safe-walk-townpass/blob/13ccee1063ac5781a0ce3b50247fb163aaae43a9/lib/features/safe_walk/platform/integration/nearby_helper_controller.dart)。

上述應用的限制：

- **路燈是路線偏好**：`use_lit` 依 OSM 標記計算，不保證實際照明。OSRM 備援與據點路線亦揭露未套用。演算法與參數說明見 [NOAA 太陽計算依據](https://gml.noaa.gov/grad/solcalc/calcdetails.html)、[Valhalla 步行參數](https://valhalla.github.io/valhalla/api/route/api-reference/#pedestrian-costing-options)。
- **通知採 App 內輪詢**：尚未實作 FCM／APNs 背景推播；App 在背景或關閉時不主動通知。匿名 session 與邀請碼配對不等於協助者資格審核；refresh token 目前存在 App 偏好設定，尚非加密安全儲存。截至上述合併版本，聯絡人後端仍待 PostGIS 執行驗證、受審查的前向 migration 與雙裝置驗收，附近通知維持該版本的 BLOCKED 狀態。技術依據見 [#91 安全與驗收紀錄](https://github.com/csfishy/taipei-safe-walk-townpass/pull/91)。
- **回報排除是社群操作**：以後端確認為準，不表示官方認定事件已解除；失敗、取消與遲到回應不以畫面假成功代替資料確認。回報功能與持久犯罪參考資料分開。

## 資料、隱私與安全原則

- **位置由使用者主動觸發**：只在使用者明確操作（如開始導航、更新位置）時透過 TownPass 原生定位服務取得；進入頁面不會自動取位置，也不建立第二個 GPS 監聽。
- **兩道同意分開**：系統定位權限與「把座標傳給第三方路線或據點服務」的同意分開。未同意不傳送；撤回後取消進行中的查詢並忽略遲到的回應。
- **不補假資料**：定位失敗、路線失敗或查無資料時，回報 Unavailable 與原因，不以示範座標、示範路線或示範據點代替。
- **統計不等於即時安全**：行政區或全市歷史統計不能直接視為即時路段安全分數；路線結果也不代表已驗證的安全路線，不保證治安、照明或無障礙條件。
- **避讓緩衝不是犯罪邊界**：50 公尺避讓緩衝是產品設定，不是官方確認的犯罪區域、精確案發位置或安全保證。
- **求助不等於受理**：開啟撥號器不代表電話已接通；開啟通報管道不代表已受理或派遣。`officialReceipt` 恆為 `null`，不偽造受理編號。
- **附近通知暫停**：在可信身分、權限、防濫用、資料保留與刪除機制完成並驗證前，附近協助者通知維持 BLOCKED；匿名 UUID 不能作為身分或授權。
- **陪伴不是真人**：模擬陪伴不要求麥克風、不錄音，也不冒充真人、警察或已派遣的人員。
- **敏感資料不進版控**：不提交 secrets、憑證、Token、真實位置紀錄、住家或聯絡人資料；App 不持有 `service_role`、管理金鑰或資料庫密碼。
- **犯罪參考資料隔離**：北北基犯罪參考資料位於持久 Supabase 資料，與 CI 及 Demo 重設隔離，build 與測試不得 import、seed、更新或刪除它。本機離線備份須放在所有 Git checkout 之外。

### 犯罪資料定位流程與開源技術

犯罪 JSON 的地點文字先經地址正規化，再比對官方參考圖資，最後將門牌平面座標轉成經緯度。這是 App 外的離線資料前處理流程；下載官方資料後，地址比對與座標轉換均在本機完成。

| 階段 | 技術／資料 | 用途 |
|---|---|---|
| 讀取與整理 | Python 3.13 標準函式庫（`json`、`csv`、`re`、`unicodedata`、`math` 等）與自行撰寫的比對規則 | 解析 JSON／CSV，統一全半形、臺／台及中文數字，按城市、行政區、道路、段、巷弄與門牌範圍比對 |
| 地點參考 | [臺北市門牌位置數值資料](https://data.taipei/dataset/detail?id=b7c8e724-1e98-45ee-a0bd-f3840623ed97)、[新北市門牌位置數值資料](https://data.ntpc.gov.tw/datasets/d7b568ab-3819-40c8-a6e7-a6b199443101)、[臺北捷運車站出入口座標](https://data.taipei/dataset/detail?id=cfa4778c-62c1-497b-b704-756231de348b) | 使用政府開放資料離線比對，選取實際公布的門牌／出入口參考點；資料採政府資料開放授權條款第 1 版 |
| 座標轉換 | Dart 與開源套件 [proj4dart 3.0.0](https://pub.dev/packages/proj4dart/versions/3.0.0)（[MIT 授權](https://pub.dev/packages/proj4dart/versions/3.0.0/license)） | 將 TWD97／TM2 121（EPSG:3826）平面座標轉為 WGS84（EPSG:4326）經緯度；GeoJSON 順序為 `[longitude, latitude]` |

新北門牌欄位 `x_3826`／`y_3826` 明示座標系統；臺北門牌原始檔未明列 CRS，本次依政府地址標準與獨立官方地址交叉核對後推定 EPSG:3826。輸出保留來源、版本／日期、比對方法與精度限制；**參考座標不是精確案發點**，無法可靠比對時保留 `null`，不以行政區中心補值。詳細定位語意與資料保存規則見 [犯罪參考資料文件](docs/SAFE_WALK_CRIME_DATABASE.md#地點與座標語意)。

## 測試與驗證

依改動範圍執行下列命令。**未執行、失敗或跳過的項目不能寫成 PASS。**

```bash
# 安心行與工具的嚴格分析（門檻）
flutter analyze --no-pub lib/features/safe_walk tool test/features/safe_walk

# 全專案分析：允許既有 style info，error／warning 仍會失敗
flutter analyze --no-pub --no-fatal-infos

# 完整測試
flutter test --no-pub --reporter expanded

# Chrome 啟動測試（需要 Chrome）
flutter test --no-pub --platform chrome test/web_startup_test.dart --reporter expanded

# Schema 與生成產物一致性
dart run tool/generate_safe_walk_contracts.dart --check

# Python 工具測試
python3 -m unittest discover -s tool -p 'test_*crime*.py' -v
python3 -m unittest discover -s tool -p 'test_*release*.py' -v

# 示範資料庫腳本測試（需先安裝 scripts/requirements-db-test.txt）
python3 -m unittest discover -s scripts/tests -v
```

補充說明：

- 全專案分析包含上游 TownPass 既有的診斷。Safe Walk CI 會保存完整分析報告；不能把安心行範圍的通過寫成「整個 App 沒有任何分析問題」。
- `test/web_startup_test.dart` 會替換裝置資訊的 plugin 邊界，驗證瀏覽器分支；它不等於已驗證真實裝置或原生功能。
- 單元與整合測試使用 Fake、Mock 與 fixtures，只證明契約與邊界，不等於真實 Provider 或實機驗收。
- 真實 Provider smoke test 需要明確開啟（如 `SAFE_WALK_LIVE=1`），且可能因外部服務狀態而失敗；通過單次 smoke 不代表完整功能驗收。

## CI、預覽版與網站

| 工作流 | 觸發 | 內容 |
|---|---|---|
| [Safe Walk CI](.github/workflows/safe_walk.yml) | PR、`main`／`migration/**` push、手動執行 | Schema 一致性、模組與工具分析、完整測試、原始診斷報告；可手動選擇 Android debug build |
| [check-and-build](.github/workflows/build.yml) | PR、`main` push、`v*-pre.*` tag、手動執行 | 檢查後建置 Android APK、unsigned iOS IPA、Web 預覽產物 |
| [demo_database_ci.yml](.github/workflows/demo_database_ci.yml) | 可重用工作流，由上面兩份工作流呼叫 | 在 runner 上以本機 PostGIS 初始化並測試隔離的示範資料庫，PR 永不連遠端 Demo |

### 預覽版

- 每次 **push 到 `main`**，且檢查與三平台建置通過、示範資料庫條件符合（見下文）後，會自動發布 GitHub prerelease，版本格式例如 `v0.0.12-pre.r0000000042.g31cb0ac12345`。
- 符合 `pubspec.yaml` 版本的手動預發佈 tag（`v*-pre.*`）也會發布。**不要覆寫已發布的 tag。**
- PR 與手動執行只保留可下載的 artifacts，不建立 Release。
- 預覽版使用獨立身分 `Town Pass Preview`／`io.github.csfishy.taipeisafewalktownpass.preview`，**不是正式市政服務發行版**。Android APK 使用測試金鑰簽署；unsigned IPA 沒有簽章，不能直接安裝或當作 TestFlight 版本。
- 詳細安裝限制見 [預發佈說明](docs/PRERELEASE-NOTES.md)。

### GitHub Pages

Web 版預設部署至 `https://csfishy.github.io/taipei-safe-walk-townpass/`。這只是**部署目標**：只有 Pages 來源已設為 **GitHub Actions**、環境規則允許，且部署成功後，網站才算上線。Release 下載檔不是網站部署證明。

### Demo 資料庫重設

遠端示範資料庫的重設由 Repository Actions Variable `DEMO_DATABASE_RESET_ENABLED` 控制：未設定或值為 `false` 時，遠端 job 會跳過並在 Summary 明示；只有精確值 `true` 才會啟用。設定與審查要求見 [資料庫重設](docs/SAFE_WALK_DATABASE_RESET.md)。

## 建置

以下命令需先完成 [安裝依賴與產生檔案](#安裝依賴與產生檔案)：

```bash
flutter build apk --release --no-pub
flutter build ios --release --no-codesign --no-pub --build-name 0.0.12 --build-number 1
flutter build web --release --no-pub --base-href /taipei-safe-walk-townpass/ --no-web-resources-cdn
```

- `--build-name` 使用 `pubspec.yaml` 版本的純數字部分（目前為 `0.0.12`），升版時需同步調整。
- iOS 建置需要 macOS 與 Xcode；Windows 無法本機編譯 iOS。
- 列出命令不代表已完成建置。實際產物與結果以對應 CI run 為準。

## 協作流程

1. **開工前**：`git fetch origin`，確認最新 `origin/main`、開放中的 PR、CI 狀態與工作樹，避免覆寫他人成果。
2. **分支**：一般功能使用短期分支（例如 `feat/…`、`fix/…`、`docs/…`）。依賴未合併成果時，使用 stacked PR，並在描述中明列 parent 與 head SHA。
3. **審查層級**：
   - **Level A**：一般功能、UI callback、導航邏輯、資料轉換、音訊與測試。通過相關測試與必要 CI 後，由一位具權限、非作者的隊員審查。
   - **Level B**：共用 Schema／Contracts／Models、依賴與 lockfile、TownPass route、原生設定、重大 UI、CI 與重大架構。合併前需對應主要負責人確認。
   - **Level C**：真實外部作用，例如警消發送、附近協助者通知、Supabase 身分／RPC／RLS、敏感位置儲存、正式部署與 Live 開關。需隊長明確授權與安全、隱私審查。
4. **PR 內容**需包含：完成的使用者功能與完成定義、主要檔案與影響模組、契約變更（沒有則寫無）、審查層級、實際執行的命令與結果、未驗證項目、外部或裝置依賴，以及對 Live 可用性與安全狀態的影響。
5. **禁止事項**：不 force push、不直接推送 `main`、不刪除或重設他人分支、不移動已發布的 tag、不寫入官方 upstream、不以未驗證結果宣稱完成。

完整規則見 [AGENTS.md](AGENTS.md) 與 [開放式平行協作](docs/SAFE_WALK_COLLABORATION.md)。

## 文件索引

| 文件 | 用途 |
|---|---|
| [AGENTS.md](AGENTS.md) | 協作規則、修改範圍、資料與 Git 規則 |
| [LIVE-FIRST 完成定義](docs/SAFE_WALK_LIVE_FIRST.md) | 正式入口只用 Live、Unavailable 的定義與驗收證據 |
| [Live MVP](docs/SAFE_WALK_LIVE_MVP.md) | 正式功能驗收規格，含 50 公尺避讓規格 |
| [Live Readiness](docs/SAFE_WALK_LIVE_READINESS.md) | 逐能力現況、接線缺口、測試與實機證據 |
| [Live 接線盤點](docs/SAFE_WALK_LIVE_WIRING_AUDIT.md) | 正式入口的程式接線盤點 |
| [Live 計畫](docs/SAFE_WALK_LIVE_PLAN.md) | P0–P2 工程計畫與分工 |
| [規格逐項審查](docs/SAFE_WALK_SPEC_AUDIT.md) | 規格與程式的對照審查 |
| [架構](docs/SAFE_WALK_ARCHITECTURE.md) | 官方接點、模組邊界與整合方向 |
| [模組契約](docs/SAFE_WALK_MODULES.md) | 各模組的輸入、輸出、狀態與交付 |
| [導航與呈現契約](docs/SAFE_WALK_NAVIGATION_PRESENTATION_CONTRACT.md) | 導航、同意、路線與 UI 的接線契約 |
| [開放式平行協作](docs/SAFE_WALK_COLLABORATION.md) | 跨模組開發、審查層級與 PR 流程 |
| [Schema 與 Dart 模型](docs/SAFE_WALK_SCHEMA.md) | 單一來源、strict 欄位、nullable 與取消語意 |
| [顏色規範](docs/SAFE_WALK_COLOR_SPEC.md) | 沿用官方 TPColors 的語意與對比 |
| [Safe Walk CI](docs/SAFE_WALK_CI.md) | CI 門檻、完整分析報告與選用建置 |
| [建置與部署](docs/BUILDS.md) | 預覽版、tag、Pages 與平台工具 |
| [預發佈說明](docs/PRERELEASE-NOTES.md) | 預覽版的下載、安裝與限制 |
| [犯罪參考資料庫](docs/SAFE_WALK_CRIME_DATABASE.md) | 持久資料、地點語意與隔離規則 |
| [Supabase 設定](docs/SAFE_WALK_SUPABASE.md) | 連線設定與目前限制 |
| [資料庫重設](docs/SAFE_WALK_DATABASE_RESET.md) | 示範資料庫重設的啟用條件與審查 |
| [附近通知安全狀態](docs/SAFE_WALK_NEARBY_SECURITY.md) | 附近通知的 BLOCKED 原因與重新啟用條件 |
| [整合歷史](docs/SAFE_WALK_INTEGRATION.md) | 既有接線與 Live 交接的歷史紀錄 |
| [初始化驗證紀錄](docs/SAFE_WALK_INITIALIZATION.md) | 初始化當時的驗證證據（歷史） |
| [競賽與授權待確認](docs/SAFE_WALK_COMPETITION_LICENSE.md) | 交件形式、AGPL 要求與待確認事項 |
| [來源紀錄](docs/SAFE_WALK_UPSTREAM.json) | 官方 base commit 與來源追溯 |
| [知識圖譜報告](docs/knowledge-graph/GRAPH_REPORT.md) | 專案知識圖譜的摘要 |

## 官方來源與授權

本專案基於臺北市政府資訊局的 [taipei-doit/TownPass](https://github.com/taipei-doit/TownPass)，保留上游 Git 歷史、來源紀錄與原 [GNU GPLv3 LICENSE](LICENSE)。官方技術文件見 [TownPass 文件](https://townpass.taipei/en/docs/)。

- 本 README 與本專案並未重新授權上游程式。
- 競賽對團隊成果的 AGPL 要求，以及上游 GPL 部分的保留與最終交件方式，仍在確認中，詳見 [競賽與授權待確認](docs/SAFE_WALK_COMPETITION_LICENSE.md)。
- Repository 為 Public 不代表授權相容性或競賽資格審查已完成。

## 免責聲明

- 臺北安心行是競賽開發中的作品，**不是官方服務**，不提供緊急救援，也不保證路線、資料或求助功能在任何情況下可用。
- 遇到危險或緊急狀況，請直接撥打 110 或 119，或使用官方求助管道。
- 測試時請勿撥打真實緊急電話，也不要送出真實通報。
- 路線與統計資料僅供參考，不代表路段安全或治安保證。

## 致謝

- **臺北市政府資訊局** 與 TownPass 團隊，提供開源的官方 Flutter App 基底。
- **OpenStreetMap** 貢獻者，提供地圖圖磚與店家資料；使用時須遵守 OSM 的來源標示與使用條款。
- **OSRM** 專案，提供步行路線引擎。公開示範伺服器屬 fair-use，無服務水準保證。
- **臺北市政府** 開放資料平台（data.taipei）與主計處，提供全市月別暴力犯罪統計資料。
- 2026 臺北城市通微服務黑客松的主辦與協辦單位。
- 五位開發成員：小魚、Steven、莅紋、信義、奶爸。
