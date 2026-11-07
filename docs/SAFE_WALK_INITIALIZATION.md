# 臺北安心行：TownPass Flutter 初始化紀錄

日期：2026-11-07（Asia/Taipei）。初始化分支 `migration/townpass-native-base`；透過 PR 交付，**不自行合併**。

## Repository 與來源

- 新 Repo：<https://github.com/csfishy/taipei-safe-walk-townpass>，Default Branch 為 main。建立時為 Private；交付前遠端已變為 Public，2026-11-07 經使用者明確確認保留 **Public**。
- `upstream`：<https://github.com/taipei-doit/TownPass>，官方 main Base `c8e5d4d3f8f699f3d9d6cd68e129ed4da12037b3`，完整 194 個上游提交、不是 shallow clone。
- `origin`：團隊 Repo；main 先保留未修改的官方 Base，安心行內容由本 migration PR 審查後才進入共同基線。
- `.fvmrc` 固定 Flutter **3.47.6**；官方 SDK 實際 Dart **3.13.5**、Framework `5fc346839b5d0eef006ed8404392afb4dfae428d`。
- 使用官方 SDK archive，Windows ZIP SHA-256 `a01bb0d26de91bc23c97cd9ccfaad281a612fb8304213fdd5df1119a09404796` 已校驗。SDK／Pub cache 僅放工作區的 Repo 外工具目錄，沒有把 SDK 入版控或改全域 PATH。
- 官方 pubspec／lock／GetX／Flutter 版本、main／routes／pages／theme、原生平台、品牌與 GPLv3 LICENSE 均未修改。詳細來源見 `SAFE_WALK_UPSTREAM.json`。

## Legacy 工作保留

原 Private React Repo <https://github.com/csfishy/taipei-safe-walk> 仍完整保留，沒有重設 main、force push、刪分支或關 PR。遷移檢查時 PR #1（M2）與 #2（預發佈）已合併；M5 新提交 `4a4d2593162ac814e314a520bc62d309fd917435` 留在原 `feat/m5-companion`，尚未開 PR。

舊 Schema 從 main `2b13a9f5d18ad35ec0855dc3f9d8ea73c054b723` 保留，原始 43 個 Schema／fixture 檔雜湊一致。React UI、CSS、Capacitor wrapper 與舊 Design System **沒有移植為新架構規格**。舊 `DESIGN_SYSTEM.md` 是 Legacy 參考，新案只遵守官方 Theme 與顏色文件；M3 的新 UI 設計尚未開始。

## 本輪新增內容

| 範圍 | 實際內容 |
|---|---|
| 架構／協作 | AGENTS、Architecture、Schema、Modules、Color、Initialization、CI、競賽授權待確認文件與五份模組 README |
| 共用契約 | 原 JSON Schema 1.0.0、16 個 typed Dart models、4 組 sealed unions、enum wire mapping、受限 validator、6 組語意檢查、取消協定、generator／一致性檢查 |
| M1 | 明確使用者操作／模式閘門、lazy TownPass 位置 Adapter、逾時／取消／錯誤映射及過期／未來定位拒絕；求助介面保留未配置，不撥號、不分享、不通報 |
| M2 | RouteService 抽象接點；沿用共用 request/result，不建立真實路線 provider 或地圖 |
| M3 | presentation 只有 README，沒有 Dart／Widget；所有正式新增 UI/UX 留給莅紋 |
| M4 | Parser＋Schema／語意驗證、注入式唯讀 Mock Repository，空資料與 live 未配置明確區分 |
| M5 | Controller／Audio Adapter 抽象介面、純狀態轉移與測試；沒有錄音、具體播放器或通話頁 |
| 驗證 | 原始 counter 範例測試修為官方 route 保留／唯一性檢查；新增資料／Adapter／狀態／顏色測試 |
| CI | GitHub Actions pinned SDK、lock、生成、分析、完整測試、上游保留 guard；手動 Android 可選；Codemagic 手動 unsigned iOS 設定 |

