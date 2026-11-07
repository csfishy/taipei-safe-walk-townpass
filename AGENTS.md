# 臺北安心行 · TownPass LIVE-FIRST DEVELOPMENT

**現行強制政策：LIVE-FIRST DEVELOPMENT + NO PRODUCTION MOCK。** 後續所有開發任務以可用、真實、可操作、可驗證的完整使用者流程為交付目標，不要求先做 Mock／Demo／Prototype。統一完成定義見 [LIVE-FIRST](docs/SAFE_WALK_LIVE_FIRST.md)；歷史初始化、舊 PR／測試紀錄只供追溯，不構成現行開發禁令。

主要目標是 **Live MVP／Production Readiness**：交付真實、可驗證、可部署的功能。採 **Feature-First Development + Soft Ownership + Contract-Based Integration**。開工先讀 [協作規範](docs/SAFE_WALK_COLLABORATION.md)、[Live MVP](docs/SAFE_WALK_LIVE_MVP.md)、[Readiness](docs/SAFE_WALK_LIVE_READINESS.md)、[架構](docs/SAFE_WALK_ARCHITECTURE.md)、[Schema](docs/SAFE_WALK_SCHEMA.md)、[模組契約](docs/SAFE_WALK_MODULES.md)、[顏色規範](docs/SAFE_WALK_COLOR_SPEC.md) 及涉及模組 README。初始化文件只供歷史查證，不作為拒絕後續 Live 或跨模組開發的理由。

## 開發階段

| 階段 | 交付標準 |
|---|---|
| 測試／研究 | 可用隔離 Fake／Mock／fixtures 驗證契約與邊界；不是正式功能交付，也不是開始 Live 開發的前置階段。 |
| Integration | 依賴注入接入實際模組，驗證同意、模式、取消、錯誤及生命週期。 |
| Live MVP | 真實 Provider 完成必要測試與 iPhone 驗收，能從正式流程使用，失敗明確揭露。 |
| Production Readiness | 補足服務容量／條款、維運、監測、更新、簽署部署、隱私及安全證據。 |

盤點基準為 main `7b99fea`（#49 恢復 `3c433001` 快照後）：正式入口仍固定 Mock，屬待修正缺口，不能當作符合本政策。#35 曾交付的 Live 接線已不在此基線；開放 PR 與歷史成果不等於 main 現況。文件 PR 不改執行期，也不宣稱全產品已上線；程式接線另以 PR、實際測試及適用裝置驗收交付。

**正式 App 唯一交付路徑為 Live。** Production 使用者資料來源與操作流程不得接入 Mock Provider／Repository、DemoGeo、虛構商店／犯罪座標、模擬路線或固定成功回應；失敗不得 fallback 到 Mock。Fake／Mock／fixtures 僅限 Unit／Integration tests 與隔離測試工具，不得由正式入口選用。新功能直接完成真實 Provider、正式 UI、錯誤／取消／逾時與來源揭露的完整流程；只交 Adapter／Parser／畫面不算完成。未完成能力回 Unavailable，列實際阻塞與下一步；已符合驗收的能力不受其他 BLOCKED 模組的全域 Mock 限制。

Mock／Live 是既有 wire DataMode；保留 `mock` 僅供測試／相容性，正式入口不得選用。Unavailable 是能力／操作呈現語意，映射既有失敗契約，不因政策任意破壞 Schema／enum。Readiness 只用 IMPLEMENTED_NOT_WIRED、WIRED_NOT_VERIFIED、LIVE_VERIFIED、BLOCKED、NOT_IMPLEMENTED；改文案、固定成功、`live=true` 或改 readiness 都不能代替真實接線與驗收，測試替身不能證明 LIVE_VERIFIED。

## 功能主責與軟性所有權

