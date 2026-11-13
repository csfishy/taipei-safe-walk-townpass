# 原生預發版：自行輸入信箱的 Live 測試

使用者要求將自填信箱的測試流程合併後，透過既有 CI/CD 自動 release 可供 iPhone 測試的 IPA；並確認沿用**未簽署 IPA、自行簽署安裝**。這是已獲授權的 Live 測試，不代表正式會員或公開救援服務通過驗收。

## 已接入的流程

原生 APK／IPA 的 CI build 明確指定 `SAFE_WALK_EMAIL_LIVE_TEST=true`，仍以 `lib/main.dart` 啟動並保留 TownPass 的 GetMaterialApp／Theme／route。首次啟動進入官方 `/safe_walk` 路由，載入同一專案的公開 client 設定與本機信箱偏好，再顯示信箱說明／輸入畫面。設定錯誤會顯示失敗與重新載入，不切回匿名 Auth 或其他身分。

- 可輸入自己的測試 e-mail，勾選了解未驗證身分後建立／登入；不預填測試名單、不寄驗證碼、不建立 Supabase Auth／TownPass 正式會員。
- 可略過進入訪客狀態；導航與其他既有功能保留。訪客沒有測試通知權限，上方可再次輸入信箱。
- 登入成功才保存正規化信箱；token 僅在記憶體。重開 App 會使用保存的標籤取得新測試 session。
- 加入協助者、定位與求助沿用明確的使用者操作／同意。守護區及聯絡人配對不在這個後端範圍，保持不可用。
- 登出先卸載舊流程，停止其定位／輪詢生命週期，再撤銷本裝置 token；另一裝置 session 不受影響。退出協助者則是帳號層級操作。
- 通知透過前景輪詢及 App 內橫幅，沒有 FCM／APNs／背景送達、簡訊、信件或官方派遣。

未設定旗標的 build 保持原入口。Web 即使誤設旗標也不啟用信箱測試身分。只有明確指定旗標的原生 release／profile 才允許建立測試 transport；獨立 debug 開發入口仍保留。

## 後端範圍與期限

已部署的同專案隔離 schema `safe_walk_nearby_live_test` 與 `swtest_*` API 提供真正的資料持久化及通知收件。正式後端維持 owner-only；本次 client 接線不修改遠端設定，也不延長期限。

**截止：台北時間 2026-11-15 23:23:10（UTC 2026-11-15 15:23:10.845667）。** 到期後登入及後續測試業務 API 會拒絕；重新下載／重建 IPA 不會重新開窗。後端細節、限流、保留與停止方式見 [README](../supabase/nearby_live_test/README.md)及 [48 小時部署紀錄](../supabase/nearby_live_test/DEPLOYMENT_20261113.md)。

任何人輸入相同信箱都能登入同一測試身分，可能看到它收到的求助位置。只使用同意參與者的測試信箱及資料；不輸入敏感位置或真實危難事件。

## CI 與交付驗證

既有全套檢查、Web／Android／iOS 建置及完整發布 gate 保持有效。額外以與原生 build 相同的編譯旗標測試實際 MyApp 啟動路由、官方入口的測試 transport 接線、輸入／略過及設定失敗／重試；原 transport 測試驗證測試 RPC、身分正規化、登出與遲到請求競態。

`verify_native_release.py --email-live-test` 檢查實際 arm64 Flutter AOT payload 包含測試帳號儲存及測試 RPC 標記，缺少即阻止發布；原有公開設定、Bundle ID、版本／來源 SHA、未簽署狀態與資料庫隔離檢查繼續執行。程式存在及 CI 通過不等於通知送達或 iPhone 驗收。

本機 Windows 不宣稱可編譯 iOS；IPA 以 GitHub Actions macOS 的實際建置、檢查與 release asset 為準。Release 記錄 source commit、build number 與 checksum；下載時核對相同版本。IPA 未簽署且無 provisioning profile，由使用者自行簽署安裝，不能直接透過 TestFlight 安裝。

初次 PR CI 的完整 Flutter 1332 項通過／20 項 skip、原生旗標 10 項及瀏覽器 18 項測試通過，Android／Web 建置亦通過；iOS 未開始編譯即因 hosted ARM64 容量不足耗盡 runner 分配重試而取消。改用官方支援的 `macos-15-intel` 主機池，保留 Xcode 26.1.1、iPhone arm64 交叉編譯及所有原產物檢查，需由新 head 的 CI 重新驗證。[官方 runner 規格](https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job)、[macOS 15 Intel 映像的 Xcode 清單](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md)。

## iPhone 測試步驟

1. 下載本次 release 的 `taipei-safe-walk-townpass-ios-unsigned.ipa`，核對 source commit／SHA256SUMS，自行簽署並安裝。
2. 開啟 App，確認看到「輸入 e-mail 開始 Live 測試」與未驗證身分說明。若略過，可從上方「輸入信箱」回來。
3. 在兩個經同意裝置使用不同測試信箱；A 加入協助者並依操作同意定位，B 在 500 公尺內主動發送測試求助。保持 A App 前景，等待輪詢並核對橫幅；不要撥真實緊急電話或傳送真實通報。
4. 測試同信箱多裝置、只登出本裝置、退出協助者及重新開啟 App。超額、過期或連線失敗應明確顯示，不偽造成功。

目前沒有雙裝置／真 GPS／背景或實機送達的驗收證據，保留為待使用者在受控 Live 測試確認項目。

## 審查範圍

涉及 M1 platform/integration、官方 route、原生 CI 與 M5 求助通知接線；功能主責為 M1 小魚。沿用既有 payload 契約、資料結構及第三方傳輸同意，不修改 Schema／套件 lock。Level B/C 依使用者對原生預發版與 Live 測試的明確要求及既有授權執行；正式會員資格與公開救援服務的 BLOCKED 狀態不因此解除。
