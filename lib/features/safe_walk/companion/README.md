# M5｜奶爸：純控制器、Audio adapter 與取消清理

**現行政策：LIVE-FIRST DEVELOPMENT + NO PRODUCTION MOCK。** 陪伴情境可明示為模擬，但聲音必須由真實裝置 TTS／核准音訊播放；Fake engine、PreviewSpeaker 計時器不是正式播放來源。無引擎時回語音 Unavailable 與文字預覽，不宣稱已播放／真人接通。直接完成操作、聲音、停止／背景／SOS 與 UI 的完整驗收，不須先交 Demo，見 [完成定義](../../../../docs/SAFE_WALK_LIVE_FIRST.md)。

所有成員均可跨 M1～M5 修改功能與相應測試，自行 AI Coding、除錯及建立 PR。修改其他模組時說明目的、影響檔案及原主要負責人，先核對進行中的 PR 避免同時改同一檔；普通 Level A 變更不需小魚事前批准，Level B 合併前確認；Level C 合併前須隊長明確授權及安全／隱私審查，正式啟用前完成適用驗收。完整規則見 [開放協作](../../../../docs/SAFE_WALK_COLLABORATION.md)。

先讀根目錄 AGENTS、[Live MVP 規格](../../../../docs/SAFE_WALK_LIVE_MVP.md)、[上線條件](../../../../docs/SAFE_WALK_LIVE_READINESS.md)及 [五人模組契約](../../../../docs/SAFE_WALK_MODULES.md)。初始化文件是歷史紀錄。奶爸是音訊主要負責人，莅紋是正式 UI/UX 設計主要負責人；任何成員可跨通話頁、speaker、控制器與測試完成完整陪伴功能，不索取麥克風／聯絡人／位置，不假扮警消或真人親友在線。

## 目前基線與 Live 目標

盤點 main `7b99fea`（#49 恢復 `3c433001` 快照）：Controller、裝置 TTS 與 M3 通話畫面存在。M1 預設建立 `TtsSafeWalkSpeaker.device()`，缺聲音時僅顯示文字，已移除 PreviewSpeaker 的模擬播放計時路徑。裝置 TTS 為 **WIRED_NOT_VERIFIED**，缺 iPhone 播放、中斷與隱私驗收；#37 的音質增量已被 restore 撤回，#46 為開放 PR，不能當成本基線已有。核准錄音的播放器、資產與鈴聲仍未完成。

模擬的是陪伴情境；裝置朗讀與導航分別驗收。Live-only 不禁止誠實標示的陪伴劇本；它禁止以測試 speaker／假回呼冒稱真聲音。不因其他 BLOCKED 能力限制已驗收 TTS，無引擎時不啟動假播放時間。

## 主要負責人與接點

- `lib/features/safe_walk/companion/` 與 `test/features/safe_walk/companion/` 是主要路徑，任何成員可跨 platform/integration／presentation 完成功能與測試。普通音訊／callback／狀態修正屬 Level A；新增依賴、共用契約或重大正式 UI 改版屬 Level B，合併前由小魚／莅紋等對應主要負責人確認；保留官方殼／Theme。
- `CompanionController` 宣告 `start(CompanionScenario, {cancellation})`、`pause()`、`stop(CompanionStopReason)`、`dispose()` 與 `Stream<CompanionEvent> events`。
- `CompanionAudioAdapter` 宣告 `playAsset(String assetPath, {cancellation})`、`pause()`、`stop()`、`dispose()`；以依賴注入提供 fake／native audio，不耦合 Widget、GetX 或電話能力。
- 共用 Scenario／Event／State／Reason 唯讀匯入 shared/models，不建立另一套通話資料 model。

## 狀態、缺值與取消

state 只有 idle／playing／paused／ended／error。audioSrc 為 null 表示無錄音；錄音播放路徑回 not_configured，TTS 能力另行判定；not_configured 是 reason，不能當新 state。持續保留「模擬通話，未聯絡任何人」揭露。

錄音路徑只播放核准的本地資產；wire `/audio/...` 必須經明確資產對映，不能當遠端 URL。裝置 TTS 使用本機引擎，不需要錄音 `audioSrc`；不能因錄音缺值拒絕已驗證的 TTS。Controller 路徑由求助接線先呼叫 `stop(emergency)`，實際 TTS speaker 路徑則呼叫 `stopForEmergency()`；user／emergency／unmount／visibilityHidden 依共用 stop reason 對應 wire 值。

取消、停止與 dispose 要使延遲 play 結果失效，清除計時器／音訊資源；dispose 關閉事件串流，重複呼叫安全。現有驗證包含 Controller fake、TTS mock platform channel 與 Widget lifecycle 測試；這些不等於裝置播放或錄音實機驗收。後續即使播放已授權本地錄音，仍是模擬陪伴，不表示發生真實通話。

## 已實作控制器及整合邊界

`companion_controller.dart` 提供注入式 `LocalCompanionController`：依序協調已核准的本地音訊、暫停、明確停止、求助中斷、取消競態、延遲結果失效與重複 dispose。`CompanionPlayback.started` 與 `completed` 分別確認真正開始及正常播完；控制器只在 started 後發布 playing，並等 completed 後才計算句後間隔及進入下一句。wire `/audio/...` 必須先由建構式注入的 allow-list resolver 轉成 bundled asset；null 或未核准來源只發布 `not_configured`，不交給播放器。