- **所有成員皆可修改 M1–M5 的功能程式與相應測試**，自行 AI Coding、除錯與建立 PR；不以資料夾所有權拒絕跨模組實作，不強制小魚撰寫或事先批准普通接線。
- 功能主責對完整操作流程、錯誤／取消、跨模組接線及必要測試／實機驗收負責。開工說明目的、影響檔案／模組與原主要負責人；同檔案重疊時與實作者協調範圍／先後，不覆寫工作，也不必將所有協調集中小魚。
- **M1 小魚**：platform／shared、套件、官方 route、原生設定、CI 與 composition 的主要聯絡人。
- **M2 Steven**：導航、OSRM、RouteFollower、目的地與據點路線的主要聯絡人；位置仍由平台入口取得，不另建 GPS watcher。
- **M3 莅紋**：正式 UI/UX 設計方向與重大改版的主要負責人；一般 UI、callback、狀態與測試可由任何成員修改。
- **M4 信義**：合法資料來源、Parser、Repository、品質／時效的主要聯絡人。
- **M5 奶爸**：控制器、裝置 TTS／本機音訊、清理及中斷的主要聯絡人。
- **修改檔案與直接 import 是兩件事**。任何成員可改 composition，但跨模組具體實作組合仍限 lib/features/safe_walk/platform/integration/；業務模組只依賴自身與 shared，保留 DI，不建立循環或反向依賴。M1 指架構分區，不是限定作者。
- canonical JSON Schema 是 payload 單一來源，不手改生成 Dart Model／Schema bundle。必要新欄位另提 Schema PR，同步 generator、validator、fixtures、語意與消費模組。
- 沿用 TownPass Flutter、GetX、官方服務、Theme、TPColors、登入、品牌、原生平台及 LICENSE；入口與功能按任務最小修改，不重做官方殼、不套 Legacy React CSS。
- 依 .fvmrc 使用 Flutter 3.47.6，不任意升級 Flutter、GetX 或全部依賴。

## 三層審查與 PR

- **Level A**：一般功能、UI callback、導航邏輯、資料轉換、音訊與測試，任何成員可直接開發；相關測試及必要 CI 通過後，由一位具權限的非作者隊員 Review。普通跨模組修改不需原模組主責或小魚事前批准。
- **Level B**：共用 Schema／Contracts／Models、依賴套件／lock、TownPass Route、原生平台、正式 UI 大型改版、CI/CD／重大架構，可由任何人開發，合併前需對應主要負責人確認。共用／平台／CI 找小魚，大型 UI 找莅紋；不要求其親自修改。一般 constructor／callback 接線在維持既有語意且未涉及 B/C 範圍時屬 A；共用契約、依賴／lock、TownPass route、原生設定、CI 等變更仍依 B，不能以普通接線降級。
- **Level C**：真實警消發送、救援者位置通知、Supabase 身分／RPC／RLS、敏感位置儲存、正式部署／Live 開關及真實外部作用。可做隔離實作／測試；合併需隊長明確授權與安全／隱私審查，啟用前完成必要驗收，不以編譯成功啟用。既有明確授權在有效範圍內沿用。
- 小型功能 PR 列使用者功能、完成定義、主要檔案、影響模組／原主責、契約變更、A/B/C、實際測試／skip、未驗部分及 Live／安全影響。完整流程可分增量，但不能把未接線／未驗部分宣稱完成。接收者與檔案協調見 [協作規範](docs/SAFE_WALK_COLLABORATION.md)。

## 安全與誠實要求

