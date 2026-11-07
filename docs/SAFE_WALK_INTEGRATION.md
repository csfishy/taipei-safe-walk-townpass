# 臺北安心行：M1 TownPass 入口整合

2026-11-07（Asia/Taipei）。整合分支 `integration/m1-townpass-entry`，起點為 main `31cb0ac8746eb3409d3fefca6ffd4e66717276b9`；開發期間以 fast-forward 納入隊員新 main `3965b8a15844d6002689f6aee0dbc3ef72aa09ac`，沒有重設或覆寫隊員工作。本輪透過 PR 交 main，不自行合併、不建立新版 Release、不移動 `v0.0.12-pre.1`。不可用其他提交的 CI 成功代替本輪成果；實際 run、head／測試 merge SHA 及 artifact 連結記錄於本 PR 描述。

## TownPass 入口與組合邊界

使用者已授權 M1 在官方城市服務中加入安心行入口、註冊 GetX route，並組合已合併的 M3 畫面及 M1／M4／M5 接點。以下路由與完整操作已通過 Widget Tests，仍須以新 IPA 在 iPhone 確認。

| 接點 | 本輪設定 |
|---|---|
| 城市服務 | `MyServiceItemId.safeWalk`，標題「臺北安心行」，`cityService` 類別；重用官方 location-search SVG，沒有新增入口 Widget 或圖示資產。 |
| 城市服務入口顯示 | 官方 `PinnedServiceWidget` → `PinnedServiceItemWidget`；預設釘選清單保留原三項，加入安心行為第四項。官方編輯列表也從同一 enum 取得項目，沒有重複服務定義。現有 controller 釘選狀態只存記憶體，未新增儲存邏輯。 |
| 首頁功能卡片 | `HomeView` 在新聞上方顯示「臺北安心行」卡片，包含服務圖示、標題、說明與向右箭頭；點按沿用同一個 `local://safe_walk`。與城市服務共用 `MyServiceItemId.safeWalk.item`，不另建第二個服務或 route。 |
| URI／GetX route | `local://safe_walk` → `TPRoute.safeWalk`（`/safe_walk`）。官方 `openUri()` 取 URI 的 host；`local:///safe_walk` 的 host 為空，不是可用形式。真實入口 tap、GetX 導頁及 route builder 已有測試。 |
| 組合根 | `SafeWalkCompositionRoot`，位於 `platform/integration/safe_walk_composition_root.dart`，注入 `PlatformService`、`SafetyDataRepository`、`CompanionSpeakerAdapter`。退出會取消請求、停止及 dispose 陪伴；測試涵蓋三次進出與遲到資料。App 背景沒有新增 lifecycle observer，仍列實機／後續項目。 |

跨模組組合集中於 `lib/features/safe_walk/platform/integration/`，以共用 models／contracts 交換資料；M2、M3、M4、M5 不直接依賴彼此實作。M1 不改共用 Schema 來遷就畫面示範型別，也不重做官方登入、會員、Theme、TPColors 或 WebView。M3 仍管理正式 UI/UX 設計。

本輪是同一個 TownPass Flutter App 內的原生模組與 route，**不是獨立 HTTPS 服務或已接妥的 TownPass WebView 微服務**。Flutter Web artifact 也不自動等於主辦核准的 WebView 交件；競賽交付形式及授權待確認項目仍見 [競賽與授權紀錄](SAFE_WALK_COMPETITION_LICENSE.md)。

### TownPass-self 首頁入口對齊

