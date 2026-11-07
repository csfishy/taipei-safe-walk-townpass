Town Pass 開發預覽，從本 release 記錄的 source commit 建立；實際功能以該版本的程式與驗證結果為準。這不是正式市政服務、政府受理或完整導航產品。

正式交付依 [LIVE-FIRST／NO PRODUCTION MOCK](SAFE_WALK_LIVE_FIRST.md) 與 [Live MVP](SAFE_WALK_LIVE_MVP.md)，能力是否完成以 [Readiness](SAFE_WALK_LIVE_READINESS.md) 及相同 build SHA 的實際證據為準。Production 僅提供真能力或 Unavailable＋真實原因＋下一步，Fake／Mock／fixtures 僅限隔離測試，清楚標示 Demo 也不能替代正式流程。安裝包／網站可開啟不等於 Live 已驗收。

包含 [#64](https://github.com/csfishy/taipei-safe-walk-townpass/pull/64) 的原生版本會在建置時驗證並注入犯罪參考查詢所需的公開 Supabase 設定；缺少設定時停止原生建置，不再產出缺少該設定的原生預覽包。App 的「犯罪資料查詢設定」在服務未配置時會顯示說明，查詢進度與失敗原因也會顯示於路線面板。保留 M3 地圖與原有模擬真人通話設計；本次修正不變更通話流程。

已透過 App 相同的唯讀 Repository、傳輸及解析器實查既有 Supabase，確認快照包含 2,542 筆來源紀錄、10 個來源。另在 Flutter 測試環境以真實 RPC 查詢，驗證指定範圍產生 17 個參考標記及 17 個 50 公尺產品緩衝；該測試使用人工起終點、隔離路線／TTS／儲存邊界，未取得裝置 GPS，**不代表 iPhone 實機驗收**。這些數字是本次驗證範圍的結果，不是所有使用者都會看到的標記數；無座標的紀錄不會補造地圖位置。證據與限制見 [Supabase 實際查詢紀錄](SAFE_WALK_SUPABASE.md)。

iPhone 更新後的操作步驟：

1. 下載本次新 IPA，完成適當簽署後安裝，並核對 release 的版本與 source commit；舊安裝包不會因後端可用而自動取得新的建置設定。
2. 進入「臺北安心行」地圖，在「資料來源與授權」開啟「犯罪資料查詢設定」，確認並同意查詢。
3. 重新規劃路線，依操作授予定位及路線查詢同意，查看犯罪參考查詢狀態與取得的標記。只變更同意設定不會立即查詢；重新規劃才會查詢該行程範圍。

50 公尺是產品避讓緩衝，不是官方犯罪邊界、精確案發範圍或安全保證；歷史資料不代表即時道路風險。每個 release 以自身 source commit 及實際驗證結果為準，沒有裝置證據就明列未驗；競賽正式功能不採 Google Maps、不加入 AED。

- Android APK：Flutter Release build，使用可拋棄的 Android Debug 測試金鑰簽署；不是正式商店簽章。不同 CI build 的金鑰可能不同，更新前可能需要移除舊預覽版。
- iOS IPA：真實 iPhone arm64 Release build，封裝 `Payload/Runner.app`，沒有簽章／provisioning profile；安裝前需要適當簽署，不能直接用 TestFlight 安裝。
- Web ZIP：Flutter Web build，base href 為 `/taipei-safe-walk-townpass/`，提供給 GitHub Pages 專案網址。其他主機需掛在同一路徑，或以正確 `--base-href` 重新建置。
- `build-info.json`：版本、build number、source commit、Flutter 版本。相同內容亦包含在三平台的 Flutter assets。
- `SHA256SUMS.txt`：三個下載檔與 build-info 的 SHA-256。

App／Bundle ID：`io.github.csfishy.taipeisafewalktownpass.preview`，顯示名稱 `Town Pass Preview`。

網站預覽不初始化／要求原生通知；瀏覽器 iframe 不提供原生 TownPass bridge，第三方網站的嵌入與 CORS 政策仍適用。網頁載入與部分操作不等於原生裝置功能已驗收。

網站部署取決於 repository owner 啟用 GitHub Pages（Source: GitHub Actions）及符合環境部署規則；本 Repo 目前為 Public。未配置時 workflow 明確跳過部署，保留 web ZIP，不會回報網站已上線。

實機啟動、定位權限／拒絕、相機、通知、WebView、撥號與裝置無障礙仍需驗收。未測試真實緊急電話或傳送通報。
