# 臺北安心行 · TownPass 持續開發規範

主要目標是 **Live MVP／Production Readiness**：交付真實、可驗證、可部署的功能。開工先讀 [Live MVP](docs/SAFE_WALK_LIVE_MVP.md)、[Readiness](docs/SAFE_WALK_LIVE_READINESS.md)、[架構](docs/SAFE_WALK_ARCHITECTURE.md)、[Schema](docs/SAFE_WALK_SCHEMA.md)、[模組契約](docs/SAFE_WALK_MODULES.md)、[顏色規範](docs/SAFE_WALK_COLOR_SPEC.md) 及所屬模組 README。初始化文件只供歷史查證，不作為拒絕後續 Live 開發的理由。

## 開發階段

| 階段 | 交付標準 |
|---|---|
| Prototype | 清楚標示的 Mock／Fake 驗證操作與契約，不宣稱正式功能完成。 |
| Integration | 依賴注入接入實際模組，驗證同意、模式、取消、錯誤及生命週期。 |
| Live MVP | 真實 Provider 完成必要測試與 iPhone 驗收，能從正式流程使用，失敗明確揭露。 |
| Production Readiness | 補足服務容量／條款、維運、監測、更新、簽署部署、隱私及安全證據。 |

目前 App 保留 Demo 與部分真實能力，逐能力推進 Integration → Live MVP；不宣稱全產品已可正式上線。本次規格 PR 不開啟未驗證功能。

**Mock 僅作為測試與未驗證功能的隔離模式。正式功能完成相應驗收後，必須能透過正式操作流程使用 Live Provider。** Development 可用 Mock；公開版本優先提供已驗證的 Live 能力，不用全域 Mock 永久封鎖全部產品。各能力分開驗收、啟用及撤回；未完成能力回清楚的 Unavailable，不暗中回 Mock 假成功。

Mock／Live 是既有 wire DataMode；Unavailable 是能力／操作呈現語意，映射既有失敗契約，不新增 Schema enum。Readiness 狀態只用 IMPLEMENTED_NOT_WIRED、WIRED_NOT_VERIFIED、LIVE_VERIFIED、BLOCKED、NOT_IMPLEMENTED；Mock unit test 不能證明 LIVE_VERIFIED。

## 五模組所有權

- **M1 小魚**：platform、shared contracts/models、pubspec/lock、官方入口／route、平台設定、CI 與跨模組接線。
- **M2 Steven**：navigation、RouteService／OSRM、RouteFollower、目的地與據點路線邏輯；消費 M1 位置，不註冊第二份 GPS 監聽，不接管地圖 UI。
- **M3 莅紋**：presentation，正式 UI/UX 唯一設計負責人；維護現有畫面、Live 底圖／投影與狀態呈現。
- **M4 信義**：safety_data，合法來源、Parser、Repository、來源／更新／限制及測試資料。
- **M5 奶爸**：companion，控制器、裝置 TTS／核准本機音訊、取消與中斷；通話頁由 M3 維護。
- 業務模組只依賴自身與 shared；跨模組實作組合限 M1 的 lib/features/safe_walk/platform/integration/。跨模組變更由 M1 協調並記錄契約影響，UI 與 M3 協作。
- canonical JSON Schema 是 payload 單一來源，不手改生成 Dart Model／Schema bundle。必要新欄位另提 Schema PR，同步 generator、validator、fixtures、語意與消費模組。
- 沿用 TownPass Flutter、GetX、官方服務、Theme、TPColors、登入、品牌、原生平台及 LICENSE；入口與功能按任務最小修改，不重做官方殼、不套 Legacy React CSS。
- 依 .fvmrc 使用 Flutter 3.47.6，不任意升級 Flutter、GetX 或全部依賴。

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

- 從最新團隊 origin/main 建任務分支，先核對工作樹、未合併 PR 與 CI；不把未合併分支寫成 main 現況。
- upstream 只讀；push 明確指定團隊 origin。不 force push、不刪／重設隊員分支、不 reset／clean 他人工作、不擅自關 PR、移動 tag、自動 merge 或發布。
- 保留 Legacy Repo／歷史成果；五模組分支已建立，不再要求重跑初始化或等待「五分支建立」。
- PR 附準確 SHA、理由、實際驗證及未驗事項。按變更跑 metadata、lock、build_runner、Schema --check、正常 module guard、analyze／test 及適用 build。文件 PR 至少驗連結、文件一致性、Schema 與模組契約，既有 CI 仍適用。
- --initialization 禁止 UI guard 僅用於歷史 migration，不阻擋已授權 UI／Live 開發。M3 可持續設計，M2/M5 可實作具體 Provider／引擎。
- 未執行、失敗、跳過分開回報，不寫 PASS；CI build／Mock 測試不等於真實 Provider／iPhone 驗收，Windows 不宣稱本機編譯 iOS。

初始化時「不建立 UI」「只允許抽象介面」「五分支 pending」與當時測試結果保留於 [初始化歷史紀錄](docs/SAFE_WALK_INITIALIZATION.md)，不再是持續開發限制。