- GPS 由使用者主動啟動導航／更新位置觸發，使用 TownPass 原生服務。定位權限與第三方查詢同意分開；不得自動追蹤、外傳或以示範座標補定位失敗。
- 真實步行 Provider 顯示 geometry、距離、可取得的時間與限制。OSRM 路網不代表已驗證的安全路線。
- 競賽導航使用 App 內 OSM／合法路網與 OSRM；不得以 Google Maps 外連作為正式導航交付。不得新增 AED 功能。
- Live 不顯示 DemoGeo、虛構避險件數、模擬 ETA／地標；查詢失敗、無資料與未配置可區分。
- 保留來源、取得／更新日期及限制。AED／便利商店不能直接當政府認證救援據點；全市／行政區歷史統計不能冒充即時道路風險。
- 持久犯罪參考資料庫與 CI／Demo reset 隔離；App 只透過授權、受限、經審查的唯讀介面取得合法公開資訊，不能持有 service_role／管理金鑰／DB 密碼。模糊地址與參考座標不是精確案發點，無可信範圍與路線比較證據不得宣稱避讓完成。
- 附近協助者通知需可信身分、接收資格、ownership、RLS/RPC、限流／防濫用、位置保留／刪除、明確同意與後端／裝置驗證；未完成維持 BLOCKED，匿名 UUID 不得開放陌生人位置通知。
- 無官方授權不得自動送警消案件、派遣或杜撰受理編號；officialReceipt 保持 null。這不阻擋導航、查詢、TTS 或使用者主動開啟 110／119 系統撥號器及官方通報入口。
- 開啟撥號器不等於電話接通，開啟外部管道不等於受理。測試不撥真實緊急號碼、不發真實通報。
- 模擬陪伴使用裝置 TTS／核准本機音訊，不要求麥克風；無引擎顯示文字預覽，不冒稱真人、警察接聽或已派遣。停止、離開、背景及 SOS 中斷音訊、計時器與遲到工作。
- 不提交 secrets、憑證、Token、真實位置紀錄、住家或聯絡人，不要求在對話貼 Token。測試／截圖使用人工位置並說明證據限制。

## Git、審查與驗證

- **北北基犯罪參考資料庫是持久資料，不是 Demo seed。** 使用者指定既有 Supabase 專案的獨立 private `crime_reference` schema；保持 RLS 啟用、不授予 `anon`／`authenticated` 直接存取，不新增公開 RPC 或把憑證放進 App／CI。來源、原始位置文字、定位依據與精度必須保留；參考位置不等於精確犯罪發生點。
- **build、CI、App 啟動、測試資料初始化及 Demo reset 絕不得 import、seed、update、delete、truncate、drop 或重建 `crime_reference`。** PR #40 的 `safe_walk_demo` 與此資料隔離，不擴大 Demo reset 範圍。任何資料更新只准明確授權的可信手動匯入，以新 snapshot version 新增並驗證，不能覆蓋或重置既有版本。受控 SQL 僅放 `supabase/crime_reference/`，不能由 workflow 呼叫；資料庫權限／匯入仍依 Level C 審查。
- 本機 SQLite 僅供唯讀離線備份與匯出，實體檔放在所有 Git checkout／worktree **之外**，不可加入 assets、Git、Web ZIP、APK、IPA 或 release。新增版本只准明確 `import-new --allow-write`，不得覆寫既有檔；CI 禁止匯入。讀取／匯出使用 `mode=ro`，不得將 guard 接到真資料庫。操作與驗證見 [犯罪資料庫隔離](docs/SAFE_WALK_CRIME_DATABASE.md)。

- 先 fetch 最新團隊 origin/main，核對工作樹、未合併 PR 與 CI；新功能預設短期任務分支，依賴未合併成果時從 parent 最新 head 建 stacked 分支並明列 base／SHA，不把它寫成 main 成果、不覆寫 parent。
- upstream 只讀；push 明確指定團隊 origin。不 force push、不刪／重設隊員分支、不 reset／clean 他人工作、不擅自關 PR、移動 tag、自動 merge 或發布。
- 保留 Legacy Repo／歷史成果；五模組分支已建立，不再要求重跑初始化或等待「五分支建立」。
- PR 附準確 SHA、理由、實際驗證及未驗事項。按變更跑 metadata、lock、build_runner、Schema --check、正常 module guard、analyze／test 及適用 build。文件 PR 至少驗連結、文件一致性、Schema 與模組契約，既有 CI 仍適用。
- --initialization 禁止 UI guard 僅用於歷史 migration，不阻擋正常 UI／Live／跨模組開發。正常 guard 檢查依賴而非 GitHub 成員修改權，保留程式與必要 CI，不以停用 guard 開放協作。
- 未執行、失敗、跳過分開回報，不寫 PASS；CI build／Mock 測試不等於真實 Provider／iPhone 驗收，Windows 不宣稱本機編譯 iOS。

初始化時「不建立 UI」「只允許抽象介面」「五分支 pending」與當時測試結果保留於 [初始化歷史紀錄](docs/SAFE_WALK_INITIALIZATION.md)，不再是持續開發限制。
