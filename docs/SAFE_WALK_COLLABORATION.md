# 臺北安心行：開放式平行協作

## 活動後維護分工（2026-11-13）

活動已結束，使用者指定後續 **M1–M5 全部由 M1 小魚統一負責**，涵蓋平台、導航、UI/UX、資料與陪伴功能的開發、維護、整合、測試及驗收。M2–M5 保留為技術模組名稱，原成員分工僅供歷史追溯。

本節優先於下文及其他文件中的舊分工與人員等待要求；後續不再等待 M2–M5 作業、交付、原主責確認或非作者隊員 Review。一般變更與 Level B 確認由 M1 完成本機檢查及審查記錄。遠端必要 Checks／branch protection 仍須遵守，此調整不自動更動 GitHub 權限或繞過保護。模組依賴、契約、資料來源、測試、Live 驗收及安全／隱私與外部作用授權要求繼續有效。

2026-11-08（Asia/Taipei）。採用 **LIVE-FIRST DEVELOPMENT + NO PRODUCTION MOCK**，結合 **Feature-First Development + Soft Ownership + Contract-Based Integration**，完成 [Live MVP](SAFE_WALK_LIVE_MVP.md)。新功能直接做真 Provider、正式 UI 接線與完整使用者流程，不要求先 Mock／Demo／Prototype；完整定義及規範衝突對照見 [現行交付政策](SAFE_WALK_LIVE_FIRST.md)。本規範適用五位成員及其 AI Coding 工作；M1–M5 是技術分區與主要聯絡人，不是獨占修改權。舊文件中的「所有權」「交 M1 接線」「由 M3 維護」若涉及作者權限，以本規範的三層審查為準；資料、依賴及安全限制繼續有效。

Production 僅使用真實、已完成適用驗收的資料來源與能力；Mock／Fake／fixtures 只用於隔離 Unit／Integration tests，正式入口不可選 `DataMode.mock`，既有 enum 保留相容。未完成能力顯示 Unavailable＋真實原因＋下一步，不回模擬 fallback、固定成功，不以只改文字／readiness／flags 冒充完成。其他模組 BLOCKED 不阻擋已獨立驗收的能力。main `7b99fea` 仍是 Mock 正式入口，本文件不等於程式已符合政策。

## 功能主責與主要聯絡人

所有成員都能修改 M1–M5 的合理功能檔案及相應測試，也能自行使用 AI Coding、測試、除錯、commit 與建立 PR。不按資料夾拒絕跨模組實作，不強制小魚親自寫所有接線，不要求普通跨模組修改先取得小魚批准。

功能主責對完整使用者流程、錯誤／取消、接線、測試與必要實機驗收負責，不能只交一個目錄的實作就稱功能完成。未驗部分明列，依 Readiness 如實保留 IMPLEMENTED_NOT_WIRED／WIRED_NOT_VERIFIED 等狀態。

| 技術分區 | 主要負責人／諮詢與驗收範圍 | 開發權限 |
|---|---|---|
| M1 platform／shared／官方整合 | 小魚：平台、共用契約、套件、route、原生設定、CI、composition 邊界 | 五人皆可實作；普通接線 Level A，涉及下列共用邊界則 Level B/C |
| M2 navigation | Steven：路線、OSRM、座標、RouteFollower、外部導航邏輯 | 五人皆可修改導航及跨模組流程，不另建第二份 GPS watcher |
| M3 presentation | 莅紋：正式 UI/UX 設計方向、重大改版及可用性 | 五人皆可做一般 UI／callback／狀態接線；大型 UI 改版合併前由莅紋確認 |
| M4 safety_data | 信義：來源、Parser、Repository、資料正確性／時效 | 五人皆可做資料功能與接線，保留 provenance／認可／統計限制 |
| M5 companion | 奶爸：本機 TTS／音訊、狀態、清理／中斷 | 五人皆可跨音訊、composition、通話頁與測試完成陪伴流程 |

主要負責人提供領域知識及下列必要確認，不是每個普通 PR 的固定核准者；其餘具審查權限的隊員可完成 Level A Review。這是 repo 協作規範，不自動改變 GitHub 帳號權限、branch protection 或邀請狀態。

