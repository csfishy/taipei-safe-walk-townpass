# 臺北安心行 · TownPass 原生協作規則

任何模組工作前先讀 `docs/SAFE_WALK_ARCHITECTURE.md`、`docs/SAFE_WALK_INITIALIZATION.md`、`docs/SAFE_WALK_SCHEMA.md`、`docs/SAFE_WALK_MODULES.md`、`docs/SAFE_WALK_COLOR_SPEC.md` 及所屬模組 README。

## 本次初始化的明確邊界

- 本專案以官方 TownPass Flutter 為主要 App；原 React Repository 是 Legacy 歷史與契約參考，不再是主要 App。
- 不建立安心行首頁、地圖、SOS、陪伴畫面、預設 Layout、卡片、Widget Tree、底部分頁、Wireframe 或 CSS Design System。
- 正式新增 UI/UX 由 M3 莅紋後續設計；不要以初始化的介面或版型預先限制她。
- 保留官方 `main.dart`、Theme、`TPColors`、頁面、GetX 路由、登入、會員、WebView、品牌與原始 LICENSE；不得為了測試或新功能直接重做官方殼。
- 只追加 `lib/features/safe_walk/` 的資料／服務／控制邏輯接點、測試、Schema 及文件。新增色彩只先提出理由；本輪只有顏色文件。

## 檔案所有權

- M1 小魚：platform、共用 contracts/models、pubspec/lock、路由、平台設定、CI、跨模組接線。
- M2 Steven：navigation 的座標處理與 Route Service，不再註冊第二份 GPS 監聽，不做正式地圖 UI。
- M3 莅紋：presentation；本輪僅保留 README，後續取得設計任務後再建立正式 UI。
- M4 信義：safety_data 的來源、Parser、Repository 與測試資料。
- M5 奶爸：companion 的無 UI 狀態控制、音訊 Adapter 與清理／中斷測試，不建通話頁。
- 模組只依賴自身與 shared，不直接 import 其他模組實作。M1 組合及接線須先記錄跨模組契約影響。
- canonical JSON Schema 是 payload 單一來源；生成的 Dart Model／Schema bundle 不手改，執行 generator 並檢查同步。
- 不升級 Flutter、GetX 或全部依賴；依 `.fvmrc` 使用 Flutter 3.47.6。工具或環境限制要如實回報。

## 誠實與資料邊界

- 預設 mock、真實撥號關閉；所有例子為人工資料，無真實使用者位置或危難個案。
- 位置取得必須由明確使用者操作觸發；不得自動追蹤／外傳。模擬與真實資料不能暗中混用。
- 無官方授權不得送警消案件、派遣救援者或回傳假的受理編號；officialReceipt 保持 null。
- 行政區歷史犯罪統計不等於即時路段安全分數，不能宣稱安全保證。
- 模擬陪伴不是真人通話或報案；停止／SOS／卸載必須取消音訊、計時器與遲到的非同步工作。
- 不提交 secrets、憑證、定位紀錄、住家、聯絡人或 Token；不要求在對話貼 Token。
- 不呼叫真實緊急號碼、不發真實通報做測試。不要執行官方 App 登入或授權流程作為初始化測試。

## Git 與驗證

- `upstream` 僅供讀取官方來源；所有 push 必須明確指定團隊 `origin`，不得寫入 upstream。
- 初始化使用 `migration/townpass-native-base` 與 PR，不自行合併 main。
- 五個模組分支待初始化 PR 經確認合併後，才從同一個合併 Commit 建立；不能提前聲稱已建立。
- 不 force push、不刪隊員分支、不擅自關 PR、不 reset／clean 他人工作，不丟棄 Legacy M2/M5 成果。
- 不自動邀請協作者；新 Repo 權限需正確 username 與授權。
- 實跑 pub get、build_runner、Schema generator/check、analyze、test；Build 依工具可用性執行。未執行或失敗不可寫 PASS；Windows 不宣稱本機 iOS 編譯。
- `docs/SAFE_WALK_INITIALIZATION.md` 記錄實際驗證與上游既有問題。驗證不等於已符合競賽資格、法律授權或實機功能全部完成。
