# Safe Walk CI 與選用雲端建置

後續跨平台預覽交付另見 [Checks, prereleases and GitHub Pages](BUILDS.md)。`check-and-build` 會保留本文件的 Schema／完整測試／嚴格 scoped 門檻，另以 errors/warnings fatal、既有 style infos advisory 的全專案分析作建置閘門，建置 APK／unsigned IPA／Web 並處理預發佈與 Pages。原 Safe Walk CI／Codemagic 在 pub get 前新增產生必要的 build-info asset；以下初始化時的驗證敘述仍為歷史紀錄，不代表新的部署已執行。

2026-11-07。Flutter 專案就在 Repository 根目錄，沿用 `.fvmrc` 的 **Flutter 3.47.6** 與官方 `pubspec.lock`。這份文件描述新增工作流；配置存在不等於 GitHub／Codemagic 已執行，更不等於裝置驗收或正式發佈完成。

本次只追加 `.github/workflows/safe_walk.yml`、根目錄 `codemagic.yaml` 與本文件，不修改上游 UI、Theme、LICENSE、pubspec 或原生簽章設定。整體本機與遠端的實際驗證結果以 `SAFE_WALK_INITIALIZATION.md` 為準。

## GitHub Actions

`Safe Walk CI` 於所有 PR、`main`／`migration/**` push，以及手動 `workflow_dispatch` 執行。權限只有 `contents: read`，checkout 不保留 Git 認證；沒有 tag 發佈、GitHub Release、部署、商店上傳或對外通知步驟。

必要檢查順序：

1. 從 `.fvmrc` 安裝 SDK，記錄版本並與檔案比對，避免使用未固定的 `stable` 版本。
2. `flutter pub get --enforce-lockfile`，不以 upgrade 或重建 lock 掩蓋依賴差異。
3. `dart run build_runner build`，沿用官方 Dart／asset binding 產生流程。
4. `dart run tool/generate_safe_walk_contracts.dart --check`，檢查已提交的 Schema 產物一致性。
5. **只有來源分支為 `migration/` 的 PR** 執行 `dart run tool/check_safe_walk_baseline.dart --initialization`，檢查本次無新 UI 的初始化邊界。一般 feature PR／後續 M3 UI 開發不套用此初始化限制。
6. 實跑完整 `flutter analyze --no-pub`，保存原始輸出、exit code 與 step outcome。
7. 嚴格執行 `flutter analyze --no-pub lib/features/safe_walk tool test/features/safe_walk`。
8. `flutter test --no-pub` 執行整套測試，包含官方根目錄測試及安心行測試；不跳過或更改 counter 模板測試來假裝全部成功。

### 完整分析與新增範圍的門檻

上游可能有既有分析資訊或警告；因此完整分析採 `continue-on-error`，讓本次新增範圍與測試仍有機會提供結果。**完整分析本身只要 exit code 非零，就是未通過，不能寫成 PASS。** 工作流保留 `full-analyze.log`、`full-analyze-exit.txt`，在 Job Summary 顯示原始 outcome，未通過時發出 warning。沒有關閉 lint、使用 `--no-fatal-infos` 或修改官方畫面來消除上游問題。

Schema、一致性、初始化 guard、新增範圍分析及完整測試都是必要門檻。任何一步失敗或未執行，均應照實回報。即使工作流因新增範圍通過而呈綠色，也不能將非阻擋的完整分析說成已通過；下一步應對照完整報告與官方基底，區分上游既有問題和本次新增問題。

目前的嚴格分析範圍對應這次無 UI 初始化。後續若經授權修改官方 route／頁面或其他範圍，M1 應將相關路徑納入嚴格檢查，或建立可核對的上游診斷 baseline；不能把新增範圍外的所有新問題自動歸類成上游資訊。

檢查報告保存在 `safe-walk-verification-reports` artifact，預設保留 14 天。設定 required checks／branch protection 是另一項 Repository 設定；本工作流不會自動啟用它。

### Android debug：只在手動勾選後建置

手動執行 workflow 並將 `build_android_debug` 設為 true，必要檢查成功後才啟動 Android job。它使用 Linux、JDK 17、Android command-line tools 與同一份 `.fvmrc`，執行 `flutter build apk --debug --no-pub`，產物為 `safe-walk-android-debug` artifact。

