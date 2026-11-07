# M5｜奶爸：純控制器、Audio adapter 與取消清理

先讀根目錄 AGENTS、[Live MVP 規格](../../../../docs/SAFE_WALK_LIVE_MVP.md)、[上線條件](../../../../docs/SAFE_WALK_LIVE_READINESS.md)及 [五人模組契約](../../../../docs/SAFE_WALK_MODULES.md)。初始化文件是歷史紀錄。本模組不自行設計通話頁，正式 UI/UX 由 M3 莅紋維護；M5 提供實際音訊能力，不索取麥克風／聯絡人／位置，不假扮警消或真人親友在線。

## 目前基線與 Live 目標

截至 main `03f98f2b7b5254db73774c4d097eb4d610499c2c`，`LocalCompanionController`、裝置 TTS 與 M3 通話畫面均已合併。M1 的 `SafeWalkCompositionRoot` 已預設建立 `TtsSafeWalkSpeaker.device()`，準備裝置語音後交給正式入口的 Flow；不能再將全部音訊寫成「只有抽象介面／尚未接入」。裝置 TTS 為 **WIRED_NOT_VERIFIED**：已接線但缺 iPhone 實際播放、中斷及隱私驗收，並非 LIVE_VERIFIED。核准錄音的具體播放器與資產仍未完成。

模擬的是陪伴情境；裝置真正朗讀與導航資料模式分別驗收。正式公開版本應提供已驗證的裝置語音，不因導航仍為 Mock 永久阻擋 TTS。沒有可用引擎或語音時清楚顯示文字預覽，不能以無聲計時器宣稱已播放。

## 所有權與接點

- 可改 `lib/features/safe_walk/companion/`，測試使用 `test/features/safe_walk/companion/`。正式 UI 交 M3，跨模組與新依賴交 M1，不修改官方頁面／theme。
- `CompanionController` 宣告 `start(CompanionScenario, {cancellation})`、`pause()`、`stop(CompanionStopReason)`、`dispose()` 與 `Stream<CompanionEvent> events`。
- `CompanionAudioAdapter` 宣告 `playAsset(String assetPath, {cancellation})`、`pause()`、`stop()`、`dispose()`；以依賴注入提供 fake／native audio，不耦合 Widget、GetX 或電話能力。
- 共用 Scenario／Event／State／Reason 唯讀匯入 shared/models，不建立另一套通話資料 model。

## 狀態、缺值與取消

state 只有 idle／playing／paused／ended／error。audioSrc 為 null 表示無錄音；錄音播放路徑回 not_configured，TTS 能力另行判定；not_configured 是 reason，不能當新 state。持續保留「模擬通話，未聯絡任何人」揭露。

錄音路徑只播放核准的本地資產；wire `/audio/...` 必須經明確資產對映，不能當遠端 URL。裝置 TTS 使用本機引擎，不需要錄音 `audioSrc`；不能因錄音缺值拒絕已驗證的 TTS。Controller 路徑由 M1 求助先呼叫 `stop(emergency)`，實際 TTS speaker 路徑則呼叫 `stopForEmergency()`；user／emergency／unmount／visibilityHidden 依共用 stop reason 對應 wire 值。

取消、停止與 dispose 要使延遲 play 結果失效，清除計時器／音訊資源；dispose 關閉事件串流，重複呼叫安全。現有驗證包含 Controller fake、TTS mock platform channel 與 Widget lifecycle 測試；這些不等於裝置播放或錄音實機驗收。後續即使播放已授權本地錄音，仍是模擬陪伴，不表示發生真實通話。

## 已實作控制器及整合邊界

`companion_controller.dart` 提供注入式 `LocalCompanionController`：依序協調已核准的本地音訊、暫停、明確停止、求助中斷、取消競態、延遲結果失效與重複 dispose。`CompanionPlayback.started` 與 `completed` 分別確認真正開始及正常播完；控制器只在 started 後發布 playing，並等 completed 後才計算句後間隔及進入下一句。wire `/audio/...` 必須先由建構式注入的 allow-list resolver 轉成 bundled asset；null 或未核准來源只發布 `not_configured`，不交給播放器。

對應 fake adapter 測試涵蓋無音檔、未核准來源、順序播放、暫停、求助中斷、取消競態、播放 milestone 同時失敗、遲到 pause、關閉柵欄、音訊錯誤、清理與重複 dispose。所有 pause／stop 回覆在發布事件前重新確認 operation；dispose 在第一個 await 前封鎖新操作。共用契約沒有 cancellation 專屬的 companion reason，因此合作式取消會停止音訊並使遲到結果失效，但不偽造 wire event；呼叫端若有明確原因，應使用 `stop(reason)`。

`companion_service.dart` 保留抽象接點，`companion_state.dart` 保留純轉移邏輯。控制器與 fake 測試不代表核准錄音的具體播放器、正式資產或實機播放已完成；裝置 TTS 與已合併 M3 UI 的狀態另見下節。

分支 `feat/m5-companion` 已由共同 Flutter base `40c72e7` 建立；M5 仍只修改 companion 與對應測試目錄。

## 裝置 TTS 與驗證邊界

`companion_tts.dart` 另提供文字朗讀，不冒稱真人來電。Android 只選 `getVoices` 明示 `network_required=0` 且沒有 `notInstalled` 的中文語音；iOS 從已安裝的 `AVSpeechSynthesisVoice.speechVoices()` 清單以 identifier 選取，原生 `AVSpeechSynthesizer` 在裝置上合成。設定語音成功才可用；沒有符合條件的語音、Web 與未驗證的平台保持文字預覽，不自行下載語音或外送文字。

依據：[Android Voice](https://developer.android.com/reference/android/speech/tts/Voice)、[Apple Speech synthesis](https://developer.apple.com/documentation/avfoundation/speech-synthesis) 與 [Apple 已安裝語音說明](https://developer.apple.com/videos/play/wwdc2020/10022/)。欄位映射已核對 lock 中 `flutter_tts 4.2.5` 的原生實作。

插件的完成／取消／錯誤事件沒有 utterance ID，因此共用裝置 driver 在停止中的舊語句收到 terminal 與 stop 回覆前，不送出新語句。等待上限一秒；若無法確認，driver 保持文字預覽直到 App 重啟。尚未開始發聲的語句可能沒有原生取消回呼，亦採此保守處理。每個路線的取消 ticket 及 owner 獨立，離開或 SOS 後的排隊朗讀不能重啟，舊路線的延遲 stop 不能停止新路線。

回歸使用 fake engine、mock platform channel 與 Widget lifecycle，不是實機播放驗收。iPhone 靜音鍵、實際語音品質、OS 中斷與廠商 callback 順序仍需實機確認；不把單元測試視為所有裝置皆可朗讀。

目前 main 的 `safe_walk_call_view.dart` 已有 `didUpdateWidget()` 更新語音選擇，以及背景時取消待回覆、停止時鐘／震動的處理；`TtsSafeWalkSpeaker` 已有前景閘門與 SOS 永久停止閘門。未合併 PR #26 是需另行審查的後續工作，不能把它的全部內容當成 main 完全沒有的能力；仍須核對所有 speaker 實作的生命週期行為。

P1 驗收由 M5 奶爸負責裝置引擎與播放／停止，M1 小魚負責組合與 SOS 優先中斷，M3 莅紋負責狀態揭露與操作。至少在實體 iPhone 記錄 OS／裝置／語音、播放完成、停止、離開、背景與返回、OS 音訊中斷、SOS 搶先中斷、語音準備晚到、無可用語音的文字預覽；不得要求麥克風權限，也不得以測試真的撥打緊急號碼。