## 三層變更審查

以實際變更內容與副作用分類，跨兩層時相關部分取較高層。可以先開發、測試與開 PR；合併／啟用門檻如下，不把「合併前確認」變成「開始前必須等批准」。

| 層級 | 範圍 | 作者／開始條件 | 合併與啟用要求 |
|---|---|---|---|
| Level A：開放修改 | 一般功能、既有契約下 UI callback／狀態接線、導航邏輯、資料轉換、音訊操作、模組／整合測試 | 任何成員可直接開始，說明跨模組目的／檔案／原主要負責人，先協調同檔案重疊 | 相關測試及必要 CI 通過，由一位具權限的非作者隊員 Review；不因跨目錄要求小魚或原模組負責人逐項先批准 |
| Level B：主要負責人確認 | 共用 Schema、Contracts、Models、依賴套件／lock、TownPass Route、原生平台設定、正式 UI 大型改版、CI/CD、重大架構邊界 | 任何成員可實作、重產及送 PR，不要求小魚親寫 | 合併前由對應主要負責人確認；共用／套件／route／原生／CI 由小魚，正式大型 UI 由莅紋，其他涉及的領域主責確認其契約影響；附相容性／生成及消費端證據 |
| Level C：隊長授權與安全驗收 | 真實警消資料發送、救援者位置通知、Supabase 身分驗證／正式唯讀權限／RPC／RLS、敏感位置儲存、正式部署／Live 啟用開關及可能造成真實外部影響的操作 | 可開發隔離實作、人工資料／fake 測試及 PR；不得自行接真實外部作用 | 合併前需隊長明確授權及額外安全／隱私審查；正式啟用前完成適用安全、後端、真實 Provider 與裝置驗收，授權範圍／證據記錄在 PR。不因編譯成功啟用 |

一般 UI constructor／callback 的接線在維持既有語意時屬 A；若改到 shared/contracts 的共用 API、wire 欄位、取消或同意契約，屬 B；若改正式外傳／啟用或敏感儲存，再屬 C。使用現有套件不等於依賴變更；新增／升版／改 lock 才納 B。一般文案／版面修補不自動算大型改版；涉及既有設計方向的大幅變更請在 PR 說明並依 B 確認。

合法導航、資料查詢、本機 TTS 及使用者主動求助入口可持續開發；當任務將觸發真實外部作用或改正式開關，才依 C 記錄對應授權／驗收。既有明確授權可沿用其有效範圍，不重複詢問已授權的同一操作；不能將開發授權推論成正式外送／部署授權。附近通知的身分、防濫用、保留刪除與官方派遣授權仍各自 BLOCKED，不藉本規範解除。

## 檔案協調與小型 PR

1. 開工先 fetch origin/main，核對開放 PR、CI、工作樹及相關新提交；功能未合併時可用 stacked PR，明列 parent PR／head SHA。父 PR 合併後改 base 至最新 main，核對差異並重新完成必要 CI，不把父 PR 的檢查當子 PR 結果。一般新功能使用短期 feature 分支，預設不直接 push main、不自行 merge。
2. 在任務／issue／PR 草稿記錄：使用者功能、功能主責、相關檔案、影響模組及原主要負責人、輸入／輸出與完成定義、測試及接收者。這是同步資訊，不是 Level A 的批准申請。
3. 同一時間盡量讓一個檔案只有一位實作者。發現重疊時，與目前實作者直接分配檔案／改動範圍或先後次序；可先做不重疊的程式與測試，不因碰到別的模組停工等待小魚。
4. 功能主責可自行完成各模組及 composition 的細小接線，不為每個 callback 另等他人開 PR。需多人平行時，以穩定契約與可測接點切分；契約變更按 B/C，不把長期分支當整合機制。
5. PR 以可審查的小型使用者功能或明確增量為範圍。若完整流程跨多 PR，列出依賴與尚未可用部分，未整合／未驗證不宣稱功能已完成。
6. 先完成 Level A/B/C 適用的 Review、測試與必要 CI，再由有權限隊員決定合併。不得為追求速度弱化測試、跳過 CI、覆寫隊員工作、force push、寫官方 upstream 或把未驗證結果寫 PASS。

