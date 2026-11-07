# LIVE-FIRST DEVELOPMENT／NO PRODUCTION MOCK

2026-11-08（Asia/Taipei）。本文件是目前開發與正式交付政策。新功能直接完成真實 Provider、正式 UI 接線與完整使用者流程，不要求先交 Mock、Demo 或 Prototype。Fake、Mock 與人工 fixtures 只供 Unit／Integration tests 的隔離與可重現驗證，不是正式能力的替代品。

## 適用範圍與目前基線

本次文件修正基於團隊 main `7b99fea`。PR #49 已 restore 至 `3c433001` 快照，先前 PR #35 的 P0 正式接線已不在目前 main 檔案狀態；不能僅憑 Git 歷史曾合併就宣稱現在有 Live 操作流程。main 的安心行正式入口仍使用 Mock，這是待修的現況，與本政策不相符；文件 PR 不會自行完成或驗證執行期改造。

PR #39 合入 feature branch，並非目前 main；PR #44 仍開放。未合併分支、未來 Phase B 程式修改與本文件的完成定義都不能列為 main 已完成功能。正式持久資料以 Supabase 主資料庫為整合方向，#44 的資料方案須另完成審查、正式接線與驗收，不能以這項方向宣稱已有安全後端或擅自啟用權限。

審查更新：#53 附近真實場所服務及 #55 犯罪唯讀 Repository／RPC SQL 已合併；仍未等同正式 UI／真後端或裝置驗收，不重新把已實作能力列為 NOT_IMPLEMENTED。

本階段只修文件與規範，以獨立 PR 審查，不修改 flags、Provider、Schema、RPC/RLS、Secrets 或遠端資料。逐項程式缺口見 [正式接線盤點](SAFE_WALK_LIVE_WIRING_AUDIT.md)；實際程式修正另開 PR，分列預期行為、實測結果及 main 現況。

## 唯一正式完成定義

一個功能的正式交付必須同時符合：

1. 正常 TownPass 入口及使用者操作可達，資料來自真實平台、合法來源或已授權後端；真實 Provider、Repository、Controller 與 UI 接線形成完整流程。只有 Adapter、Parser、介面、模型或獨立測試頁不算完成。
2. Production 使用者資料來源沒有 Mock、Fake、Demo fixtures、硬編成功值或錯誤後的模擬 fallback；正式入口不能選擇 `DataMode.mock`。既有 enum 因契約相容保留，不得任意刪除或修改生成模型；mock 值的允許範圍明確限於隔離測試。
3. 失敗、取消、未配置、缺少資料或權限時顯示 **Unavailable＋真實原因＋可行下一步**；成功空結果與服務失敗可區分，不補人工位置、路線、據點、ETA、已送出或受理編號。
4. 主動操作、定位與外傳用途的個別同意、撤回、取消、遲到回應、背景／離開／SOS 清理皆有測試。已符合驗收的真能力可獨立使用，不因其他 BLOCKED 模組而被全域 Mock 或全域開關封鎖。
5. 有相同 source SHA 的單元／整合、真實 Provider 與必要裝置證據；PASS、FAIL、SKIP、未執行分開記錄。沒有裝置或外部服務驗證就明列未驗，不能以 CI 編譯、文字改標、固定成功或只改 `readiness`／`live=true` 宣稱完成。

本機裝置 TTS 的模擬陪伴內容是產品用途，並不因此等於 Mock 引擎；必須真的播放、誠實回報無引擎或文字預覽，不能偽裝真人接聽、警察或通知已送達。

## 測試與 Production 的邊界

| 場景 | 可接受內容 | 完成聲明 |
|---|---|---|
| Unit／Integration tests | 注入 Fake Provider、Mock repository、人工固定座標、fixture、fake native channel，以驗證錯誤／取消及契約 | 僅證明所測範圍，不證明真實來源或裝置已驗收 |
| 真實 Provider／受控裝置驗證 | 經同意的真實服務、公開地標或受控測試身分，保留來源與去識別證據 | 如實記錄成功、失敗與限制，不使用真實危難作測試 |
| Production／正式使用者入口 | 真實且已完成適用安全與裝置驗收的能力；未完成為 Unavailable＋原因＋下一步 | 不允許 Mock 切換、fixtures 資料來源或錯誤後模擬 fallback |
| 隔離資料庫重設測試 | 專用 CI／測試 schema 的人工 seed，驗 migration、雙重 reset、權限與 rollback | 不把人工 seed 接入 Production，不宣稱主 App 已消費此資料庫 |