對應 fake adapter 測試涵蓋無音檔、未核准來源、順序播放、暫停、求助中斷、取消競態、播放 milestone 同時失敗、遲到 pause、關閉柵欄、音訊錯誤、清理與重複 dispose。所有 pause／stop 回覆在發布事件前重新確認 operation；dispose 在第一個 await 前封鎖新操作。共用契約沒有 cancellation 專屬的 companion reason，因此合作式取消會停止音訊並使遲到結果失效，但不偽造 wire event；呼叫端若有明確原因，應使用 `stop(reason)`。

`companion_service.dart` 保留抽象接點，`companion_state.dart` 保留純轉移邏輯。控制器與 fake 測試不代表核准錄音的具體播放器、正式資產或實機播放已完成；裝置 TTS 與已合併 M3 UI 的狀態另見下節。

分支 `feat/m5-companion` 曾由共同 Flutter base `40c72e7` 建立；此為來源歷史。後續功能主責可跨模組完成音訊、通話頁、SOS 中斷與測試，不再只限 companion 目錄。

## 裝置 TTS 與驗證邊界

`companion_tts.dart` 另提供文字朗讀，不冒稱真人來電。單一嚇阻劇本使用英文男性角色台詞；Android 只選 `getVoices` 明示 `network_required=0` 且沒有 `notInstalled` 的英文語音，iOS 從已安裝的 `AVSpeechSynthesisVoice.speechVoices()` 清單以 identifier 選取，原生 `AVSpeechSynthesizer` 在裝置上合成。設定語音成功才可用；沒有符合條件的語音、Web 與未驗證的平台保持文字預覽，不自行下載語音或外送文字。平台 voice metadata 不保證性別，實際聲線仍須裝置驗收。

依據：[Android Voice](https://developer.android.com/reference/android/speech/tts/Voice)、[Apple Speech synthesis](https://developer.apple.com/documentation/avfoundation/speech-synthesis) 與 [Apple 已安裝語音說明](https://developer.apple.com/videos/play/wwdc2020/10022/)。欄位映射已核對 lock 中 `flutter_tts 4.2.5` 的原生實作。

插件的完成／取消／錯誤事件沒有 utterance ID，因此共用裝置 driver 在停止中的舊語句收到 terminal 與 stop 回覆前，不送出新語句。等待上限一秒；若無法確認，driver 保持文字預覽直到 App 重啟。尚未開始發聲的語句可能沒有原生取消回呼，亦採此保守處理。每個路線的取消 ticket 及 owner 獨立，離開或 SOS 後的排隊朗讀不能重啟，舊路線的延遲 stop 不能停止新路線。

回歸使用 fake engine、mock platform channel 與 Widget lifecycle，不是實機播放驗收。iPhone 靜音鍵、實際語音品質、OS 中斷與廠商 callback 順序仍需實機確認；不把單元測試視為所有裝置皆可朗讀。

### 歷史分支與生命周期驗證說明

以下保留先前 `03f98f2`／`65ee6f7` 與 stacked #31 時的記錄，不代表現在仍使用該分支或已完成裝置驗收。

原 `03f98f2` 盤點時，`safe_walk_call_view.dart` 已有 `didUpdateWidget()` 更新語音選擇，以及背景取消待回覆、停止時鐘／震動；`TtsSafeWalkSpeaker` 也已有前景與 SOS 永久停止閘門。現在 main `65ee6f7` 及本 stacked 分支承接的 #31 最新 head 已納入 PR #26，統一所有 speaker 的 lifecycle 介面與回歸；不再將 #26 列為未合併阻塞。裝置實際中斷與語音驗收仍需完成。

P1 由指定功能主責負責裝置引擎、組合、通話狀態與 SOS 優先中斷的完整驗收；奶爸、小魚、莅紋是音訊、平台、設計的主要聯絡人，不要求三人各自開接線 PR。至少在實體 iPhone 記錄 OS／裝置／語音、播放完成、停止、離開、背景與返回、OS 音訊中斷、SOS 搶先中斷、語音準備晚到、無可用語音的文字預覽；不得要求麥克風權限，也不得以測試真的撥打緊急號碼。

## 模擬來電鈴聲（P1-3）

`companion_ringtone.dart` 以程式合成原創兩音鈴聲（無第三方素材），經注入式 `CompanionToneAdapter`（實作為 `audioplayers` 記憶體 WAV 播放，不讀檔、不需權限）循環播放，最長 18 秒。`TtsSafeWalkSpeaker` 實作 `SafeWalkRinger`：背景、`stopForEmergency`、`dispose` 與接聽／拒絕都會停止，遲到的 play 結果以 generation 失效，不會重新響鈴。畫面仍保留「模擬通話，未聯絡任何人」。以上只經 fake adapter 測試，尚未在實機聽過；iPhone 靜音鍵、音量與音訊焦點行為待實機驗收。新增 `audioplayers` 依賴屬 Level B，合併前請主要負責人確認。
