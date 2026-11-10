# 模擬來電錄音稿：疑似遭人跟蹤

男聲（英文）目前由手機 TTS 朗讀；要改用真人錄音時，依下表錄製並把檔名填進
`test/features/safe_walk/companion/fixtures/companion_scenarios.json` 的 `audioSrc`，
再同步 `companion_scenarios.dart`（`safe_walk_companion_sync_test.dart` 會比對）。
女聲（繁中）是使用者看著螢幕大聲照讀的台詞，不需錄音、不用麥克風；用語像一般回家路上講電話，不含「跟著我、有人、回頭、不對勁、報警、危險」等會讓旁人起疑的字（測試把關）。

| 順序 | 誰說 | 台詞 | 建議檔名 | 語氣 |
|---|---|---|---|---|
| 1 | 男友 | Damn it, babe, where the hell are you? You should've been home by now. I'm already downstairs waiting for you. | `line-1.m4a` | 不耐煩、大聲，讓旁人聽得到 |
| 2 | 使用者 | 我快到了啦，還在路上，再幾分鐘。 | — | |
| 3 | 男友 | Don't stop anywhere. Keep walking toward the lights. I'm coming down to get you right now. | `line-2.m4a` | 果斷、催促 |
| 4 | 使用者 | 好，我走大路，不要催啦。 | — | |
| 5 | 男友 | Okay. I'm out the door now. Stay on the phone with me and tell me where you are. | `line-3.m4a` | 邊走邊說、穩定 |
| 6 | 使用者 | 我在便利商店旁邊，前面就是路口。 | — | |
| 7 | 男友 | Good, I know that corner. I'm two minutes away. Stay where people can see you and keep talking to me. | `line-4.m4a` | 有把握、安撫 |
| 8 | 使用者 | 好，我看到你了，我現在直接走過去。電話先不要掛。 | — | |
| 9 | 男友 | I see you. Keep walking straight toward me. I'm right here, and I'm watching everything around you. | `line-5.m4a` | 結尾、刻意說給旁人聽 |

錄音建議：每句單獨一檔、前後留 0.3 秒靜音、音量正規化到相近大小，總長約 45 秒。
