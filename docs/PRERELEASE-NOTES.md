Town Pass 開發預覽，從本 release 記錄的 source commit 建立；實際功能以該版本的程式與驗證結果為準。這不是正式市政服務、政府受理或完整導航產品。

現行開發目標為 [Live MVP](SAFE_WALK_LIVE_MVP.md)，能力是否完成以 [Readiness](SAFE_WALK_LIVE_READINESS.md) 與相同 build SHA 的實際證據為準。保留 Demo 預覽不代表產品永久預設 Mock；安裝包／網站可開啟不等於 Live 已驗收。

- Android APK：Flutter Release build，使用可拋棄的 Android Debug 測試金鑰簽署；不是正式商店簽章。不同 CI build 的金鑰可能不同，更新前可能需要移除舊預覽版。
- iOS IPA：真實 iPhone arm64 Release build，封裝 `Payload/Runner.app`，沒有簽章／provisioning profile；安裝前需要適當簽署，不能直接用 TestFlight 安裝。
- Web ZIP：Flutter Web build，base href 為 `/taipei-safe-walk-townpass/`，提供給 GitHub Pages 專案網址。其他主機需掛在同一路徑，或以正確 `--base-href` 重新建置。
- `build-info.json`：版本、build number、source commit、Flutter 版本。相同內容亦包含在三平台的 Flutter assets。
- `SHA256SUMS.txt`：三個下載檔與 build-info 的 SHA-256。

App／Bundle ID：`io.github.csfishy.taipeisafewalktownpass.preview`，顯示名稱 `Town Pass Preview`。

網站預覽不初始化／要求原生通知；瀏覽器 iframe 不提供原生 TownPass bridge，第三方網站的嵌入與 CORS 政策仍適用。網頁載入與部分操作不等於原生裝置功能已驗收。

網站部署取決於 repository owner 啟用 GitHub Pages（Source: GitHub Actions）及符合環境部署規則；本 Repo 目前為 Public。未配置時 workflow 明確跳過部署，保留 web ZIP，不會回報網站已上線。

實機啟動、定位權限／拒絕、相機、通知、WebView、撥號與裝置無障礙仍需驗收。未測試真實緊急電話或傳送通報。
