# 臺北安心行 · Taipei Safe Walk

以官方 TownPass Flutter App 為基底的五人協作專案，參與「2026 臺北城市通微服務黑客松」。專案目前提供共用資料契約、無 UI 的服務接點、資料適配器與測試；完整安心行畫面、真實步行導航、官方求助介接與裝置驗收仍待各模組交付。

- **Repository**：[csfishy/taipei-safe-walk-townpass](https://github.com/csfishy/taipei-safe-walk-townpass)；Public，預設分支 `main`。
- **開發基線**：Flutter **3.47.6**／Dart **3.13.5**，依 [.fvmrc](.fvmrc) 與已提交的 [pubspec.lock](pubspec.lock)；同一個 Flutter App，以模組分支協作。
- **目前狀態**：五模組初始化及預覽建置設定均已合併至 `main`；[預覽建置與 CI 修正 PR #2](https://github.com/csfishy/taipei-safe-walk-townpass/pull/2) 為已合併的歷史紀錄。產物與部署狀態請查看 [GitHub Actions](https://github.com/csfishy/taipei-safe-walk-townpass/actions) 對應 commit 的實際結果，不能將設定已合併視為全部檢查或部署成功。

## Clone 與五人分工

每位工程師使用自己的 clone。讀取 Public Repository 不需共用帳號；推送仍需自己的 GitHub 帳號及寫入權限。

```sh
git clone --branch main https://github.com/csfishy/taipei-safe-walk-townpass.git
cd taipei-safe-walk-townpass
git fetch origin
```

五個模組遠端分支已建立，首次 checkout 使用下表指令；本機分支已存在時使用 `git switch 分支名稱`。

| 模組／負責人 | 首次 checkout | 可修改的模組目錄與責任 |
|---|---|---|
| M1 小魚 | `git switch --track origin/feat/m1-platform` | `lib/features/safe_walk/platform/`；平台、唯一定位入口、求助、跨模組、route／CI |
| M2 Steven | `git switch --track origin/feat/m2-navigation` | `lib/features/safe_walk/navigation/`；座標與 RouteService，消費 M1 位置、不另監聽 GPS |
| M3 莅紋 | `git switch --track origin/feat/m3-experience` | `lib/features/safe_walk/presentation/`；正式 UI/UX 唯一設計負責人 |
| M4 信義 | `git switch --track origin/feat/m4-safety-data` | `lib/features/safe_walk/safety_data/`；資料來源、Parser、Repository 與 fixtures |
| M5 奶爸 | `git switch --track origin/feat/m5-companion` | `lib/features/safe_walk/companion/`；無 UI 控制器、Audio adapter、取消與清理 |

正式開工前同步已合併的共同基線：`git fetch origin` 後，在自己的分支執行 `git merge origin/main`。有衝突時與 M1 協調，不 force push 或重設隊友歷史。main 已包含下列開發與預覽流程，無須切到 PR #2；其他待審模組 PR 的成果仍須合併後才會進入共同基線。

共用 Schema、Dart models／contracts、套件／lock、CI、官方 route 與跨模組修改由 M1 統一協調。模組透過共用型別及依賴注入整合，不直接 import 其他模組實作。詳細輸入／輸出、狀態與第一輪交付見 [五人模組契約](docs/SAFE_WALK_MODULES.md) 及各模組 README。

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

下列兩份工作流均已在 main；執行規則與實際結果分開看，預覽產物、Release 與 Pages 以對應 run 為準：

| 工作流 | 觸發與用途 |
|---|---|
| [Safe Walk CI](https://github.com/csfishy/taipei-safe-walk-townpass/actions/workflows/safe_walk.yml) | PR、main／migration push、手動執行；Schema 一致性、模組／工具分析、完整測試與原始診斷報告；可手動選擇 Android debug build |
| [check-and-build](https://github.com/csfishy/taipei-safe-walk-townpass/actions/workflows/build.yml) | PR、main push、`v*-pre.*` tag、手動執行；檢查後產生 Android APK／unsigned iOS IPA／Web 預覽產物 |

PR／main／manual run 產生可下載 artifacts，不直接等於 GitHub Release。只有 **push 事件推送符合 pubspec 版本的預發佈 tag**，且全部必要平台建置通過後，才發布 GitHub prerelease；例如 `0.0.12-pre.1+1` 對應 `v0.0.12-pre.1`。手動對既有 tag 執行不會建立 Release；Pages 仍依下述網站部署條件判斷。不要覆寫已發布 tag。手動執行入口需工作流已存在於預設分支；完整規則見 [建置與部署](docs/BUILDS.md)。

本機可在完成相同 metadata／pub get／generation 後建置；以下 iOS 範例的純數字版本對應目前 pubspec：

```sh
flutter build apk --release --no-pub
flutter build ios --release --no-codesign --no-pub --build-name 0.0.12 --build-number 1
flutter build web --release --no-pub --base-href /taipei-safe-walk-townpass/ --no-web-resources-cdn
```

iOS `--build-name` 使用 pubspec 版本的純數字部分，升版時需同步調整。這些命令需要對應平台工具；列出命令不是已完成建置的證明。預覽使用獨立身份 `Town Pass Preview`／`io.github.csfishy.taipeisafewalktownpass.preview`，不是正式市政服務發行版。Android APK 使用測試金鑰；unsigned IPA 沒有 provisioning profile／簽章，不能直接安裝或當作 TestFlight 版本，仍需適當簽署。下載與安裝限制見 [預發佈說明](docs/PRERELEASE-NOTES.md)。

GitHub Pages 只在非 PR run、Web／Android／iOS 三個建置成功，且 owner／admin 已將 Settings → Pages 的 Source 設為 **GitHub Actions**、允許對應 main／tag environment 部署後才可能發布；未配置時保留 Web ZIP 並明確跳過部署。預期專案網址為 [csfishy.github.io/taipei-safe-walk-townpass](https://csfishy.github.io/taipei-safe-walk-townpass/)，**部署成功前僅是預期網址**，實際以 Pages deployment 回傳連結為準。Web ZIP 或 Release 下載頁不是已上線網站。

## 架構、資料與產品邊界

- JSON payload 的唯一來源是 [contracts.schema.json](schemas/safe_walk/v1/contracts.schema.json)；Dart 模型／runtime schema 可由 `dart run tool/generate_safe_walk_contracts.dart` 重產，再執行 `--check`。不手改生成模型，也不在五模組各自定義資料型別。
- 模組先以 mock／fixtures／fake adapters 獨立開發。mock 不是真實位置、正式機關資料或救援；live provider 未配置要明確失敗，不能用 mock 假成功。`officialReceipt` 保持 null，不宣稱警方已受理或救援已派遣。
- 行政區歷史犯罪統計不能直接等同即時道路安全評分，也不構成路段安全保證。來源、時間、認可及未知狀態各自保留。
- 官方 `main.dart`、GetX route、Theme、`TPColors`、品牌與原生功能沿用官方架構。新增 UI/UX 由 **M3 莅紋**設計，目前 presentation 只保留責任說明，不預建首頁、SOS、地圖、通話頁或 Widget Tree；不套用其他技術棧的 CSS 設計。
- 色值沿用官方 [TPColors](lib/util/tp_colors.dart)，語意與對比參考 [顏色規範](docs/SAFE_WALK_COLOR_SPEC.md)；色彩配對不等於整個 App 已通過 WCAG。
- 定位權限、原生／WebView、相機、通知、音訊、撥號與裝置無障礙仍需實機驗收。保留官方來源、分析／測試或產出安裝包，都不能替代這些驗收。

## 開工文件

| 文件 | 用途 |
|---|---|
| [AGENTS.md](AGENTS.md) | 人員與 AI 協作、修改範圍、資料與 Git 規則 |
| [架構基線](docs/SAFE_WALK_ARCHITECTURE.md) | 官方接點、模組邊界與整合方向 |
| [五人模組契約](docs/SAFE_WALK_MODULES.md) | 輸入／輸出、所有權、狀態與第一輪交付 |
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
