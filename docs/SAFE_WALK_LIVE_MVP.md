# 臺北安心行：Live MVP 正式驗收規格

2026-11-08（Asia/Taipei）。依 [LIVE-FIRST／NO PRODUCTION MOCK](SAFE_WALK_LIVE_FIRST.md)，正式交付只有**真實、可驗證、可部署的完整使用者流程**；新功能直接做真實 Provider 與正式 UI 接線，不要求先交 Mock、Demo 或 Prototype。本文定義驗收，現況／缺口見 [Readiness](SAFE_WALK_LIVE_READINESS.md)。基線 main `7b99fea` 正式入口仍 Mock，#35 的 P0 接線已由 #49 restore 移除；這是尚待修正的現況，不能因文件或過去合併紀錄宣稱已 Live。本次文件不改旗標、不啟用未驗證能力。

依 [開放協作規範](SAFE_WALK_COLLABORATION.md)，以下模組／姓名是主要負責與技術驗收聯絡人，不是目錄獨占權。所有成員可跨模組修改合理的功能程式及測試，由指定功能主責交付完整操作流程。一般接線、導航、UI callback、資料轉換、音訊及測試採 Level A；共用契約／Schema／Models、套件、TownPass route／原生設定、重大 UI 及 CI 採 Level B 合併前確認；正式部署開關及高風險真實外部操作採 Level C 隊長授權與安全／隱私驗收。Live 驗收標準不因開放協作而降低。

## 模式與證據

| 能力模式 | 必須滿足 |
|---|---|
| Mock | 僅限 Unit／Integration tests 的隔離替身與人工 fixtures；不得成為 Production 資料來源，正式入口不可選擇。 |
| Live | 實際平台能力／真實合法來源；Provider、權限、同意均已配置；處理失敗、取消、不可用；通過該能力必要測試與實機驗收。 |
| Unavailable | 未配置、資料不足或外部服務不可用，說明原因及可行下一步；不自動以 Mock 假成功。 |

Production 僅提供已驗收真能力或 Unavailable＋真實原因＋下一步；清楚標示 Demo 不會使正式流程中的模擬資料合格。定位、導航、據點、TTS、撥號 handoff 分別驗收／啟用，附近通知的 BLOCKED 不阻擋其他已驗收能力。不得暗中 fallback、硬編成功或只改 `readiness`／`live=true`；只交 Adapter／Parser、獨立測試頁也不算完整功能。

既有 JSON DataMode 只有 mock/live，因契約相容保留，mock 值僅限隔離測試；Unavailable 映射既有 LocationFailure、RouteFailure、not_configured／錯誤及畫面狀態，不新增 Schema enum。Readiness 狀態限 IMPLEMENTED_NOT_WIRED、WIRED_NOT_VERIFIED、LIVE_VERIFIED、BLOCKED、NOT_IMPLEMENTED；只有 Mock Unit Test 不可標 LIVE_VERIFIED。

證據要記錄 source SHA、Provider／endpoint、測試類型、實際結果與 skip、裝置／OS、日期及 Owner。外部服務測試使用人工公開地標，不留真實使用者軌跡。CI build／合成座標重播不能代替實體 iPhone 行走、GPS、音訊與系統交接。

## M1 平台｜小魚

- 沿用 TownPass 的 GeoLocatorService.position()，由使用者主動啟動導航或更新位置取得 GPS；不在進入頁面時取位置，不另建第二份 GPS 監聽。
- 首次允許、拒絕、永久拒絕、系統服務關閉、逾時、過期／未來時間、缺精度／低精度、取消／背景／離開均有明確處理。不以 Demo 座標補失敗，不保留誤導的舊成功狀態。
- 系統定位權限與向第三方路線／附近據點服務傳座標的同意分開：說明接收服務、目的、傳送內容，未同意不送，撤回後取消並忽略遲到結果。
- 必要時使用者主動更新位置；任何持續追蹤須另行明確需求、同意與驗收，不由本規格自動授權背景追蹤。
- 提供使用者主動開啟 110／119 系統撥號器與已核對官方通報管道的入口；取消、無可處理 App、平台失敗可理解。UI 僅聲明交接結果，不聲稱電話接通、警方受理或派遣。
- SOS 先優先中斷語音／導航工作；真實通知、SMS、附近協助者及官方派遣不因撥號能力而順帶啟用。

驗收：Adapter 單元、正式入口至 native seam 整合、真實權限／GPS iPhone 實機；電話以攔截／測試替身驗 URI，實機只開系統撥號畫面或經核准測試流程，**不撥出真實緊急電話、不送報案**。

## M2 導航｜Steven

- 接入已實作 OsrmWalkingRouteProvider／DefaultRouteService，使用真正步行路網；驗 endpoint 的步行 profile、來源與可用性，不用 DemoGeo 或虛構直線冒充路線。
- 顯示實際 geometry、distanceMeters、可取得的 durationSeconds；未知時間顯示未知，不以固定步速／Demo ETA 補成 Provider 預估。
- M1 新位置輸入接入 RouteFollower；驗進度、偏航、到達、低精度／過期位置與刷新，偏航時明示需更新或重新查詢。
- 使用者能選擇、更換目的地；每次 requestId 對應結果，取消／改目的地／撤回同意／背景／離開不讓舊結果覆寫。
- 可選經過已查證據點，透過 M1 注入 lookup 核對 ID、來源、認可、營業與模式。查不到或已關閉不杜撰據點；直接路線替代需揭露繞路不可用／超出上限，不假稱已經過。
- 網路、HTTP、格式、無路線／逾時明示 Unavailable、原因與重試下一步；不自動開第三方 App／瀏覽器或改回 Mock。競賽正式功能不採 Google Maps，舊 URI builder 不構成正式整合許可。
- OSRM 與 walkingNetworkVerified 不代表已驗證安全路線，不保證治安、照明、無障礙或即時通行。