M1～M5 的實際路徑均為 `lib/features/safe_walk/` 下的 platform、navigation、presentation、safety_data、companion；共用 contracts／models 位於 shared。輸入輸出與所有權見 `SAFE_WALK_MODULES.md`。

## 實際驗證結果

| 檢查 | 結果 | 證據／限制 |
|---|---|---|
| `flutter pub get --enforce-lockfile` | PASS | 官方 lock 成功；pubspec／lock 沒有 diff，沒有升級依賴 |
| `dart run build_runner build` | PASS | 官方 json_serializable／flutter_gen，13 個輸出；沿用官方忽略規則，不手改生成檔 |
| Safe Walk generator／`--check` | PASS | Schema、runtime bundle、Dart models 一致；原樣來源 43 檔 SHA-256 一致 |
| `flutter analyze --no-pub lib/features/safe_walk tool test/features/safe_walk` | PASS | 新增範圍 No issues found，包含 lint；沒有以 ignore 掩蓋新增診斷 |
| 完整 `flutter analyze --no-pub` | **未通過，exit 1** | 25 個診斷：7 warnings、18 info、0 errors，全在未修改的官方 lib/page、lib/util；未為清 lint 重做上游程式或改 analysis_options |
| 完整 `flutter test --no-pub --reporter expanded` | **PASS：119/119** | 無 skip；涵蓋契約 58、M4 21、M1 13、M5 純狀態 22、色彩 3、官方路由 2 |
| 官方來源／UI guard | PASS | 完整官方歷史為 HEAD 祖先；官方 main/pages/util/service/assets/fonts/iOS/Android/LICENSE／pubspec／版本檔均無 diff；本輪沒有新 Widget |
| 顏色配對 | PASS（指定配對） | 官方 primary500 白字 2.39:1 不適用；深字配 primary500 7.24:1；primary700 白字 5.89:1、red600 白字 5.51:1；不是整體 WCAG 認證 |
| Android Debug Build | **已嘗試，環境阻塞** | `flutter build apk --debug --no-pub` exit 1：No Android SDK found；本機也未找到 Java／adb，不宣稱 APK 成功 |
| 本機 iOS Build | 未執行 | Windows 沒有 Xcode；不能本機編譯 iOS |
| Codemagic | 設定／YAML 檢查完成，雲端未執行 | root path、FVM pin、manual-only、unsigned .app；未連帳號、簽章、billing 或發布 |
| GitHub Actions | 以該 PR 的真實 run 為準 | 完整 analyze 的非零結果保留為 warning／artifact；新增範圍與完整測試為必要門檻，分析 error 仍會令 job 失敗 |
| 實機／官方功能啟動 | 未執行 | 未登入／執行官方 App、未取真位置、未播放、未撥號；來源未變＋分析／測試不等於所有實機功能已驗收 |

上游原 `test/widget_test.dart` 是 Counter 模板，實跑出現 SharedPreferencesService 未初始化與找不到文字 0 的錯誤（exit 1）。本輪只改該測試為不啟動原生權限的官方 route contract smoke test；沒有為通過模板測試在 App 加 counter、fake login 或替代首頁。

## 重現方式

先安裝 FVM／官方指定 SDK，或確保 PATH 的 Flutter 恰為 3.47.6。在新 Repo 根目錄：

```text
fvm install
fvm flutter --version
fvm flutter pub get --enforce-lockfile
fvm dart run build_runner build
fvm dart tool/generate_safe_walk_contracts.dart --check
fvm dart tool/check_safe_walk_baseline.dart --initialization
fvm flutter analyze --no-pub
fvm flutter analyze --no-pub lib/features/safe_walk tool test/features/safe_walk
fvm flutter test --no-pub
```

完整 analyze 目前仍預期報上述官方診斷；不要把 scoped analyze 的 PASS 改寫成整個 TownPass 無問題。`--initialization` 是本次 migration 的無 UI／來源保留檢查，CI 只在 migration PR 啟用，不用它規定日後 M3 的 Widget 架構。

