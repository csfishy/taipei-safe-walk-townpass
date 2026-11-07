# M5｜奶爸：純控制器、Audio adapter 與取消清理

先讀根目錄 AGENTS、官方初始化文件及 [五人模組契約](../../../../docs/SAFE_WALK_MODULES.md)。本模組不建立通話頁、不索取麥克風／聯絡人／位置、不假扮警消或真人親友在線。

## 所有權與接點

- 可改 `lib/features/safe_walk/companion/`，測試使用 `test/features/safe_walk/companion/`。正式 UI 交 M3，跨模組與新依賴交 M1，不修改官方頁面／theme。
- `CompanionController` 宣告 `start(CompanionScenario, {cancellation})`、`pause()`、`stop(CompanionStopReason)`、`dispose()` 與 `Stream<CompanionEvent> events`。
- `CompanionAudioAdapter` 宣告 `playAsset(String assetPath, {cancellation})`、`pause()`、`stop()`、`dispose()`；以依賴注入提供 fake／native audio，不耦合 Widget、GetX 或電話能力。
- 共用 Scenario／Event／State／Reason 唯讀匯入 shared/models，不建立另一套通話資料 model。

## 狀態、缺值與取消

state 只有 idle／playing／paused／ended／error。audioSrc 為 null 表示無錄音，只能表達文字或未配置；not_configured 是 reason，不能當新 state。持續保留「模擬通話，未聯絡任何人」揭露。

只播放核准的本地資產；wire `/audio/...` 必須經明確資產對映，不能當遠端 URL。M1 求助先呼叫 `stop(emergency)`；user／emergency／unmount／visibilityHidden 依共用 stop reason 對應 wire 值。

取消、停止與 dispose 要使延遲 play 結果失效，清除計時器／音訊資源；dispose 關閉事件串流，重複呼叫安全。本次只有純狀態／契約測試，尚未實作或測試完整 audio Adapter，不進行裝置播放或錄音。後續即使播放已授權本地錄音，仍是模擬陪伴，不表示發生真實通話。

## 第一輪交付

後續交付純控制器與 fake adapter 的無音檔、暫停、停止、求助中斷、取消競態、延遲播放、清理及重複 dispose 測試。本次 `companion_service.dart` 是抽象接點，另有 `companion_state.dart` 純轉移邏輯：開始播放的回執、暫停回執與中止訊號分開。狀態測試通過不代表錄音、計時器或播放資源已驗收；目前沒有具體控制器／播放功能。

預定分支 `feat/m5-companion`：**pending**，待初始化 PR 審查並由使用者確認合併後，才從共同 Flutter base 建立。
