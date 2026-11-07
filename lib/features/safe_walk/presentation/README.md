# M3｜莅紋：正式 UI/UX 唯一設計負責人

先讀根目錄 AGENTS、官方初始化文件及 [五人模組契約](../../../../docs/SAFE_WALK_MODULES.md)。本初始化目錄 **只有本 README，沒有 Widget、頁面、控制器或樣式實作**。

## 所有權與預定接點

- 正式安心行 UI/UX 由 M3 唯一負責；後續可修改 `lib/features/safe_walk/presentation/`，測試使用 `test/features/safe_walk/presentation/`。
- 官方 main／pages／服務卡／TPColors／theme／GetX route 保留；本次不套舊 React UI 或 Design System、不建立替代首頁。
- 後續輸入使用共用 LocationResult、RouteResult、AssistancePoint／AreaStatistics、CompanionEvent 與模式／操作狀態；不要在 presentation 另造資料 model。
- 使用者操作意圖經 M1 callbacks／controller 邊界接線；不直接取 GPS、開電話或 import M2／M4 實作。正式 Widget／route 接線需在後續工作另行確認。

## 狀態與缺值

保留 mock／live 未配置、loading、定位拒絕、無路線、空資料、未知營業／來源及音訊未配置的真實語意。null 不代表零、空結果不表示附近沒有求助管道，歷史犯罪統計不能表示即時道路安全。OS handoff 不等於已接通或官方受理。

## 第一輪交付

本輪確認輸入／輸出意圖、官方整合邊界與後續設計清單，驗收為沒有新 UI；不自行開始畫面。共用 Schema／模型與官方 route 修改交 M1 協調。未執行的正式 UI 或裝置驗收不寫 PASS。

預定分支 `feat/m3-experience`：**pending**，待初始化 PR 審查並由使用者確認合併後，才從共同 Flutter base 建立；其他模組不先代做通話頁或正式主流程。