## 不隨政策解除的限制

- 沿用 TownPass Flutter 3.47.6、GetX、Theme、TPColors、登入、品牌、LICENSE、DI／module guard 與 canonical Schema；業務模組只依賴自身及 shared，跨模組具體組合留在 `platform/integration/`。
- 功能主責可跨 M1–M5 完成流程，仍依 [協作規範](SAFE_WALK_COLLABORATION.md) 的 Level A／B／C Review；本政策不是隊長對正式開關、敏感資料或遠端副作用的授權。
- GPS 必須由使用者操作觸發；定位權限不等於向 OSRM／其他第三方外傳的同意。保留來源、日期、授權、精度、nullable 與失敗語意，不以歷史統計產生即時安全保證。
- 競賽正式功能不採 Google Maps，也不加入 AED 功能。舊 URI builder、測試、文件或歷史分支提及這些項目，不構成正式整合許可。
- Supabase 管理 key、service_role、資料庫密碼不得進入 App；正式唯讀存取、身分／RPC／RLS 與持久資料權限仍需適用 Level C 審查及驗收。client API 可達不等於業務資料安全完成。
- 真實 SMS／附近協助者通知未完成可信身分、接收資格、ownership、RLS/RPC、防濫用、保留刪除及後端／裝置送達驗收前保持 BLOCKED。不得自動報案／派遣，`officialReceipt` 保持 null；測試不撥真實緊急號碼、不送真實危難或警消案件。
- PR #47 已合併至 main `752dd96`：遠端 Demo 須精確 `DEMO_DATABASE_RESET_ENABLED=true` 才重設，未啟用時允許既有不依賴 Demo 的發布；必要隔離 CI 仍保留。本文件不改 workflow、白名單、Secrets 或現有 `gxofnhzkqcmzrftxqddi` 保護。

## 規範衝突修正對照

| 原文件／衝突或易誤用之處 | 現行規則 | 保留的邊界 |
|---|---|---|
| 原 AGENTS「開發階段」列 Prototype／Integration／Live，容易被誤讀為必經順序 | 不要求先 Mock／Demo／Prototype；從真 Provider 與完整正常流程開始 | 測試可使用替身，不能省略安全、取消或正式證據 |
| 原 AGENTS「Development 可用 Mock」及 LIVE_MVP「公開版本應優先提供已驗證 Live」；ARCHITECTURE 允許離線開發／標示 Demo | Production 僅真能力或 Unavailable；Mock 僅隔離 tests，正式入口不可選 | `DataMode.mock/live` enum 與既有 wire 相容，不任意改 Schema |
| 原 NAVIGATION_PRESENTATION_CONTRACT「缺 scope 的 standalone preview 可保留 Mock」及 Mock「明確展示」範圍 | 標示不會使 Production Mock 合格；缺接線就回 Unavailable，列阻塞與下一步 | 歷史展示與測試證據不刪除，但不再是正式產品授權 |
| MODULES／LIVE_PLAN 的 Provider、Parser 與接線分項，可能只交局部或翻旗標就誤稱完成 | 必須包含 Provider→資料存取→控制→UI→使用者操作、取消及必要裝置驗收 | 分項仍可拆 PR；尚未接線／未驗證如實保留五種 Readiness 狀態 |
| 原正式入口固定全域 Mock；不得將 SUPABASE 的通知 BLOCKED 擴大為所有能力禁止真實化 | 已驗收的 GPS／導航／查詢／TTS 可獨立交付，通知保持 BLOCKED | 正式外送、Supabase 權限及啟用仍依 Level C |
| INITIALIZATION「不建立 UI」「只允許抽象介面」及五分支 pending，若被帶入後續工程會阻止交付 | 僅是歷史範圍，不阻止真實功能或跨模組實作 | 官方殼、DI、Schema、授權、位置隱私及 PR／CI 限制繼續有效 |

舊初始化、整合、測試 SHA、CI 數字與規則查閱證據保留原文並標歷史。這份對照修正現行規範，沒有重寫過去測試或授權事實。