每個 PR 必填：

- 完成的使用者功能與完成定義。
- 主要修改檔案、影響模組及原主要負責人。
- 新增／修改的契約；沒有則明寫無。
- 層級 A/B/C、需確認的主要負責人／隊長，以及接收審查者。
- 實際執行的命令、結果、失敗與 skip；必要 CI。
- 尚未驗證、裝置／外部依賴與後續工作。
- 是否影響 Live 可用性、外部作用或安全／隱私狀態；stacked PR 的 parent／head。

## 檔案修改權與程式依賴分開

允許 Steven 修改 platform/integration 與 presentation，不代表允許 navigation 直接 import presentation 的實作；任何人改 composition 都仍在同一依賴邊界。普通 composition 接線可由任一功能主責撰寫，不強制小魚代工。

- 業務模組保持只依賴自身與 shared；跨模組具體實作組合集中 lib/features/safe_walk/platform/integration/，保留 M1 Composition Root 機制。M1 在這裡是架構分區名稱，不是作者限制。
- 保留依賴注入，不隨意建立循環 import；shared 不反向依賴業務模組，composition 不被業務模組反向引用。
- canonical schemas/safe_walk/v1/contracts.schema.json 是 payload 單一來源，不各自建立 Position、Route、AssistancePoint 等重複 Model，不手改生成型別繞過 Schema。真正新 wire 欄位另提 Schema 變更並依 B 重產／驗消費端。
- 保留原生 TownPass 入口／route、Theme、TPColors、品牌及使用者同意。跨模組修改不授權重設官方殼；Production 不使用 Mock／fixtures，競賽正式範圍不採 Google Maps、不加入 AED。GPS 仍須主動操作，定位權限與外傳同意分開。
- tool/check_safe_walk_baseline.dart 檢查 Git 歷史、Dart import/export 及確切 composition namespace，沒有檢查 GitHub 成員身分或檔案作者權限。其 guard 與六項 module_boundary_test 保持原樣；不能為協作全面關閉。
- guard 的 --initialization 只對 migration 歷史範圍啟用保護路徑／無 UI；一般功能使用正常 guard，不把初始化限制帶回 Live 開發。現有 guard 不是完整 Dart 循環偵測器，仍要用 analyzer／相依審查與相關測試確認新增依賴；本次無程式依賴變更。

## 五人可直接承接的功能工作包

以下是可選的功能主責與接收安排，不是新的目錄分割或已宣告的檔案鎖。開工先檢查最新 main、開放 PR 與 CI，登記實際檔案與並行實作者；撞同檔案時協調先後，功能主責仍可完成後續接線。main `7b99fea` 已 restore，不能沿用 #35 曾合併推論目前已有 P0；#39 僅合入 feature branch，#44 仍開放。