## PR、五分支與權限

本輪只提交並 push `migration/townpass-native-base`、建立 PR。PR 連結及最新 Commit 以交付回報／GitHub 為準，不自行合併。新 main 尚非已合併的安心行基線。

五分支目前 **pending**：feat/m1-platform、feat/m2-navigation、feat/m3-experience、feat/m4-safety-data、feat/m5-companion。必須等使用者確認初始化 PR 合併後，M1 才從同一個已驗證合併 Commit 建立並核對五個遠端 SHA。禁止從舊 React Repo 建分支或把未合併初始化當成已正式 ready。

使用者另已明確授權五位新 Repo 協作者，已送出／核對 Write 權限；未將 Email／憑證入版控。Pending invitation 不等於本人已接受，最終狀態以 GitHub 存取清單為準，姓名／模組與 Email 不做推測綁定。

可先 clone migration 分支進行審查：

```text
git clone --branch migration/townpass-native-base https://github.com/csfishy/taipei-safe-walk-townpass.git
```

## 待人工確認與後續交付

- 主辦對原生 Flutter 修改、服務入口／WebView 相容與交件物的正式要求；證據與問題見 `SAFE_WALK_COMPETITION_LICENSE.md`。
- 上游 GPLv3 與團隊成果 AGPL v3-or-later 的著作／結合／通知方式；LICENSE 未替換，也未宣稱已獲授權相容核准。
- 初始化 PR 審查與合併、五分支建立、協作者接受邀請。
- 本機 Android SDK／JDK、Codemagic 首次帳號設定與雲端 Xcode／unsigned iOS build、正式簽章與裝置安裝；本輪不做 iPhone 安裝。
- 位置權限、TownPass 真實啟動、音訊資源／離線／取消競態、VoiceOver／TalkBack、iPhone safe area 等實機驗收。
- 真實資料、步行 provider、完整音訊控制器及全部新增 UI，分別由模組負責人後續交付。M3 對 UI/UX 的設計權未被預設版型限制。

## 初始化範圍確認

- [x] TownPass 官方原生 UI 未重新設計。
- [x] React 不再是新案主要 App 架構，歷史成果保留。
- [x] M3 沒有被預建首頁、Widget Tree 或版型限制。
- [x] 僅新增顏色規範，沒有新增產品介面。
- [x] 五個 Flutter 模組責任與資料接點清楚。
- [x] 共用 JSON Schema 保留並有可測 Dart 對照。
- [x] 其他成員的 GitHub 工作未遭覆寫／丟棄。
- [x] 已有同一 TownPass 架構的可審查基線；正式五分支仍待 PR 合併。

## 2026-11-07 Supabase 本機設定補充

使用者另明確要求將目前 TownPass Flutter App 設定連至指定 Supabase 專案。本輪從共同 main `99d4135` 建立本機 `codex/supabase-setup`；初始化階段「不新增資料庫」不撤銷此次連線設定授權。設定範圍與實際結果見 [Supabase 連線紀錄](SAFE_WALK_SUPABASE.md)。

已確認 Data API 啟用，設定忽略版控的公開 client key，並以 Dart 3.13.5 實跑不讀寫資料列的 PostgREST 連線檢查。隔離純 Dart runner 20 項測試、Schema check、模組 guard 與格式檢查通過；本機 Flutter 3.47.7 與 pin 3.47.6 不符，因此本輪沒有執行 Flutter pub get、build_runner、完整 analyze／Flutter test 或 build，亦沒有把 formatter 的缺少 lint include 提示當成完整 lint 通過。

沒有部署 PR #21 的附近通知 SQL：其匿名 security-definer RPC 尚缺可信身份／ownership 驗證。App 入口仍 Mock，沒有真實定位、資料列寫入、通知、官方登入或實機驗收；本輪以 `codex/supabase-setup` 交 PR 審查，不自行合併或發布。
