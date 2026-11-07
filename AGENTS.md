# 臺北安心行 · TownPass 持續開發規範

主要目標是 **Live MVP／Production Readiness**：交付真實、可驗證、可部署的功能。採 **Feature-First Development + Soft Ownership + Contract-Based Integration**。開工先讀 [協作規範](docs/SAFE_WALK_COLLABORATION.md)、[Live MVP](docs/SAFE_WALK_LIVE_MVP.md)、[Readiness](docs/SAFE_WALK_LIVE_READINESS.md)、[架構](docs/SAFE_WALK_ARCHITECTURE.md)、[Schema](docs/SAFE_WALK_SCHEMA.md)、[模組契約](docs/SAFE_WALK_MODULES.md)、[顏色規範](docs/SAFE_WALK_COLOR_SPEC.md) 及涉及模組 README。初始化文件只供歷史查證，不作為拒絕後續 Live 或跨模組開發的理由。

## 開發階段

| 階段 | 交付標準 |
|---|---|
| Prototype | 清楚標示的 Mock／Fake 驗證操作與契約，不宣稱正式功能完成。 |
| Integration | 依賴注入接入實際模組，驗證同意、模式、取消、錯誤及生命週期。 |
| Live MVP | 真實 Provider 完成必要測試與 iPhone 驗收，能從正式流程使用，失敗明確揭露。 |
| Production Readiness | 補足服務容量／條款、維運、監測、更新、簽署部署、隱私及安全證據。 |

目前 App 保留顯式 Mock 與部分真實能力，逐能力推進 Integration → Live MVP。P0 已在本工作分支接入正常入口的受控真實步行預覽：兩份同意、明確單次 GPS、OSRM 與真地圖，狀態為 WIRED_NOT_VERIFIED；未完成 iPhone／部署驗收，不宣稱 LIVE_VERIFIED 或全產品正式上線。操作、外傳與本輪證據見 [P0 Live 預覽](docs/SAFE_WALK_P0_LIVE_PREVIEW.md)；既有文件明列舊 SHA 的 Mock 盤點是歷史快照。

**Mock 僅作為測試與未驗證功能的隔離模式。正式功能完成相應驗收後，必須能透過正式操作流程使用 Live Provider。** Development 可用 Mock；公開版本優先提供已驗證的 Live 能力，不用全域 Mock 永久封鎖全部產品。各能力分開驗收、啟用及撤回；未完成能力回清楚的 Unavailable，不暗中回 Mock 假成功。

Mock／Live 是既有 wire DataMode；Unavailable 是能力／操作呈現語意，映射既有失敗契約，不新增 Schema enum。Readiness 狀態只用 IMPLEMENTED_NOT_WIRED、WIRED_NOT_VERIFIED、LIVE_VERIFIED、BLOCKED、NOT_IMPLEMENTED；Mock unit test 不能證明 LIVE_VERIFIED。

## 功能主責與軟性所有權

- **所有成員皆可修改 M1–M5 的功能程式與相應測試**，自行 AI Coding、除錯與建立 PR；不以資料夾所有權拒絕跨模組實作，不強制小魚撰寫或事先批准普通接線。
- 功能主責對完整操作流程、錯誤／取消、跨模組接線及必要測試／實機驗收負責。開工說明目的、影響檔案／模組與原主要負責人；同檔案重疊時與實作者協調範圍／先後，不覆寫工作，也不必將所有協調集中小魚。
- **M1 小魚**：platform／shared、套件、官方 route、原生設定、CI 與 composition 的主要聯絡人。
- **M2 Steven**：導航、OSRM、RouteFollower、目的地與據點路線的主要聯絡人；位置仍由平台入口取得，不另建 GPS watcher。
- **M3 莅紋**：正式 UI/UX 設計方向與重大改版的主要負責人；一般 UI、callback、狀態與測試可由任何成員修改。
- **M4 信義**：官方犯罪警示來源、地理化可信度、可參與避讓的警示範圍與資料品質／時效之主要聯絡人。本輪取消 AED 開發；全市暴力犯罪月統計只作歷史趨勢，不進逐路段避讓。
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
- Live 不顯示 DemoGeo、虛構避險件數、模擬 ETA／地標；查詢失敗、無資料與未配置可區分。
- 保留來源、取得／更新日期及限制。AED／便利商店不能直接當政府認證救援據點；全市／行政區歷史統計不能冒充即時道路風險。
- 附近協助者通知需可信身分、接收資格、ownership、RLS/RPC、限流／防濫用、位置保留／刪除、明確同意與後端／裝置驗證；未完成維持 BLOCKED，匿名 UUID 不得開放陌生人位置通知。
- 無官方授權不得自動送警消案件、派遣或杜撰受理編號；officialReceipt 保持 null。這不阻擋導航、查詢、TTS 或使用者主動開啟 110／119 系統撥號器及官方通報入口。
- 開啟撥號器不等於電話接通，開啟外部管道不等於受理。測試不撥真實緊急號碼、不發真實通報。
- 模擬陪伴使用裝置 TTS／核准本機音訊，不要求麥克風；無引擎顯示文字預覽，不冒稱真人、警察接聽或已派遣。停止、離開、背景及 SOS 中斷音訊、計時器與遲到工作。
- 不提交 secrets、憑證、Token、真實位置紀錄、住家或聯絡人，不要求在對話貼 Token。測試／截圖使用人工位置並說明證據限制。

## Git、審查與驗證

- 先 fetch 最新團隊 origin/main，核對工作樹、未合併 PR 與 CI；新功能預設短期任務分支，依賴未合併成果時從 parent 最新 head 建 stacked 分支並明列 base／SHA，不把它寫成 main 成果、不覆寫 parent。
- upstream 只讀；push 明確指定團隊 origin。不 force push、不刪／重設隊員分支、不 reset／clean 他人工作、不擅自關 PR、移動 tag、自動 merge 或發布。
- 保留 Legacy Repo／歷史成果；五模組分支已建立，不再要求重跑初始化或等待「五分支建立」。
- PR 附準確 SHA、理由、實際驗證及未驗事項。按變更跑 metadata、lock、build_runner、Schema --check、正常 module guard、analyze／test 及適用 build。文件 PR 至少驗連結、文件一致性、Schema 與模組契約，既有 CI 仍適用。
- --initialization 禁止 UI guard 僅用於歷史 migration，不阻擋正常 UI／Live／跨模組開發。正常 guard 檢查依賴而非 GitHub 成員修改權，保留程式與必要 CI，不以停用 guard 開放協作。
- 未執行、失敗、跳過分開回報，不寫 PASS；CI build／Mock 測試不等於真實 Provider／iPhone 驗收，Windows 不宣稱本機編譯 iOS。

初始化時「不建立 UI」「只允許抽象介面」「五分支 pending」與當時測試結果保留於 [初始化歷史紀錄](docs/SAFE_WALK_INITIALIZATION.md)，不再是持續開發限制。
