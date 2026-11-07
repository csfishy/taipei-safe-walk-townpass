# 臺北安心行：Prototype → Live MVP 規格逐項審查

日期：2026-11-07（Asia/Taipei）。本報告比較 **已 fetch 的團隊 main 程式／測試**與全部版控 Markdown，不只依 README 判斷。本次只調整文件，不修改程式、Schema、常數、套件、UI 設計或外部通知；現行規格以 [Live MVP](SAFE_WALK_LIVE_MVP.md) 為準。

> 審查更新（2026-11-07）：PR #26 已合併至 main `65ee6f7dd9c07710ecf18084b1975b6998287b3e`，統一 speaker lifecycle 修正與回歸已進主線，仍缺實際 iPhone 驗收。下列 `03f98f2` 的 PR／CI 快照與 541 通過、17 跳過是原盤點事實，保留不改寫；本增量註記不宣告重跑或 LIVE_VERIFIED。R9 與 P1-C 的現行後續工作已更新，#28／#29 仍未合併，不計入主線完成。

## 基線、PR 與工作樹

起初本機 main c765f471866de85908fef9bce3a673ea491a16f4，工作樹乾淨，落後當時 origin/main 42 commits。先 fetch 得 0ea99798b130cfba10358b9f47c287b93d06b275，再於獨立 worktree／docs/live-mvp-spec 分支作業。審查中 #27 合併，再 fetch 並 fast-forward 到 **03f98f2b7b5254db73774c4d097eb4d610499c2c**，納入新增的兩個 Dart 測試入口檔與一個測試檔，重跑相關驗證。未切換或重設其他工作樹。

已檢查 git worktree list 的全部 21 個 worktree（含本次）；檢查時只有本次文件工作樹有未提交修改，其他工作樹無未提交變更。main 保留原分支狀態。origin 指向 csfishy/taipei-safe-walk-townpass，官方 upstream 只讀，未寫入、force push、刪分支、關 PR、移動 tag 或自動 merge。