依使用者要求，首頁入口採用 [TownPass-self 的功能卡片排列](https://github.com/steventeng2022/TownPass-self/blob/feat/taipei-youbike-finder/lib/page/home/home_view.dart)：卡片放在新聞上方，點按開啟同一 App 內的功能頁，返回回到 TownPass 首頁。服務名稱、說明與圖示重用既有服務目錄，功能頁仍由 `SafeWalkCompositionRoot` 組合已合併的 M3 畫面；沒有搬入參考 Repo 的公共廁所或 YouBike 功能。原城市服務入口仍可使用。

首頁卡片的導頁／返回及 320px、2 倍字體的操作由 focused widget tests 驗證；資料模式、定位與求助行為沿用下方已揭露的限制，不因入口移到首頁而開放 Live。

## 模組狀態與預設行為

| 模組 | 狀態 | 本輪可用內容與限制 |
|---|---|---|
| M1 平台 | Mock；Live UI 尚未開放 | 沿用 `TownPassPlatformAdapter`。原生組合根固定 `DataMode.mock`、`allowRealCalls: false`；進入安心行不取 GPS 或對外求助。只在使用者點按時回傳明確示範位置；求助 `officialReceipt` 為 null。Live adapter 已有拒絕、逾時、過期、缺少精度、精度超過 100m 及不可用測試，但本入口沒有 Live 切換。 |
| M2 導航 | Mock；Live provider 阻塞 | 遠端 `feat/m2-navigation` 為 `40c72e738a88d31d266adecbc723f5cd2aed12d5`，只有 README 與抽象 `RouteService.planRoute()`，沒有路網 provider。沿用 M3 示範路線，標示「示範路線／非即時導航」，不虛構 RouteService 實作。 |
| M3 體驗 | Mock 操作已接線 | 已合併的 `SafeWalkFlow` 保留畫面與配色，由 M1 注入 callbacks／資料。使用者可操作首頁、地圖／文字路線、求助地點、模擬來電、SOS 與返回；Live 顯示及新的暫停操作 callback 待莅紋交付。 |
| M4 資料 | Mock；Live 未整合 | 使用已合併的 `MockSafetyDataRepository`，注入三個標有示範來源的據點，保留 unknown／null；提供 loading／error／retry／empty。`feat/m4-safety-data` 的 `45d861cfa4cd93b300d14046874922636d3c09d8` 尚未納入 main，沒有帶入其 AED live 來源。 |
| M5 陪伴 | 控制器已接；語音未配置 | `CompanionSpeakerAdapter.unavailable()` 實際建立已合併的 `LocalCompanionController`，但沒有核准錄音或 native audio adapter，`available` 固定 false。畫面只顯示文字及「語音尚未配置」，不假裝 playing；bridge 的 start／pause／stop／SOS／dispose 契約有測試，新增正式播放／暫停 UI 留給 M3、M5 協作。未合併的情境分支沒有納入。 |

不得用未合併分支補出完成狀態。M4 的即時可取用性、合作認可及協助能力不能由 AED 登錄推測；歷史犯罪統計也不能當即時路段安全分數。示範簡訊或求助流程不得顯示真實送達、警方受理或派遣成功。

原生入口暫不提供 Live 開關：目前 M3 首頁／地圖沿用示範文字、人工路網與示範時間，僅切換定位會混淆資料。須先由莅紋提供正確 Live／unconfigured／error 顯示及必要 callback，再與 Steven、信義的正式 provider 一起接入；不以真實 GPS 配示範路線冒充完成導航。

## 必要修正與後續交接

- M1 新增原生入口與單一組合根，並讓模組 guard 僅例外允許 `platform/integration/` 接入其他模組；六項 guard 測試維持業務模組隔離。Schema、generated models、pubspec、lock、官方 Theme／登入／LICENSE 均未變更。
- M1 Adapter 補官方拒絕定位的字串錯誤映射與超過 100m 精度拒絕。這是保守展示門檻，不代表導航精度保證。
- M3 僅必要小修：地圖增加指定示範標示；定位失敗清除舊位置；Mock 簡訊即使注入 sender 也不呼叫，結尾顯示「示範完成／未傳送簡訊」；離開通話立即取消計時／延遲回覆，防止 SOS 換頁動畫期間再次朗讀。未重排版面或重設 Theme。
- M3 示範據點 B 原為 `open` 卻沒有 `checkedAt`，與 canonical contract 不符，改成 `unknown`，沒有杜撰查核時間或營業保證。
- 莅紋：Live 狀態文案、正式暫停／SOS-open／背景 callback、320px 地圖底列與大字體／VoiceOver 待驗問題；目前沒有為此重做 UI。
- Steven：可驗證步行路網 provider、RouteService 成功／失敗及不可通行狀態；信義：正式資料來源與驗證、時效與 availability 證據；奶爸：核准音檔、native audio adapter、與 M3 的播放／暫停及背景中斷 UI。未交付前維持 Mock／未配置。

## 本 PR 的 CI 與產物

目前 main 的 `check-and-build` 在 PR 跑 check、web、Android 與 iOS，後三者依賴 check 成功。iOS 使用 macOS 15、Xcode 26.1.1、Flutter 3.47.6，以 `flutter build ios --release --no-codesign` 建立 iPhone device app，再封裝成 `Payload/Runner.app`。

| 工作流 | 本輪預期輸出與發布邊界 |
|---|---|
| `.github/workflows/build.yml` | PR 成功時提供 `prerelease-ios` artifact，內含 `taipei-safe-walk-townpass-ios-unsigned.ipa`，保留 30 日；另有 web／Android artifacts。最新 main 的 Release job 會處理 main push／版本 tag push，PR 明確排除 Release 和 Pages；本輪不推 main。 |
| `.github/workflows/safe_walk.yml` | Schema、生成、分析、完整測試與報告。完整分析的非零結果仍透明記錄；scoped analysis／測試為必要門檻。手動可選 Android debug，沒有 iOS job 或發布。 |
| `codemagic.yaml` | 可選手動雲端設定，沒有帳號／簽章／發布整合。現有流程建 unsigned debug `.app`，不是本 PR 的 release IPA 來源；未執行不能宣稱 Codemagic 已 build。host Xcode 需另核對 locked plugin 的最低版本。 |

PR #8「main push 自動 prerelease」於本輪開發期間由隊員合併，main 成為 `3965b8a`。本分支以 fast-forward 保留該既有修改，沒有重寫工作流；後續若有人合併本 PR，main push 會依該設定發布，須由隊長決定。本輪只建立 PR，沒有觸發 main push、Release 或 Pages，保留現有 tag 與 Release。

`verify_native_release.py` 會檢查 ZIP 完整性、內嵌 build-info、iOS bundle／版本與無簽章檔案，以及部分二進位 header。它不是完整原生格式或實機驗證：Android 識別目前是 manifest 字串搜尋，未精確比較安裝 package／版本；iOS arm64 CPU header 也未區分 device／simulator platform。正確建置目標仍由 CI 的原生 build 命令指定；不可把 verifier PASS 擴大為可安裝、可導航或已通過實機驗收。

本輪接線需要通過正常的模組 guard。跨模組例外只能允許 M1 的 `platform/integration/`，不能取消所有模組邊界；初始化 `--initialization` 的無 UI 限制只用於 migration PR，不能拿來限制已授權的整合或 M3 正式設計。

## 取得本輪 IPA 與 iPhone 安裝前提

1. 開啟本整合 PR，從 Checks 進入最新 head 對應的 `check-and-build` run；核對 source commit，等待 check 與 iOS job 真正完成。PR 的預設 checkout 會使用測試 merge commit，`build-info.commit` 因此可能不是 PR head SHA，兩者須連同 run 記錄。不要使用舊 `v0.0.12-pre.1` Release 的 IPA 代替本輪成果。
2. 在該 run 的 Artifacts 下載 `prerelease-ios` 並解壓取得 unsigned IPA；artifact 需要 GitHub 登入及適當讀取權限，也有到期日。PR、run、head SHA 及 artifact 連結由本輪交付紀錄補上。
3. 此 IPA **沒有簽章與 provisioning profile，不能直接安裝，也不是 TestFlight build**。由有權限的隊員在 macOS 使用既有 Apple 開發簽署流程，為主 App 及需簽署的內嵌內容配置相符的 bundle ID、entitlements、憑證與 provisioning；開發／Ad Hoc profile 必須涵蓋測試 iPhone。
4. 重新簽署後，依團隊選定的 Xcode／裝置安裝流程裝到 iPhone，必要時啟用 Developer Mode。若尚無可用的重新簽署流程，改從同一個 PR commit 在 macOS Xcode 設定 Team、重建並安裝，不能宣稱 unsigned IPA 已安裝成功。

簽署與測試裝置的要求依 [Apple：發佈至已註冊裝置](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices)及[建立開發 provisioning profile](https://developer.apple.com/help/account/provisioning-profiles/create-a-development-provisioning-profile)；Xcode 裝置執行流程見 [Apple：在模擬或實體裝置執行 App](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices)。這些是平台前提，沒有宣稱本輪已完成簽署。

本輪不把 Apple 私鑰、憑證、profile、裝置 UDID 或登入資訊提交到 Repo，也不代為連線 Apple 帳號。簽署／安裝完成後仍須跑下列實機驗收。

## iPhone 實機驗收

| 步驟 | 要確認的結果 |
|---|---|
| 啟動 TownPass 並從城市服務進入安心行 | 保留官方啟動與既有服務行為；本輪 route 確實進到已合併的 M3 flow，返回不破壞原頁面。確認裝置執行的是本 PR commit。 |
| 首次進入與背景／返回 | 顯示示範模式；安心行入口不自行啟動 GPS、音訊、電話或簡訊。背景／返回／退出清理本輪 controller、訂閱、timer 與延遲回應。 |
| 定位操作 | mock 只顯示注入的示範位置；若本輪另有明確 live 測試入口，分別驗允許／拒絕／逾時，不能將失敗補成示範 GPS。不要將真實位置放入截圖、log 或回報附件。 |
| 地圖與據點 | 路線與時間保持示範揭露；M4 mock 據點的 unknown／null、空資料、載入及錯誤可分辨，不顯示成真實附近無救援或道路安全保證。 |
| 陪伴 | 無正式音檔／audio adapter 時明示未配置，不出現假 playing；停止、求助中斷、背景與離開不留下音訊或遲到狀態。文字劇本不代表真人通話。 |
| 求助與簡訊 | 預設真實操作關閉，只驗不撥號、不送訊息、不回傳受理成功；保留「未通知任何人」。不撥打 110／119 或送真實報案做測試。 |
| 顯示與操作 | 在 iPhone 小螢幕、大字體、VoiceOver、減少動態效果下核對主要入口、返回與求助文字；發現版面問題交 M3，不把 CI 成功等同無障礙驗收。 |

## 本輪實際驗證紀錄

| 項目 | 本輪狀態 |
|---|---|
| 入口項目／URI／route／組合生命週期 | 本機 4 項入口、9 項整合操作、11 項 speaker bridge、6 項邊界測試通過；涵蓋 A–H、三次進出、取消遲到資料、Mock 不對外與 SOS 延遲回覆中斷。背景未測。 |
| 本機 metadata、lock、build_runner、Schema check、guard | 本輪已執行通過；Schema 一致且依賴 lock 無變更。納入新 main 後的 Python 工具測試 17 項通過（外部發布為 fake，沒有真正發布）。 |
| 本機 scoped analyze／Flutter tests | Scoped analyze 無問題；完整 analyze `--no-fatal-infos` exit 0，只有 17 項既有 info、沒有 error／warning。完整 Flutter tests 174 通過、9 項既有 opt-in 截圖測試跳過，沒有把跳過列為 PASS。 |
| Chrome、web／Android／iOS build | 以本 PR 最新 `check-and-build` 的實際各 job／step 為準，run 與 artifact 連結記於 PR 描述。Windows 本機沒有編譯 iOS；CI 成功仍不等於實機已通過。 |
| PR／head SHA／測試 merge SHA | 由本 PR 描述記錄；PR checkout 可能是 synthetic merge commit，不能將 build-info 的 commit 誤標為 head。 |
| 新 unsigned IPA artifact | 從本 PR 最新成功 run 的 `prerelease-ios` 下載；須核對 commit 並重新簽署，不能直接安裝。實際產物／驗證結果記於 PR 描述，不能以舊 Release 替代。 |
| iPhone 簽署、安裝及上表實機驗收 | 未執行 |

只有實際完成的項目能改為 PASS；未完成、失敗、跳過與環境限制分別記錄。初始化或其他 PR 的成功 run 不代替本輪驗證。