這是裝置測試用 debug APK，不是正式簽章版，也沒有上架、安裝、啟動或實際功能驗證。本機缺少 Android SDK／Java 時應記為未完成或環境阻塞，不能因 CI 配置存在就宣稱 APK 已產出。此 Linux 工作流不編譯 iOS。

## Codemagic：選用、手動、未連帳號

根目錄 `codemagic.yaml` 定義 `safe-walk-ios-unsigned`，使用 `mac_mini_m2`，`working_directory: .`。沒有 `triggering`、`publishing`、secret group、Apple 登入、憑證、provisioning profile 或通知設定。本次沒有連接 Codemagic 帳號、啟動建置或配置付費資源。

`environment.flutter: fvm` 依 Codemagic 官方文件讀取根目錄 `.fvmrc`；同樣記錄並驗證實際版本。工作流執行 pub get、官方 build_runner、Schema check、完整分析、新增範圍嚴格分析及完整測試，再執行：

```sh
flutter build ios --debug --no-codesign --no-pub
```

Codemagic 的完整分析採 `ignore_failure: true`，但仍以原始 exit code 結束該腳本，保留日誌與狀態檔並明示未通過；其餘必要步驟沒有忽略失敗。測試提供 Flutter `--machine` JSON 報告。雲端整體成功也不能覆蓋完整分析的非零結果。

預期產物是 `build/ios/iphoneos/` 內的 **unsigned `.app`**，不是可直接安裝的簽署 IPA，也不是 App Store／TestFlight 交付。Xcode 保留雲端 host 預設，不猜測尚未驗證的版本；首輪手動執行會記錄 `xcodebuild -version`。可用 Xcode／CocoaPods 是否符合固定 Flutter 與官方原生工程、SDK 版本是否由服務提供，以及帳號機型使用權限，都仍需實際確認。Windows 本機不宣稱能完成 iOS 編譯。

Codemagic 沒有套用一次性的無 UI 初始化 guard；該限制只在 GitHub migration PR 啟用，避免之後 M3 的正常設計被本初始化配置永久限制。Schema、分析與測試仍繼續適用。

## 驗證紀錄邊界

| 項目 | 本文件建立時可聲明的狀態 |
|---|---|
| 工作流內容與官方文件對照 | 已檢視；採 `.fvmrc`、根目錄及未簽章流程 |
| YAML 語法／結構檢查 | 已以本機 Dart 的既有 `yaml` 套件解析兩檔，並檢查觸發器、read 權限、migration guard、手動 Android、FVM 與無 publishing 等結構；未宣稱 actionlint、Codemagic 完整 schema 或服務端執行通過 |
| GitHub 新工作流執行 | 尚未由本文件建立動作觸發；以實際 run URL／commit 與結果為準 |
| 完整 Flutter analyze | 結果獨立列示；非零不得報 PASS |
| Android debug APK | 手動選用且成功建置後才可宣稱產出 |
| Codemagic 帳號／雲端 build／unsigned iOS | 未連接／未執行，沒有已產出或已可安裝的宣告 |

## 官方與工具維護者來源

- [flutter-action 維護者 README：讀取 `.fvmrc`](https://github.com/subosito/flutter-action#use-version-from-pubspecyaml-or-fvm-config)。
- [Codemagic：Flutter 與 FVM 設定](https://docs.codemagic.io/yaml-quick-start/building-a-flutter-app/#setting-the-flutter-version)。
- [Codemagic：YAML、工作目錄、失敗處理與 artifacts](https://docs.codemagic.io/yaml-basic-configuration/yaml-getting-started/)。
- [Codemagic：未簽章 Flutter iOS 範例](https://docs.codemagic.io/yaml-quick-start/first-signed-build/)。
- [Codemagic：Flutter 測試與 JSON 報告](https://docs.codemagic.io/yaml-testing/testing/)。

官方範例中關於簽章、商店發佈或寄信的部分沒有套入本專案。未來需要部署或正式簽章時另開具體任務，不從本初始化配置推定已取得授權。
