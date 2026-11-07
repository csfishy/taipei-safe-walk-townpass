# 臺北安心行 · Taipei Safe Walk

以官方 TownPass Flutter App 為基底的五人協作專案，參與「2026 臺北城市通微服務黑客松」。現行政策為 **LIVE-FIRST DEVELOPMENT + NO PRODUCTION MOCK**：直接交付真實、可操作、可驗證的完整 Live 使用者流程，不要求先做 Demo／Mock。Fake／Mock／fixtures 僅供隔離測試，不能進入正式入口。統一完成定義見 [LIVE-FIRST](docs/SAFE_WALK_LIVE_FIRST.md) 與 [Live MVP](docs/SAFE_WALK_LIVE_MVP.md)。

- **Repository**：[csfishy/taipei-safe-walk-townpass](https://github.com/csfishy/taipei-safe-walk-townpass)；Public，預設分支 `main`。
- **開發基線**：Flutter **3.47.6**／Dart **3.13.5**，依 [.fvmrc](.fvmrc) 與已提交的 [pubspec.lock](pubspec.lock)；同一個 Flutter App，採 Feature-First／Soft Ownership／Contract-Based Integration。
- **盤點基線**：main `7b99fea`（#49 恢復 `3c433001` 快照後）。已有 OSRM、OSM 圖磚／店家查詢、RouteFollower、全市歷史犯罪 Repository、裝置 TTS 與 Supabase 連線基礎；正式入口仍固定 Mock，是必須修正的缺口。#35 的 Live 接線目前不在 main；#44 的持久犯罪資料保護另經審查；#55 的唯讀 Repository／RPC SQL 已合併，但尚未接正式流程或證明遠端驗收。詳見 [Readiness](docs/SAFE_WALK_LIVE_READINESS.md)；CI 成功不等於實機或完整 Live 驗收。

## 在 TownPass 開啟安心行

從 TownPass **首頁新聞上方的「臺北安心行」功能卡片**進入，卡片包含圖示、說明與向右箭頭，排列方式參考 TownPass-self。也可從「城市服務」的釘選項目開啟；兩處進入同一個原生功能頁，返回回到原本的 TownPass 畫面。

上述基線的導航／據點／求助仍會走示範流程，**不符合目前 LIVE-FIRST 完成定義**；文件 PR 不會把它改標成 Live 完成，接線修正另以程式 PR 交付。正式路徑必須使用真定位、真路線、可信資料；未配置／失敗顯示 Unavailable、阻塞原因與下一步，不切換 Mock。進入功能不應自動取 GPS、播放、撥號或傳送簡訊。陪伴情境雖為模擬，聲音須由真裝置 TTS／核准音訊播放；沒有引擎時明示語音不可用與文字預覽，不假稱通話接通。舊接線證據見 [整合歷史](docs/SAFE_WALK_INTEGRATION.md)。

## Clone 與五人分工

每位工程師使用自己的 clone。讀取 Public Repository 不需共用帳號；推送仍需自己的 GitHub 帳號及寫入權限。

```sh
git clone --branch main https://github.com/csfishy/taipei-safe-walk-townpass.git
cd taipei-safe-walk-townpass
git fetch origin
```

五個模組分支仍保留供歷史與同步，但新任務優先從最新 main 建短期功能分支，依賴未合併成果時使用明列 parent 的 stacked PR。任何成員都能跨 M1–M5 修改功能及測試，不以資料夾分割完整操作流程。

| 技術分區／主要負責人 | 主要諮詢範圍（不是獨占修改權） |
|---|---|
| M1 小魚 | platform／shared、平台定位入口、composition、套件、route、原生設定及 CI |
| M2 Steven | navigation、OSRM、RouteFollower、目的地及據點路線 |
| M3 莅紋 | presentation、正式 UI/UX 設計方向與重大改版 |
| M4 信義 | safety_data、來源、Parser、Repository 與資料品質 |
| M5 奶爸 | companion、本機 TTS／音訊、清理及中斷 |

功能主責可自行完成 GPS→OSRM→地圖等端到端接線。修改前說明目的、檔案、影響模組及原主責，同檔案並行時直接協調實作者，不強制所有普通修改先等小魚批准或代工。

Level A 一般功能／UI callback／測試，一位具權限非作者隊員 Review；Level B 共用 Schema／Contracts／Models、依賴／route／原生／CI 及重大 UI，任何人可開發、合併前對應主責確認；Level C 真實外部作用、位置通知、Supabase 權限、敏感位置及正式開關，需隊長授權與安全／隱私驗收。預設經 PR／必要 CI，不直接推 main。

程式架構仍以共用型別及依賴注入整合，業務模組不直接 import 其他模組實作，具體組合限 platform/integration/；這限制依賴，不限制作者。完整規則、功能工作包與檔案／審查協調見 [開放式平行協作](docs/SAFE_WALK_COLLABORATION.md) 與 [模組契約](docs/SAFE_WALK_MODULES.md)。

## 首次安裝與產生檔案

需要 Git、真正可執行的 **Python 3**、指定版本的 Flutter／Dart；Chrome 測試與 Web 開發另需安裝 Chrome。可使用 FVM 管理 [.fvmrc](.fvmrc)：先執行 `fvm install`，並將以下 `flutter`／`dart` 指令分別改用 `fvm flutter`／`fvm dart`。不要以套件 upgrade 或重建 lockfile 排除版本差異。

更新 main／模組分支後，在 Repository 根目錄依序執行。**先產生 metadata，再執行 pub get**：

```sh
flutter --version
dart --version
python3 tool/release_metadata.py
flutter pub get --enforce-lockfile
dart run build_runner build
dart run tool/generate_safe_walk_contracts.dart --check
dart run tool/check_safe_walk_baseline.dart
```

`release_metadata.py` 會產生 `assets/build-info.json`，內容包含版本、build number、source commit 與 Flutter 版本。metadata 與官方 Dart／asset binding 產物依專案設定產生，不手改；Schema 產物則需與版控來源保持一致。

### Windows 的 Python 3

Windows 請使用真正的 Python 3 解譯器；若已安裝 Windows Python，可將 metadata 指令改為 `py -3 tool/release_metadata.py`，或以已安裝的 `python.exe` 執行。不要把 Windows Store 的 Python 執行別名誤當成可用解譯器。WSL 是選項，並非必要條件；若已安裝 WSL、Linux Python 3 與 Git，可在這份 clone 根目錄使用：

```powershell
wsl python3 tool/release_metadata.py
```

WSL 內需可讀取這份 clone 並執行 Git；本文不假設本機已有 WSL。其餘 Flutter 指令使用已安裝的對應平台 SDK。

## 分析、測試與啟動

完成上方產生流程後執行：

```sh
flutter analyze --no-pub lib/features/safe_walk tool test/features/safe_walk
flutter analyze --no-pub --no-fatal-infos
flutter test --no-pub --reporter expanded
flutter test --no-pub --platform chrome test/web_startup_test.dart --reporter expanded
flutter devices
flutter run -d chrome
```

第一個分析命令檢查安心行、新工具與模組測試，採嚴格門檻。全專案分析的 `--no-fatal-infos` 允許既有 style info，error／warning 仍會失敗；如需查看包含 fatal infos 的原始診斷，可另外執行 `flutter analyze --no-pub`。Safe Walk CI 另保存完整分析報告，不能將 scoped 檢查成功寫成整個 TownPass 都無診斷。

Chrome guard 測試明確替換裝置資訊 plugin 邊界，仍檢查真正服務的瀏覽器分支；它不等於已驗證真實裝置資訊或原生功能。

Android／iOS 開發使用 `flutter run -d 裝置ID`，先安裝對應 SDK、模擬器或準備實機。Android 預覽 CI 使用 JDK 21 與 Repository 的 Android SDK 設定；iOS 使用 macOS 15／Xcode 26.1.1，以符合鎖定的裝置資訊套件需求。Windows 不能本機編譯 iOS。不要用真實緊急電話、官方登入或通報流程做初始化測試。

## CI、預覽包與網站

兩份工作流的 runner 本機 PostGIS 初始化、雙重重設與安全測試均為必要檢查；PR 永不連遠端 Demo。專用 Demo 重設另由 **Repository Actions Variable `DEMO_DATABASE_RESET_ENABLED`** 明確啟用：未設定或值為 `false` 時，遠端 job 跳過，既有 main prerelease／Pages 可在全部建置及檢查成功後繼續，Summary 明示未重設，不能宣稱 Demo 已就緒。只有精確值 `true` 才啟用單一遠端 reset job；啟用後缺白名單、Secrets、marker／受限角色，或重設失敗、取消、非預期跳過，都會阻擋相關發布／部署。其他旗標值視為配置錯誤，不自動放行。設定與 Level C 審查見 [資料庫重設](docs/SAFE_WALK_DATABASE_RESET.md)。

[PR #47](https://github.com/csfishy/taipei-safe-walk-townpass/pull/47) 已合併至 main `752dd96`：遠端 Demo 改為完成配置／驗收後明確啟用；未啟用時保留必要隔離 CI，既有發布可繼續。文件政策與新功能開發不應重新啟用任何遠端 reset。

下列兩份工作流均已在 main；執行規則與實際結果分開看，預覽產物、Release 與 Pages 以對應 run 為準：

| 工作流 | 觸發與用途 |
|---|---|
| [Safe Walk CI](https://github.com/csfishy/taipei-safe-walk-townpass/actions/workflows/safe_walk.yml) | PR、main／migration push、手動執行；Schema 一致性、模組／工具分析、完整測試與原始診斷報告；可手動選擇 Android debug build |
| [check-and-build](https://github.com/csfishy/taipei-safe-walk-townpass/actions/workflows/build.yml) | PR、main push、`v*-pre.*` tag、手動執行；檢查後產生 Android APK／unsigned iOS IPA／Web 預覽產物 |

每次 **push 到 main**，檢查及三平台建置全部通過，且上方 Demo gate 已符合後，會自動發布 GitHub prerelease，版本包含 run number 與 commit，例如 `v0.0.12-pre.r0000000042.g31cb0ac12345`；`r` 後的十位數補零，讓 GitHub Releases 清單按新舊正確排序，原生 build number 仍為整數。一次推送多個 commits 時只建置最後一個。符合 pubspec 版本的手動預發佈 tag 仍支援發布且不重設共享 Demo。PR／manual run 不建立 Release；main 手動執行在旗標啟用時也須完成重設，Pages 仍依既有設定及最新來源檢查。不要覆寫已發布 tag。完整規則見 [建置與部署](docs/BUILDS.md)。

本機可在完成相同 metadata／pub get／generation 後建置；以下 iOS 範例的純數字版本對應目前 pubspec：

```sh
flutter build apk --release --no-pub
flutter build ios --release --no-codesign --no-pub --build-name 0.0.12 --build-number 1
flutter build web --release --no-pub --base-href /taipei-safe-walk-townpass/ --no-web-resources-cdn
```

iOS `--build-name` 使用 pubspec 版本的純數字部分，升版時需同步調整。這些命令需要對應平台工具；列出命令不是已完成建置的證明。預覽使用獨立身份 `Town Pass Preview`／`io.github.csfishy.taipeisafewalktownpass.preview`，不是正式市政服務發行版。Android APK 使用測試金鑰；unsigned IPA 沒有 provisioning profile／簽章，不能直接安裝或當作 TestFlight 版本，仍需適當簽署。下載與安裝限制見 [預發佈說明](docs/PRERELEASE-NOTES.md)。

GitHub Pages 僅從最新 main 部署：必要資料庫測試、分析及 Web／Android／iOS 三個建置成功，上方 Demo gate 已符合，且 owner／admin 已將 Source 設為 **GitHub Actions**、允許 main environment 部署後才發布；Pages 未配置或來源已過期時明確跳過。專案網址為 [csfishy.github.io/taipei-safe-walk-townpass](https://csfishy.github.io/taipei-safe-walk-townpass/)，實際部署結果以對應 run 為準。Web ZIP 或 Release 下載頁不是網站部署證明。

## 架構、資料與產品邊界

- JSON payload 的唯一來源是 [contracts.schema.json](schemas/safe_walk/v1/contracts.schema.json)；Dart 模型／runtime schema 可由 `dart run tool/generate_safe_walk_contracts.dart` 重產，再執行 `--check`。不手改生成模型，也不在五模組各自定義資料型別。
- 正式入口只使用 Live，無 Mock／Demo 資料或成功 fallback；新功能直接完成真實 Provider 到 UI 的完整操作，不以 Demo 為前置。測試可保留 Fake／Mock 與 DataMode.mock 相容值，但正式入口不能選用。Unavailable 說明原因／下一步，不以文案或 readiness 旗標冒充完成。`officialReceipt` 保持 null，不宣稱警方受理或已派遣。
- 定位權限與第三方路線／據點查詢同意分開；不補示範座標或路線。附近協助者通知因身分、ownership、RPC/RLS、防濫用與保留刪除等條件未完成維持 BLOCKED；官方案件自動派送須正式授權。兩者不阻擋導航、查詢、TTS、主動系統撥號及官方通報入口。
- 行政區歷史犯罪統計不能直接等同即時道路安全評分，也不構成路段安全保證。來源、時間、認可及未知狀態各自保留。
- 犯罪參考資料以持久 Supabase 與 CI／Demo reset 隔離；App 不持有管理者憑證，只接經授權審查的受限唯讀介面。保留回報點與有座標犯罪參考點的 [50 公尺產品避讓緩衝](docs/SAFE_WALK_LIVE_MVP.md#50-公尺避讓規格)；參考座標不能冒充精確案發點，緩衝不是官方犯罪範圍或安全保證。競賽導航使用 App 內 OSM／合法步行路網，不依賴 Google Maps；不新增 AED。
- 官方 `main.dart`、GetX route、Theme、`TPColors`、品牌與原生功能沿用官方架構。安心行 UI/UX 由 **M3 莅紋**設計，M1 在 TownPass 首頁與城市服務接入同一個功能頁；不套用其他技術棧的 CSS 設計。
- 色值沿用官方 [TPColors](lib/util/tp_colors.dart)，語意與對比參考 [顏色規範](docs/SAFE_WALK_COLOR_SPEC.md)；色彩配對不等於整個 App 已通過 WCAG。
- 定位權限、原生／WebView、相機、通知、音訊、撥號與裝置無障礙仍需實機驗收。保留官方來源、分析／測試或產出安裝包，都不能替代這些驗收。

## 開工文件

| 文件 | 用途 |
|---|---|
| [AGENTS.md](AGENTS.md) | 人員與 AI 協作、修改範圍、資料與 Git 規則 |
| [LIVE-FIRST 完成定義](docs/SAFE_WALK_LIVE_FIRST.md) | 正式入口 Live-only、完整流程、Unavailable 與驗收證據 |
| [Live MVP](docs/SAFE_WALK_LIVE_MVP.md) | 現行正式功能驗收及 Mock／Live／Unavailable 定義 |
| [Live Readiness](docs/SAFE_WALK_LIVE_READINESS.md) | 逐能力現況、接線／測試／實機缺口與旗標解除條件 |
| [規格逐項審查](docs/SAFE_WALK_SPEC_AUDIT.md)、[P0–P2 工程計畫](docs/SAFE_WALK_LIVE_PLAN.md) | Markdown／程式對照、五人分工與第一個實作提示詞 |
| [架構基線](docs/SAFE_WALK_ARCHITECTURE.md) | 官方接點、模組邊界與整合方向 |
| [五人模組契約](docs/SAFE_WALK_MODULES.md) | 輸入／輸出、主要聯絡人、狀態與持續交付 |
| [開放式平行協作](docs/SAFE_WALK_COLLABORATION.md) | 跨模組開發、A/B/C 審查、功能工作包與 PR 流程 |
| [導航呈現契約](docs/SAFE_WALK_NAVIGATION_PRESENTATION_CONTRACT.md) | M1／M2／M3 正式流程、同意、路線與 UI 接線 |
| [Schema 與 Dart 模型](docs/SAFE_WALK_SCHEMA.md) | 單一來源、strict 欄位、nullable、語意與取消 |
| [顏色規範](docs/SAFE_WALK_COLOR_SPEC.md) | 官方 TPColors 語意；不預先定義 UI 版型 |
| [初始化驗證紀錄](docs/SAFE_WALK_INITIALIZATION.md) | 初始化時的實跑證據與限制；後續狀態以新 run 為準 |
| [Safe Walk CI](docs/SAFE_WALK_CI.md) | scoped 門檻、完整分析報告與選用建置 |
| [建置與部署](docs/BUILDS.md)、[預發佈說明](docs/PRERELEASE-NOTES.md) | artifacts、tag、Pages、平台工具與安裝限制 |
| [來源紀錄](docs/SAFE_WALK_UPSTREAM.json) | 官方 base commit 與來源追溯 |
| [競賽與授權待確認](docs/SAFE_WALK_COMPETITION_LICENSE.md) | 正式交付形式、AGPL 要求與待確認事項 |

## 官方來源與授權

本專案基於臺北市政府資訊局的 [taipei-doit/TownPass](https://github.com/taipei-doit/TownPass)，保留上游 Git 歷史、來源及原 [GNU GPLv3 LICENSE](LICENSE)。官方技術資料見 [TownPass 文件](https://townpass.taipei/en/docs/)。

競賽對團隊成果的 AGPL 要求、上游 GPL 部分的保留與最終交件方式仍須確認；本 README 沒有將上游重新授權，也不宣稱已完成競賽資格或授權相容性審核。Repository 為 Public 不等於這些事項已完成。