| 功能／建議主責 | 相關檔案（前綴 lib/features/safe_walk/） | 完成定義／輸入輸出 | 測試標準／接收者 |
|---|---|---|---|
| 完整真實導航：Steven | platform/integration/safe_walk_composition_root.dart、safe_walk_navigation_controller.dart；navigation 的 service／follower；presentation/safe_walk_flow.dart、safe_walk_map_view.dart、safe_walk_map.dart；對應測試 | 從選／換目的地到主動 GPS、獨立第三方同意、OSRM RouteResult、真地圖、刷新／取消；錯誤不補 Demo | Adapter／Provider／Flow／取消整合與真實 Provider、iPhone 驗收；A 普通接線由具權限隊員接收；shared/deps 大型 UI 依 B 找小魚／莅紋，正式啟用依 C；先核對 #29 避免重做 |
| 目的地與 Live 錯誤操作：莅紋 | presentation 的 home／flow／map；platform/integration 導航 controller／callbacks；必要 navigation 純邏輯及測試 | 使用者可選／換目的地、重試／取消、拒絕／撤同意；geometry／距離／未知時間與狀態一致 | Widget＋controller／入口整合、無障礙與 iPhone；具權限隊員接收 A，shared 契約改動依 B；與導航主責協調 flow/map 同檔案範圍 |
| 真實據點完整查詢：信義 | safety_data 的來源／Parser／Repository；platform/integration points lookup；navigation 途經點；presentation 據點列表及測試 | 合法來源 → AssistancePoint → 查詢／途經／來源日期限制，區分失敗、無資料、未配置；不冒稱認證救援 | 解析／語意、lookup／途經／UI 整合、真來源與 iPhone；具權限隊員接收 A，模型／shared 依 B，敏感外送依 C；root 同檔案安排獨立時段 |
| 陪伴播放到 SOS 中斷：奶爸 | companion/companion_tts.dart；platform/integration 的 speaker／composition；presentation/safe_walk_call_view.dart 與 lifecycle 測試 | 劇本／本機 voice → 播放或文字預覽；停止／離開／背景／SOS 無遲到聲音，不要求麥克風 | engine／speaker／頁面競態整合與 iPhone 離線／無 voice／OS 中斷；具權限隊員接收 A，shared speaker 契約依 B；#26 已合併，從其實作續做，不重做既有修正 |
| 系統撥號／官方求助交接：小魚 | platform/townpass_platform_adapter.dart／handoff adapter、integration；presentation/safe_walk_emergency_view.dart／flow；對應測試 | 主動操作 → 系統撥號或官方入口結果，取消／失敗可理解，officialReceipt null、不稱已接通 | launcher URI／失敗／SOS 停聲整合；iPhone 只開畫面，不撥真實緊急電話或送案件；具權限隊員接收，route/native 依 B，真實外部作用／啟用依 C |

以上功能主責可以交換，任何成員也可承接其他跨模組功能；任務中要寫明接收者與層級。資料來源、地圖授權、裝置與正式啟用證據不因作者開放而省略。

## 歷史：開放協作文件分支與查核紀錄

以下至文末保留 2026-11-07 當次查核與測試事實，不是 `7b99fea` 的新驗證；其 PR 狀態也不代表現在狀態。現行交付政策見本文開頭與 [LIVE-FIRST](SAFE_WALK_LIVE_FIRST.md)。

本次先 fetch origin/main=65ee6f7dd9c07710ecf18084b1975b6998287b3e；#26 已合併。#31 當時仍開放，依其最新 head bf66fe33b06d77e61e37d52370d058b46e8444c1 建立 docs/open-collaboration，使用 stacked PR，base 指向 docs/live-mvp-spec；沒有覆寫 #31 分支。#29、#28 當時仍開放，不把未合併內容當完成。開發期間 #31 前進至 a58029fbc381f322b23a731a8545fc6f428b57d6（納入 main 65ee6f7／#26 與文件修正），本分支在首次推送前 rebase 到此最新 head；保留父分支的劇本／畫面／TTS 事實修正，沒有改寫父分支或 force push。

初次查詢時（#31 head bf66fe3），#31 Safe Walk CI success／build 執行中；#29 兩份工作流 success；#26 合併前兩份必要工作流 success；main 65ee6f7 Safe Walk CI success／build queued。這是查核快照，#31 更新 head 後必須核對其新 Checks，不能沿用舊綠燈。另有既有 PR31 review 工作樹的 presentation README 未提交修改，未接觸或重設。

本次只修改協作文件、相關規範／README 及 PR 範本，不修改 guard、Schema、生成模型、執行期旗標或功能程式，也不啟用任何 Live／通知。#31 的 SAFE_WALK_SPEC_AUDIT 與初始化歷史測試事實不改寫。執行檢查的實際結果由本 PR 描述記錄，不把上次 541 tests 或其他分支 CI 當成本次驗證。

更新 parent 後實跑：metadata、固定 lock、build_runner、Schema --check、正常 history/module guard、scoped analyze 通過；既有契約／模組邊界／TownPass 入口／整合及 TTS／通話生命週期測試 **117 通過、0 跳過**（選定範圍，非完整 suite）。28 份 Markdown 的 126 個本地連結無缺失，diff check 通過；相對 parent 無 Dart／Schema／依賴／guard／初始化歷史及顏色檔案變更。未執行真實 Provider、GPS、電話、通知或實機驗收。parent 新 head a58029f 的 Safe Walk CI success，build 查詢時仍執行中；子 PR 另看自己的 Checks。