驗收：Provider 解析／錯誤／同意／取消及 follower 單元、正式入口整合、人工公開地標真實 Provider smoke、實體 iPhone 路線／位置刷新。預設公共 OSRM 程式已註明 fair-use／無 SLA；MVP 記錄允許使用條件及負載，Production Readiness 補服務維運方案。

## M3 Flutter UI/UX｜莅紋

- 沿用 TownPass 原生介面、Theme、TPColors 與現有設計，莅紋是正式 UI/UX 主要負責人；一般 UI 功能／callback 可由任何成員修改，大型正式改版須 Level B 合併前確認，不以文件調整重做版面。
- 使用真實地圖底圖及正確 WGS84／GeoJSON [lng, lat] 投影；授權、attribution、網路／底圖載入失敗均可處理。Live 不使用固定 DemoMap 畫布冒充地圖。
- M1 注入 M2 RouteResult，呈現實際路線、距離、可取得的時間；loading、取消、錯誤、空結果、未知時間可區分。
- 提供定位及獨立第三方查詢同意、撤回／重試／更新位置、目的地選擇與更換、路線／外部導航操作。
- 正式畫面清楚呈現真實能力與 Unavailable 原因／下一步；不得顯示虛構避險件數、模擬 ETA／地標或示範據點。狀態與 M1 接線一致，不僅靠傳入 live 字樣；不提供 Production Mock 切換。
- 驗返回、SOS、背景、離開及重進，無遲到路線／語音復活；小螢幕、大字體、VoiceOver 與減少動態效果可操作。

驗收：widget 測試核對真正傳入 geometry／distance／nullable duration、同意及錯誤，不只測截圖；入口至 Controller／Provider seam 整合及實機地圖／投影／無障礙。

## M4 公共安全資料｜信義

- 使用合法來源真實開放資料；保留 datasetId、sourceUrl、retrievedAt、dataUpdatedAt、license、coverage、limitations，未知用契約 null，不編造更新日或授權。
- Repository 可供 M1 查詢，由 M1 注入 M2／M3，明確區分查詢失敗、成功無資料、尚未配置及過期快取。
- 據點座標／ID／查核資訊正確；OSM 24/7 商店不等於政府認證救援、安全合作站、此刻有人或願意協助。認可需 evidenceUrl／checkedAt，營業資訊不能當現場保證。競賽正式範圍不加入 AED 功能。
- 全市犯罪統計不能拆成行政區、道路或逐時風險；既有 violent_crime snapshot 與尚未符合 district-only AreaStatistics 的資料保持分離。歷史率不直接推算即時安全路線。
- 真實來源 fetch／parse／更新、正式查詢畫面及異常完整流程有證據，fixtures 只限隔離測試，不當成已連線證據。來源格式或範圍不符時清楚 Unavailable＋原因＋下一步。正式持久資料整合方向是 Supabase 主資料庫；#44 仍待合併及 Level C 權限／安全審查，不代表 main 已完成後端。

驗收：Parser 正反例／Schema／語意、M1 lookup 與 M2 途經整合、真實來源與 provenance、iPhone 列表／斷網／空資料／錯誤及更新日期顯示。

## M5 模擬陪伴通話｜奶爸（UI：莅紋）

- 使用裝置內建 TTS 的本機可用語音，或已核准、授權可追溯的本機音訊；真實 iPhone 可播放。沒有可用引擎／語音時顯示文字預覽，不假稱播放成功。
- 不要求麥克風權限；不錄音、不上傳聲音或文字到雲端語音服務。語音準備完成的狀態與實際 speaker 選擇同步。
- 支援停止、離開、背景／系統中斷與 SOS 優先中斷；取消計時器、延遲回覆、排隊播放、遲到 prepare／speak，恢復前景不得擅自續播。
- 不假裝真人、警察接聽、報案或派遣；畫面清楚標示模擬陪伴。文字劇本不等於語音播放回執。

驗收：引擎／speaker fake 的取消、遲到、重複停止／dispose 單元，通話頁生命週期整合，iPhone 離線播放、無語音、靜音／音量、背景及 SOS 中斷。已合併 TTS 接線不能取代以上實測。

## 獨立封鎖能力與發布

附近協助者通知目前 BLOCKED：需可信身分、接收資格、資料 ownership、RLS／RPC、頻率及防濫用、定位保留／刪除、明確同意、實際後端與裝置測試。Supabase 連通或匿名 UUID 不足以啟用；不部署未完成授權的 anon security-definer 通知 RPC。官方警消案件自動派送另需官方授權。

這些封鎖不阻擋導航、查詢、TTS、系統撥號器及官方通報入口。逐能力驗收由功能主責彙整完整流程證據，模組主要負責人依審查級別確認；普通配置接線不限定 M1 作者，正式部署開關與真實外部操作須 Level C 授權／安全驗收。PR 審查／CI 後由具備權限的隊員依規則決定合併，執行任務的代理不自行 merge。正式部署還需 [建置](BUILDS.md) 與 [競賽／授權](SAFE_WALK_COMPETITION_LICENSE.md) 的適用條件。