| PR／範圍 | 本次核對狀態及證據用途 |
|---|---|
| #10／#14／#15／#16 | M2 service／真實步行／同意取消修正／M1 導航 scope 已合併；不能再寫只有抽象 RouteService。 |
| #17／#24 | M3 畫面／路線 API／通話與狀態已合併；不能再寫 presentation 只有 README 或沒有畫面。 |
| #18／#20 | RouteFollower／最近店家 planner 與外部導航 URI 已合併；正式 App 尚未消費。 |
| #19 | 真實全市月別犯罪 Repository 已合併，未接 UI；不等於行政區或路段風險模型。 |
| #21／#25／#27 | 附近 service／SQL、Supabase 連線、獨立測試頁已合併；匿名 RPC 安全條件不足，正式通知仍 BLOCKED。 |
| #22／#23 | 本機 TTS 與劇本已合併，M1 已接 speaker；缺真實 iPhone 證據。 |
| [#26](https://github.com/csfishy/taipei-safe-walk-townpass/pull/26) | 未合併，head f919e6218546a2572219d81abb7fc80d5e28c37c，統一 speaker lifecycle；main 已有部分 late readiness／背景保護，不把整個修正視為不存在。 |
| [#28](https://github.com/csfishy/taipei-safe-walk-townpass/pull/28) | 未合併，head 54367d8177ed023d7a498afbfefb990aa2ba52d8，知識圖譜是另一份文件工作，不納入主線盤點。 |
| [#29](https://github.com/csfishy/taipei-safe-walk-townpass/pull/29) | 未合併，head 04efda76559a4ea01dedb01b7ba980d9e00ec03b，OSM 圖磚／套件提案；主線仍 DemoMap，不把提案當真地圖已驗收。後續 P0-C 應先審其可重用範圍，避免重複實作或覆寫。 |

CI 快照：main 03f98f2 的 [Safe Walk CI](https://github.com/csfishy/taipei-safe-walk-townpass/actions/runs/42375781565) 及 [check-and-build](https://github.com/csfishy/taipei-safe-walk-townpass/actions/runs/42375781594) 查詢時仍執行中。#26 最新 [Safe Walk CI](https://github.com/csfishy/taipei-safe-walk-townpass/actions/runs/42375674752)／[build](https://github.com/csfishy/taipei-safe-walk-townpass/actions/runs/42375674759) 執行中；#28 [Safe Walk CI](https://github.com/csfishy/taipei-safe-walk-townpass/actions/runs/42375462189) success、[build](https://github.com/csfishy/taipei-safe-walk-townpass/actions/runs/42375462226) 執行中；#29 [Safe Walk CI](https://github.com/csfishy/taipei-safe-walk-townpass/actions/runs/42375672356)／[build](https://github.com/csfishy/taipei-safe-walk-townpass/actions/runs/42375672381) 執行中。這是查詢時快照，後續依連結實際結果；不把其他 SHA 的綠燈或工作流存在當作通過。

## 全部 Markdown 逐項對照

基線 git ls-files '*.md' 共 **23 份**，包含隱藏 .github 範本；本次新增四份 Live 文件後共 27 份。全庫搜尋 Mock／Fake／Demo／Live／不可／不得／尚未／待配置／pending／初始化，並核對 lib、test、tool、workflow、supabase；第三方 SDK／cache 不屬 repository 版控規格。

分類：「初始化」是一次性範圍；「安全」持續有效；「過時」為程式已進展；「阻開發」可能錯誤拒絕正式實作；「接線」是功能已存在但不可從正式流程使用。表中的原規範為修改前摘要，完整原文可由基線 SHA 查閱。

| 檔案 | 原規範／狀態 | 目前程式及測試 | 保留／修改理由 | 新規範 |
|---|---|---|---|---|
| AGENTS.md：階段 | M1 入口本輪、預設 Mock、真實撥號關閉 | root 已有 OSRM／TTS，仍硬編 Mock；不是完全無實作 | 初始化／阻開發；不能永久以本輪預設限制產品 | 四階段、逐能力驗收，已驗證 Live 必須正常流程可達；本 PR 不開旗標 |
| AGENTS.md：UI／抽象／分支 | 不建 UI、M3 僅 README、M5 不建通話頁、五分支 pending | presentation 多個 Widget／route、TTS／控制器與五分支已存在 | 初始化／過時；錯用會拒絕具體功能 | 移為歷史說明；M3 可持續維護，M2/M5 可做具體 Provider／引擎 |
| AGENTS.md：治理 | 五模組所有權、M3 設計、DI／Schema、位置隱私、官方授權、PR／CI／upstream | module_boundary_test、Schema／semantics 及 guard 保留 | 安全；解除 Prototype 不等於刪安全 | 保留並補通知身分／ownership／防濫用；禁止假受理及 Mock fallback |
| README.md | 以示範畫面交付、先用 Mock、真功能待交付 | OSRM／follower／OSM／crime／TTS／Supabase 已合併，各自接線程度不同 | 過時／接線 | 主要目標 Live MVP，列精確實作及缺口，連規格／readiness／計畫 |
| docs/SAFE_WALK_ARCHITECTURE.md | 初始化 PR 待合併、不新增 route／入口／UI／資料庫 | TownPass 原生入口、Flow、Supabase 已存在 | 初始化／阻開發／過時 | 持續架構、現存資料流與真實 GPS→OSRM→UI 目標；保留原生殼及 DI |
| docs/SAFE_WALK_INITIALIZATION.md | pending 五分支、M3 無 UI、舊 119 tests 等 | 是當時記錄，現況不同 | 初始化；歷史測試事實不可改寫 | 只在開頭加入歷史導引，原本文字與測試事實原樣保留 |
| docs/SAFE_WALK_MODULES.md：M1/M2 | 第一輪契約／Mock，M2 無具體 Provider | Adapter、DefaultRouteService／OSRM／Follower／planner 已存在 | 過時／接線 | 具體實作與輸入輸出、同意／模式／取消，M1 正式接線責任 |
| docs/SAFE_WALK_MODULES.md：M3/M5 | M3 只有 README，具體控制器／音訊仍待交付 | Flow／Call、LocalCompanionController／CompanionTtsSpeaker 及 root device speaker 已存在 | 過時／阻開發 | M3 設計權不變；TTS 已接但未實機，資產播放器另缺 |
| docs/SAFE_WALK_SCHEMA.md | strict／nullable／mock-live／官方回執；音檔「未來映射」 | canonical v1、generator／validator／semantics 已用於所有模組；已有 allow-list 接點 | 安全保留；音訊狀態與歷史驗證指向小修 | 不變更 JSON／產物；Unavailable 不增 enum；新 payload 才獨立 Schema PR |
| docs/SAFE_WALK_INTEGRATION.md | M2 只有抽象、M4 分支未合、M5 available 固定 false、無 lifecycle observer | root 建 OSRM、WidgetsBindingObserver、TTS；crime 已合併，但 Mock points 仍在 | 過時／接線；早期測試不能代表當前 | 以目前程式重寫狀態、接線／iPhone 交付與逐能力解除條件 |
| docs/SAFE_WALK_NAVIGATION_PRESENTATION_CONTRACT.md | M3 API 未合、初始化 post-frame、PiP 等待接線 | Flow 已有 route/routeLoading/onPlanRoute，_go(map) 才觸發；通話已無地圖 | 過時／接線 | 保留現有 API，M1 adapter 接 scope／callbacks；補同意、取消、真地圖／未知時間 |
| docs/SAFE_WALK_COLOR_SPEC.md | TPColors、配對、M3 設計權 | color_spec_test、官方色值來源仍適用 | 安全／設計；無需更改 | **完全不修改**，不以本次規格重設設計 |
| docs/SAFE_WALK_SUPABASE.md | 本輪分支／本機診斷；通知 SQL 未部署 | #25 已合，#27 新測試頁亦合；probe 只到 Data API，未驗通知權限 | 過時／安全；連通不等於授權 | 保存原診斷／測試事實，標明已合併、測試頁隔離及正式通知 BLOCKED |
| platform/README.md | 先 Mock、真求助未配置、第一輪工作 | 真 GPS Adapter 存在、root Mock；emergency adapter 仍不執行 handoff | 接線／過時 | 保留 GPS 主動及失敗保護；安排合法撥號／官方入口，與通知派遣分開 |
| navigation/README.md | 先用 Fake／第一輪、正式 provider 規劃 | 具體 OSRM、RouteFollower、OSM、planner、Google link 與 tests 已有 | 阻開發／過時／接線 | 清楚區分已實作與尚未 App 接線；真服務與 iPhone 證據後啟用 |
| presentation/README.md | Mock 交付、無音訊、待 M2 API | Flow 已有路線 API，TTS 已接；DemoMap／DemoGeo 及估時仍存在 | 過時／接線 | 保留設計／色彩與 Demo，加入真實底圖／投影、狀態、同意及 Live 無假資料驗收 |
| safety_data/README.md | 真來源尚未接入、分支 pending | Parser／Mock repo 及真 crime repo 已合，但無正式據點 repo | 過時／接線 | 真據點 NOT_IMPLEMENTED、crime IMPLEMENTED_NOT_WIRED；不能概稱所有來源未做 |
| safety_data/violent_crime/README.md | 真來源、舊 Node 驗證 | Dart Repository／normalizer 與 fake fetch 測試已存在，未接 App | 接線／安全；舊來源測試不等於 App | 保留舊測試事實，明列全市月別、Dart fetch／UI／實機缺口 |
| companion/README.md | 純狀態／契約、M3 UI 未完成 | 本機 flutter_tts、speaker、通話 UI 已合；資產播放器未完成 | 過時／阻開發 | TTS WIRED_NOT_VERIFIED；無麥克風、文字預覽、背景／SOS 等驗收保留 |
| docs/SAFE_WALK_CI.md | 嚴格範圍對應無 UI 初始化，新工作流未執行 | workflow scoped 包含 M3；migration 才 --initialization，build gate 已存在 | 初始化／過時；不能錯用 guard 阻擋 UI | 明標歷史段落與目前 gate，完整測試／skip 如實，CI 不等於 Live |
| docs/BUILDS.md | builds／prerelease／Pages 與 unsigned 安裝限制 | 與 build.yml 一致，PR 只 artifacts、main 成功才發布 | 仍有效；部署不代表能力驗收 | 保留並導向 Live 規格／readiness，不把 Demo preview 當產品永久規範 |
| docs/PRERELEASE-NOTES.md | preview／未簽章／裝置待驗 | 與打包／安裝限制一致 | 安全；不可誇大 | 保留安裝限制，新增逐能力驗收導引 |
| docs/SAFE_WALK_COMPETITION_LICENSE.md | 初始化未改 UI／建網站、規則與授權待確認 | 已有原生入口／Web build，但文件是日期化證據 | 初始化／安全；不可把舊工作範圍當禁令或改寫授權事實 | 加歷史範圍導引，原授權與交付待確認證據保留 |
| .github/pull_request_template.md | 先建對應 issue、PR 範圍與 checklist | 適用本次文件 PR | 有效協作 | 不修改；先建規格轉換 issue 再建立 PR |
| CODE_OF_CONDUCT.md | 協作行為準則 | 無 Prototype／Live 能力限制 | 有效且不相關 | 不修改 |
| ios/Runner/Assets.xcassets/LaunchImage.imageset/README.md | 官方 LaunchImage 素材操作 | 無 Mock／Live 限制 | 官方資產說明 | 不修改 |

本表模組 README 路徑前綴為 lib/features/safe_walk/。新增 SAFE_WALK_LIVE_MVP.md（正式驗收）、SAFE_WALK_LIVE_READINESS.md（14 能力與閘門）、SAFE_WALK_LIVE_PLAN.md（檔案／契約／標準／測試／Owner／依賴與首個提示詞）及本報告。

## 阻止目前開啟 Live 導航的實際程式

以下行號對應上述 main 快照；本次文件 PR 不改動這些程式。

| 程式 | 目前效果與修改原因 |
|---|---|
| platform/integration/safe_walk_composition_root.dart:97–111 | 建構 OSRM，但 controller mode=mock、livePresentationReady=false、liveProviderReady=false，不能只因實例存在就稱可用 |
| 同檔 :65、:130–142、:293–328 | _navigationActive 起始 false，scope 有 opened/closed 等 callbacks，但 Flow 不讀 scope；root 只傳 mode/points/speaker/locate/emergency/exit，未傳 route/routeLoading/onPlanRoute |
| 同檔 :206、:213、:238、:279、:316 | 據點／定位／求助／Flow 各固定 Mock，且拒絕 Live points；只改 controller 留下模式混用 |
| platform/integration/safe_walk_navigation_controller.dart:95–105 | Live readiness／routing consent 不足拒絕規劃；此保護須保留，由真接線與證據解除 |
| presentation/safe_walk_flow.dart:75–101 | 無位置／據點可補 DemoGeo／示範資料，Live 需分流；現有 API 未包含完整同意／取消／錯誤／lifecycle 操作 |
| presentation/safe_walk_map_view.dart:51–55、:116、:171–177 | 未知 duration 以 walkMinutes 補；據點 L 形線及缺位置 DemoGeo，不可當真路線／ETA |
| presentation/demo_map.dart:19–20、:113 | 固定示範投影／標記，無真實底圖；未合併 #29 須另審 |
| navigation/route_follower.dart | 實作及測試存在，App 無 production consumer；不能宣稱已跟隨真 GPS |

真正「已完成實作但未能從 App 使用」包含：TownPass GPS seam、OSRM 真實查詢（已建構但 UI／模式封鎖）、RouteFollower、OSM source、NearestStorePlanner、Google walking URI、全市 crime Repository。TTS 是已接線待驗，不能放入「未接 App」清單；Supabase CLI 是連線診斷，不能當正式通知。

## 必須保留的安全與品質條件

五模組所有權／DI、M3 設計權、Schema 單一來源／strict／nullable／語意；主動定位、分離用途同意、資料來源／模式／日期正確；無 Mock 假成功；模擬陪伴誠實與中斷；officialReceipt null／官方派遣授權；附近通知身分／ownership／RLS/RPC／限流／保留刪除／後端裝置驗證；不測真緊急通報、不提交個資憑證；PR／CI／實機證據與 upstream 只讀均保留。

## 本次驗證與交付

以下為本次實際驗證結果；命令／測試檔存在不當 PASS。完整 suite 預設跳過真實服務及 opt-in 截圖，不為文件變更啟動 GPS、通知 RPC、真實服務 smoke 或緊急電話。Runtime 未修改，Live 驗收證據仍依各能力列為缺少。

| 檢查 | 實際結果 |
|---|---|
| 最新 main／全部工作樹／未合併 PR／CI | 已核對；main 03f98f2，未合併 #26/#28/#29，CI 快照如上 |
| metadata、固定 lock、build_runner | PASS；metadata source=03f98f2，Flutter 3.47.6，offline pub get --enforce-lockfile；最新基線 build_runner exit 0（17 秒、1 output），lock 無變動 |
| Schema --check／正常 history/module guard | PASS，exit 0；未套用歷史 --initialization 禁止 UI guard |
| scoped analyze／完整 Flutter tests | PASS：scoped No issues found；完整 suite 541 通過、17 跳過（14 opt-in 截圖、3 真實 Provider smoke）；含 #27 新測試，exit 0 |
| 完整 analyze --no-pub --no-fatal-infos | exit 0；17 項既有官方 style info，0 warning／error；不是零診斷，不宣稱預設 fatal-infos analyze 通過 |
| 全 Markdown 本地連結／一致性／diff | PASS：27 Markdown、107 本地連結無遺失目標、git diff --check；已核對初始化只新增 banner，顏色／Schema／程式／依賴無變動，23 個變更全為 Markdown |
| 真實 Provider／iPhone／原生 build | 本次不執行；Windows 不宣稱 iOS build，不能標 LIVE_VERIFIED |

PR URL、最終 commit SHA 與相同 SHA 的 CI 結果記於 PR／交付回報；不把最終 SHA 寫回自身檔案形成循環。後續 P0–P2 五人分工及第一個可直接交 Codex 的實作提示詞見 [工程計畫](SAFE_WALK_LIVE_PLAN.md)。
