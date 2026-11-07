# LIVE-FIRST 正式接線基線盤點

2026-11-08（Asia/Taipei）。本文件是 Phase A 文件 PR 的唯讀程式盤點，固定基線為團隊 main **`7b99fea4e4e3b71da1e265cc99d9e9d7c8266834`**。本階段尚未修改執行期程式、Provider、flags、Schema、RPC／RLS、Secrets、CI 或遠端資料；下列「所需修正」都是後續工程，不能當成 Phase B 已完成證據。

現行完成定義見 [LIVE-FIRST／NO PRODUCTION MOCK](SAFE_WALK_LIVE_FIRST.md)，審查依 [協作規範](SAFE_WALK_COLLABORATION.md)，正式驗收依 [Readiness](SAFE_WALK_LIVE_READINESS.md)。本文狀態只使用 `IMPLEMENTED_NOT_WIRED`、`WIRED_NOT_VERIFIED`、`LIVE_VERIFIED`、`BLOCKED`、`NOT_IMPLEMENTED`；狀態針對表中指定的真實能力，不是說既有 Widget 或 Mock 不存在。本次沒有任何能力因文件盤點升為 `LIVE_VERIFIED`。

## 歷史與證據範圍

- [PR #35](https://github.com/csfishy/taipei-safe-walk-townpass/pull/35) 曾合併 P0 Live 接線，但 [PR #49](https://github.com/csfishy/taipei-safe-walk-townpass/pull/49) 已將程式樹恢復至 `3c433001e97b493fdcbda16cac15a04618b89da8` 快照。Git 歷史仍在，不表示目前 main 還有 #35 的正式操作流程。
- 可以審查並重用既有 Provider、controller、#35 或其他分支的程式，仍須對新 head 完成整合及適用驗收。舊 SHA 的 CI、真實來源 smoke 或裝置結果不能自動算作新 SHA 通過。
- 下列程式連結全部固定至盤點 SHA，行號不隨後續修改漂移。主要檔案前綴為 `lib/features/safe_walk/`；功能主責可跨模組實作，表中姓名是領域聯絡／驗收角色，不是修改權限限制。
- 本次使用 `git show`、`git grep`、`git diff` 核對原始碼與分支差異；沒有執行 App、Flutter tests／build、真 GPS、第三方請求、裝置操作或遠端 SQL。後續 PR 必須另列實際 PASS／FAIL／SKIP／未執行，不以本盤點代替測試。

## 十項 Runtime 檢查

| 項目／固定來源與行號 | 基線狀態與問題 | 所需修正 | 主要聯絡人 | 驗收、實際阻塞與下一步 |
|---|---|---|---|---|
| R1 正常 TownPass 入口與組合根：[城市服務:187–192][townpass-service]、[TPRoute:83–84／196–204][townpass-route]；[composition root:77–90][root]、109–111、203、235、276、313 | **IMPLEMENTED_NOT_WIRED**：正常入口可達，但注入 DemoGeo 位置、Mock 據點，controller／查詢／定位／求助／Flow 各自固定 Mock；兩個 Live readiness 為 false。 | 保留官方 route／品牌，正式入口只組合真能力或明確 Unavailable；資料、位置、UI、request/result 同模式。不能只改 `mode` 或兩個 bool，也不能以某一高風險能力 BLOCKED 鎖住整個產品。 | M1 小魚；M2 Steven、M3 莅紋、M4 信義、M5 奶爸協作。 | 由正常入口跑到定位／同意／路線／呈現，驗無人工資料與模擬 fallback、取消／背景／SOS；必要 iPhone 證據。阻塞是尚未完整組合及驗收；下一步先修 R2–R4 的真資料呈現與 R7–R8 的同意／位置流程，正式啟用依適用 Level C。 |
| R2 Flow：[safe_walk_flow.dart:17][flow]、75–84、89–100、163–187；[root:295–323][root-scope] | **IMPLEMENTED_NOT_WIRED**：Flow 有 route 參數與 callback，但未消費 `SafeWalkNavigationScope`，root 也未傳入 route／loading／onPlanRoute；目的地、異常、據點預載 Demo，無位置時以 DemoGeo 排序，null points 會補示範。 | 選定 shared scope 或顯式 adapter 作單一資料流；實際目的地由使用者選擇，route/loading/error/consent/cancel 接到畫面；正式缺值保持缺值／Unavailable，不回 Demo。 | M3 莅紋、M1 小魚；M2 Steven驗路線契約。 | Widget＋root 整合驗選／換目的地、同意／撤回、重試／取消、遲到結果；無位置時不得算附近排序。阻塞是現有 API 未完整接線及預載假資料；下一步與 R1/R3 協調同檔案修改。 |
| R3 地圖頁：[safe_walk_map_view.dart:116][map-view]、170–177、189 | **IMPLEMENTED_NOT_WIRED**：缺位置補 DemoGeo；求助據點使用 L 形線，未配置回家路線會補示範線；距離／分鐘可由示範 path 推算，呈現虛構「已繞開」件數。 | 只畫核對過的 RouteResult geometry，距離與可取得時間由 Provider 傳入，未知時間保持 null；據點導航也須真路網，缺位置／路線顯示原因及下一步；移除虛構避險成果。 | M3 莅紋、M2 Steven；M1 小魚接結果。 | Widget 驗缺位置、route null/loading/failure、duration null、據點切換均無 Demo 線／假 ETA／假避險件數；真實路線到畫面的裝置驗收。阻塞是 presenter 仍有 fallback；下一步先完成真資料分支與空狀態，不靠換文案解決。 |
| R4 底圖與覆蓋物：[demo_map.dart:21–33][demo-map]、69–74、104–142、169 | 真 OSM 圖磚／投影子能力 **WIRED_NOT_VERIFIED**；完整 Live 覆蓋物 **NOT_IMPLEMENTED**。類名不是主要問題：視野與 marker 硬塞 DemoGeo.home，可畫 Demo shortcut，接入的異常／據點仍可能來自 fixtures。 | 保留可用 renderer、來源標示與投影；視野、目的地、起點、路線及 marker 僅由已驗真資料決定；空集合也有可用畫面，不塞示範家或異常。 | M3 莅紋；M1 小魚、M2 Steven協作。 | 投影／camera fit／空資料／點擊與無障礙測試，驗 attribution、圖磚失敗及 iPhone 操作。阻塞是底圖已接但產品資料未真實化，不能把地圖可見當導航完成；下一步接 R2/R3，核對圖磚使用條件。 |
| R5 求助與簡訊：[safe_walk_emergency_view.dart:198–214][emergency]；[townpass_platform_adapter.dart:104–124][gps-adapter]；[root:276–279][root-emergency] | 正式系統交接／SMS Adapter **NOT_IMPLEMENTED**。沒有 live sender 時 `_send()` 延遲後固定 true，進入 sent 畫面；平台本身誠實回 not_configured，沒有真正撥號／通報。真實 SMS／附近通知啟用另為 **BLOCKED**。 | 缺 sender 立即顯示 Unavailable＋真實原因，不模擬成功。系統撥號／官方入口與資料發送分開實作；交接不等於接通、發送或受理，`officialReceipt` 保持 null；不因 Live-only 開啟通知 RPC。 | M1 小魚、M3 莅紋；M5 奶爸確認 SOS 停聲。 | 驗無 sender／取消／launcher 失敗／缺權限均不進成功畫面；受控 iPhone 僅開交接畫面，不撥真緊急號碼或送案件。下一步可隔離實作與 PR；真實外部作用仍需 Level C 授權，通知另補身分、ownership、防濫用及保留刪除。 |
| R6 陪伴語音與無引擎狀態：[safe_walk_call_view.dart:64][call-view]、86–110；[root:91／153–161][root-speaker]；[tts_safe_walk_speaker.dart:14–26][tts-speaker]；[safe_walk_speaker.dart:25–33][preview-speaker] | 真裝置 TTS 已接線，**WIRED_NOT_VERIFIED**，不是「完全沒有音訊」。但引擎不可用時 CallView 以 PreviewSpeaker 按字數計時、模擬朗讀樣式；不能把這個 fallback 稱成真播放。 | 保留裝置引擎及清理；無 voice／引擎錯誤只提供明確文字預覽及下一步，不啟用假播放計時狀態。陪伴劇本是產品內容，實際本機 TTS 不因內容為模擬陪伴而等同 Mock 引擎。 | M5 奶爸、M1 小魚、M3 莅紋。 | 真引擎準備／播放／無 voice／OS 中斷、停止／離開／背景／SOS／dispose 及遲到 callback；iPhone 離線證據。阻塞是裝置及錯誤呈現未驗；下一步移除正式 PreviewSpeaker fallback 並補引擎失敗狀態，不要求麥克風、不偽裝真人接聽。 |
| R7 位置平台：[townpass_platform_adapter.dart:27–28／34–99][gps-adapter]；[GeoLocatorService:9–40][native-gps]；[root:232–235][root-locate] | 真 GPS Adapter **IMPLEMENTED_NOT_WIRED**：沿用 `Get.find<GeoLocatorService>().position()`，已有主動操作、取消、逾時、mocked／精度／時間檢查；正式入口卻仍傳 mock，未消費真能力。 | 正式使用者操作走既有 TownPass 服務並傳 live；位置失敗回原因，不補 DemoGeo。位置權限與第三方外傳同意分開，不新增另一個 GPS watcher 或自動追蹤。 | M1 小魚；M2 Steven消費 Position，M3 莅紋呈現。 | Adapter 測試驗無主動操作不呼叫、拒絕／永久拒絕／逾時／過期／取消；受控 iPhone 驗原生權限與真定位，證據不記錄私人位置。阻塞是入口模式與實機驗收；下一步先接主動取得／更新與清理，不能直接讓載入觸發外傳。 |
| R8 OSRM 與 transport：[osrm_walking_route_provider.dart:27–43][osrm]、128–141、184–203；[default_json_transport.dart:1–8][transport-selector]、[io_json_transport.dart:10–16][io-transport]、[unsupported_json_transport.dart:4–23][unsupported-transport] | 原生真步行 Provider **IMPLEMENTED_NOT_WIRED**；Web HTTP 實作 **NOT_IMPLEMENTED**，目前明確 unsupported／Unavailable。root 建構 OSRM 不代表 Flow 已操作它。 | 正式流程取得獨立 routing consent 後才送起終點；完成 request/result／cancel 接線。原生延用 HTTPS、逾時、大小及取消保護；Web 若未另驗 transport/CORS 仍誠實不可用，不能以直線或 Mock 補成功。 | M2 Steven；M1 小魚接同意／transport，M3 莅紋接狀態。 | 真 Provider 成功、無路線、timeout、斷網、撤同意／換目的地／背景取消；iPhone request→geometry／距離／時間。阻塞是正常入口接線、服務條件／容量及裝置證據；下一步使用已存在 foot endpoint 完成受控驗證。`walkingNetworkVerified` 不表示治安安全。 |
| R9 進度／偏離／抵達：[route_follower.dart:73–81][follower]、140–187；[root:92–112／295–323][root] | **IMPLEMENTED_NOT_WIRED**：Follower 已消費 Position／Stream 並計算 FollowUpdate，但 root／Flow 沒有建立或消費它。 | 由平台組合在真路線上建立 follower，把使用者更新的位置交入並注入 UI；取消、改目的地、背景、離開／SOS 清除舊 follower／結果，不另開 GPS。 | M2 Steven、M1 小魚、M3 莅紋。 | 純邏輯驗過期／精度／偏離／抵達與換線，整合驗更新按鈕到進度及取消清空；真裝置受控步行驗收。阻塞是未接線及裝置證據；下一步先完成使用者主動更新，不把幾何方向步驟說成已完成逐路口導航。 |
| R10 真便利商店／附近據點：[osm_convenience_store_source.dart:25–35][osm-stores]、56–60、101–159、212–230；[nearest_store_planner.dart:85–129][store-planner]；[root:85–90／203][root] | OSM Source／NearestStorePlanner **IMPLEMENTED_NOT_WIRED**；一般 M4 真據點 Repository **NOT_IMPLEMENTED**。目前 root 仍供 Mock 據點，不能宣稱附近查詢已完成。 | 平台組合真 source／planner，另揭露並取得 Overpass 查詢用途同意；保留來源、日期、營業未知及未認可狀態，成功空結果／失敗／未配置分開；商店不能當政府認證救援點。 | M4 信義、M2 Steven；M1 小魚組合，M3 莅紋呈現。 | 真來源與語意／模式／取消測試，拒同意零請求、空結果／格式失敗、lookup／途經及 iPhone；不加入 AED 或 Google Maps。阻塞是來源到正式列表／路線未接及驗收不足；下一步先協調援助相關 PR 與 DTO，不能直接把 source 存在當整個 M4 完成。 |

## M4／Supabase：來源、持久資料與只讀入口

| 範圍／基線 | 五狀態與可證明內容 | 實際缺口、下一步及驗收 |
|---|---|---|
| main 全市暴力犯罪月統計：[violent_crime/README.md:5–9][city-crime]、23–33；[normalizer:47–52][city-limitations] | **IMPLEMENTED_NOT_WIRED**。已有 live-only 資料來源讀取，不新增 DB；資料只有全市月份，非行政區／道路／即時風險。 | M4 信義與 M1／M3 完成資訊呈現；不能塞入 district-only AreaStatistics 或用於逐路段安全分數。驗真來源、來源時間未知、格式改版／取消及 iPhone 標示。 |
| [PR #39](https://github.com/csfishy/taipei-safe-walk-townpass/pull/39)，head `d39608e9d2f2821a8a87063c88dc9d43d10f9c11` | 分支犯罪警示 Provider **IMPLEMENTED_NOT_WIRED**，不在目前 main。已合入 feature branch，不能算 main 成果；直接讀官方 CSV，不讀 Supabase。 | M4 信義審來源，M1／M2／M3依 DI 接線；共用內部模型依 Level B 確認。既有資料／smoke 記錄只能證明該 SHA 範圍，重新整合後補端到端與裝置證據。 |
| [PR #44](https://github.com/csfishy/taipei-safe-walk-townpass/pull/44)，head `9f6de4e0f959fa21b6222ee3d79749abf0ae5b65` | 私有持久快照／人工管理套件在分支有實作；App 讀取仍 **NOT_IMPLEMENTED**。目前 main 沒有此套件，PR 仍待審，不能列 main 已交付。 | M4 信義、M1 小魚及隊長審 Level C 與既有匯入收據；不能把離線 SQLite 查詢稱為 App 的 Supabase Repository。 |
| main Supabase client／連線 probe：[supabase_connection.dart:34–54][supabase-probe]；[Supabase 文件][supabase-doc] | **IMPLEMENTED_NOT_WIRED**。client 設定、明確呼叫的唯讀可達性診斷已存在；不等於可讀 crime_reference，也不驗資料列權限。 | M1 小魚以所需資料契約實作真正讀取流程。不能為了連通而把管理 key 放 App，或沿用 nearby RPC 當健康檢查。 |
| crime_reference 的 App 唯讀 Repository／API | **NOT_IMPLEMENTED**；正式資料權限／接口啟用在完成設計與審查前 **BLOCKED**。這是程式缺口與安全門檻兩個不同事實，不將整個資料功能籠統標成完成或全域 BLOCKED。 | 下一步是獨立 Level C PR：選定可公開的固定欄位投影與受眾，或設計可信身分授權；限定已驗 snapshot、查詢範圍、分頁／上限與唯讀行為。以隔離 DB 驗未授權／跨權限拒絕、不可寫、限額、空值／過期／取消，再經授權受控驗真後端。不能直接 grant private 三表，也不能把 service_role／postgres 交給 App。 |

### #39：可比較的範圍很有限

[來源文件第 11–19 行][crime-warning-data] 記錄三個官方資料集：婦幼警示 22 筆、搶奪 54 筆、強盜 26 筆，原始 CSV 均無經緯度。婦幼資料檔名是 115 上半年，資源更新 2026-07-27；發布日不當發生日，逐列無明確期間即保留 null。另兩類歷史地址已模糊化，不得還原成精確犯罪發生點。

[同文件第 29–48 行][crime-warning-geography] 與 [模型第 279–329 行][crime-warning-eligibility] 限制精度、授權、時間及幾何：來源年齡 190 天、mapping 核對期限 90 天；這是工程門檻，不是官方有效期限。目前只查證婦幼警示中的二二八和平公園範圍，主要來源覆蓋 **1/22＝4.55%**，三來源合計 **1/102＝0.98%**，其餘 101 筆不作精確路段懲罰。已查證場所範圍不是犯罪點、範圍外也不代表安全；未知 accuracyMeters 保留 null。

M1 可在 composition 注入共享契約，M3 呈現來源、日期及未定位筆數；M2 只能用符合適用條件的幾何比較真路網候選，不能改畫任意 polyline。必須保留未定位資料，不能把「無可靠幾何」顯示成「沒有警示」。

### #44：持久快照不是 Demo seed，也不是可直接避讓的幾何

[分支文件第 17–42 行][crime-database-evidence] 記錄 2026-11-07 在既有 `gxofnhzkqcmzrftxqddi` 匯入 snapshot `5ea3810c-5744-4b89-baad-0121c8fc951b`：**2542** 來源紀錄、**1366** 參考定位、**1176** 空座標；臺北 617、新北 970、基隆 955。這是分支文件及收據的歷史記錄，本次未查遠端，不能重新宣告當前雲端資料／權限驗證通過。跨來源未以共同案件 ID 去重；各來源案件分別截至 9/29、6/30、9/30，不是三市全年／全案類或即時風險。

原案件檔沒有原生座標。官方門牌／捷運出入口的離線參考定位、候選分布上限、臺北門牌 CRS 推定及整條道路集合，都不能變成已確認犯罪路段。`reference_geocoded`／`high` 是文字匹配語意，**不能直接轉成 #39 的 confirmedPublicPlace／verified**；候選半徑不是精度保證，null 不補行政區中心。未經另行查證的點不進精確道路避讓。

來源 manifest、案件資料與定位證據保存在 Git 外；本次只能核對文件中的雜湊及描述，未重新逐一驗證八資料集的來源內容／授權。App 投影與正式查詢前，M4 必須提供可審查的來源／授權、取得／更新日期、涵蓋範圍與幾何適用性證據；資料量不等於合法性或定位可靠性。

[人工初始化 SQL 第 24、133–147 行][crime-database-security] 撤銷 PUBLIC／anon／authenticated／service_role，三表啟用 FORCE RLS，只保留 postgres 人工讀／寫 policy；不可透過 App 公開 key 直接讀取，也沒有對外 RPC。UPDATE／DELETE／TRUNCATE 另有拒絕 trigger，但管理者仍可改 DDL／新增，不能稱管理者不可修改。[查詢範例][crime-query] 是人工只讀 SQL，不是 App API。

最小可實作方案是先在隔離 DB 與 fake transport 建立**固定欄位、指定已驗 snapshot、範圍／分頁有上限**的只讀接口和 Repository，再由 M1 注入 M2／M3。共享 DTO 保留來源、日期、coordinate_status、精度、限制與空座標；不回傳不必要 raw payload、不接使用者位置寫入、不新增任意 SQL／管理接口。投影對象、身分／ACL、配額與資料暴露範圍是 Level C 的具體審查項目；未完成顯示 Unavailable＋原因＋下一步，不能先 grant private 或以 Mock 補資料。

### 持久資料與 reset 的不可跨越邊界

- `crime_reference` 與原案件／來源／定位證據是持久參考資料。build、CI、App 啟動、測試初始化、Demo seed／reset **不得 import、seed、update、delete、truncate、drop 或重建它**。更新只能在另行授權的可信人工流程新增已驗版本；不可為重跑編譯而重新灌入，也不把真實資料包進 assets、Web ZIP、APK 或 IPA。
- main [reset script:24–27][reset-script] 固定 schema／角色並保護既有 `gxofnhzkqcmzrftxqddi`；[第 154–165 行][reset-privileges] 拒絕非本案寫權限，[第 331–332 行][reset-truncate] 僅明列 `safe_walk_demo.alert_recipients`、`emergency_alerts`、`helpers`，無全庫 reset。[targets.json:3–4][reset-targets] 的 protected project 保留、Demo allowlist 為空。不能因正式資料整合而擴大此範圍。
- main [build.yml:182–214][demo-gate] 仍要求 main builds 成功後遠端 Demo reset；缺少設定會停止相關發布。[PR #47](https://github.com/csfishy/taipei-safe-walk-townpass/pull/47) 的明確啟用修正尚待合併，不能把 pending 行為寫成 main 已有。文件 PR 不新增 Secrets、不開旗標、不執行 reset 或發布。
- 舊 [nearby_emergency.sql:139–141][unsafe-nearby] 的 anon RPC、匿名 UUID／ownership 缺口與持久歷史資料查詢是不同能力。附近位置通知仍 BLOCKED，不得藉 LIVE-FIRST 或資料只讀接口開啟；Auth、public、Production／真使用者資料皆不得納入 reset。

## 後續工程與 PR 協調

Phase A 只建立誠實基線。Phase B 應以完整使用者流程的小 PR 實作，記錄 base／head SHA、改動檔案、功能主責與原領域聯絡人、契約／審查層級、實際測試及未驗部分；完成證據另附後續 PR／驗收文件，不修改本基線讓它看似原先已完成。

開始程式修改前重新核對未合併 PR 與同檔案實作者，尤其 [#36](https://github.com/csfishy/taipei-safe-walk-townpass/pull/36)／[#46](https://github.com/csfishy/taipei-safe-walk-townpass/pull/46) 的 UI、[#41](https://github.com/csfishy/taipei-safe-walk-townpass/pull/41)／[#42](https://github.com/csfishy/taipei-safe-walk-townpass/pull/42) 的援助流程、#39 資料、#44 持久 DB 及 #47 CI gate；這是需核對的重疊清單，不保證將來 PR 狀態不變，也不授權覆寫分支或自動 merge。

可並行完成純邏輯、同意／取消與 Unavailable 呈現；共享契約／官方 route／重大 UI／CI 依 Level B，Supabase 身分／正式唯讀權限／RPC／RLS、敏感位置、正式外部作用及啟用依 Level C。測試可用人工資料與 Fake；Production 正常入口只使用真實且完成適用驗收的能力。尚未驗證就保留對應狀態，不以全域 Mock 永久封鎖導航／查詢／TTS，也不為追求 Live 而放寬高風險能力。

[townpass-service]: https://github.com/csfishy/taipei-safe-walk-townpass/blob/7b99fea4e4e3b71da1e265cc99d9e9d7c8266834/lib/page/city_service/model/my_service_model.dart#L187
[townpass-route]: https://github.com/csfishy/taipei-safe-walk-townpass/blob/7b99fea4e4e3b71da1e265cc99d9e9d7c8266834/lib/util/tp_route.dart#L83
[root]: https://github.com/csfishy/taipei-safe-walk-townpass/blob/7b99fea4e4e3b71da1e265cc99d9e9d7c8266834/lib/features/safe_walk/platform/integration/safe_walk_composition_root.dart#L77
[root-scope]: https://github.com/csfishy/taipei-safe-walk-townpass/blob/7b99fea4e4e3b71da1e265cc99d9e9d7c8266834/lib/features/safe_walk/platform/integration/safe_walk_composition_root.dart#L295
[root-emergency]: https://github.com/csfishy/taipei-safe-walk-townpass/blob/7b99fea4e4e3b71da1e265cc99d9e9d7c8266834/lib/features/safe_walk/platform/integration/safe_walk_composition_root.dart#L276
[root-speaker]: https://github.com/csfishy/taipei-safe-walk-townpass/blob/7b99fea4e4e3b71da1e265cc99d9e9d7c8266834/lib/features/safe_walk/platform/integration/safe_walk_composition_root.dart#L153
[root-locate]: https://github.com/csfishy/taipei-safe-walk-townpass/blob/7b99fea4e4e3b71da1e265cc99d9e9d7c8266834/lib/features/safe_walk/platform/integration/safe_walk_composition_root.dart#L232
[flow]: https://github.com/csfishy/taipei-safe-walk-townpass/blob/7b99fea4e4e3b71da1e265cc99d9e9d7c8266834/lib/features/safe_walk/presentation/safe_walk_flow.dart#L17
[map-view]: https://github.com/csfishy/taipei-safe-walk-townpass/blob/7b99fea4e4e3b71da1e265cc99d9e9d7c8266834/lib/features/safe_walk/presentation/safe_walk_map_view.dart#L116
[demo-map]: https://github.com/csfishy/taipei-safe-walk-townpass/blob/7b99fea4e4e3b71da1e265cc99d9e9d7c8266834/lib/features/safe_walk/presentation/demo_map.dart#L21
[emergency]: https://github.com/csfishy/taipei-safe-walk-townpass/blob/7b99fea4e4e3b71da1e265cc99d9e9d7c8266834/lib/features/safe_walk/presentation/safe_walk_emergency_view.dart#L198
[call-view]: https://github.com/csfishy/taipei-safe-walk-townpass/blob/7b99fea4e4e3b71da1e265cc99d9e9d7c8266834/lib/features/safe_walk/presentation/safe_walk_call_view.dart#L64
[gps-adapter]: https://github.com/csfishy/taipei-safe-walk-townpass/blob/7b99fea4e4e3b71da1e265cc99d9e9d7c8266834/lib/features/safe_walk/platform/townpass_platform_adapter.dart#L27
[native-gps]: https://github.com/csfishy/taipei-safe-walk-townpass/blob/7b99fea4e4e3b71da1e265cc99d9e9d7c8266834/lib/service/geo_locator_service.dart#L9
[tts-speaker]: https://github.com/csfishy/taipei-safe-walk-townpass/blob/7b99fea4e4e3b71da1e265cc99d9e9d7c8266834/lib/features/safe_walk/platform/integration/tts_safe_walk_speaker.dart#L14
[preview-speaker]: https://github.com/csfishy/taipei-safe-walk-townpass/blob/7b99fea4e4e3b71da1e265cc99d9e9d7c8266834/lib/features/safe_walk/presentation/safe_walk_speaker.dart#L25
[osrm]: https://github.com/csfishy/taipei-safe-walk-townpass/blob/7b99fea4e4e3b71da1e265cc99d9e9d7c8266834/lib/features/safe_walk/navigation/osrm_walking_route_provider.dart#L27
[transport-selector]: https://github.com/csfishy/taipei-safe-walk-townpass/blob/7b99fea4e4e3b71da1e265cc99d9e9d7c8266834/lib/features/safe_walk/navigation/default_json_transport.dart#L1
[io-transport]: https://github.com/csfishy/taipei-safe-walk-townpass/blob/7b99fea4e4e3b71da1e265cc99d9e9d7c8266834/lib/features/safe_walk/navigation/io_json_transport.dart#L10
[unsupported-transport]: https://github.com/csfishy/taipei-safe-walk-townpass/blob/7b99fea4e4e3b71da1e265cc99d9e9d7c8266834/lib/features/safe_walk/navigation/unsupported_json_transport.dart#L4
[follower]: https://github.com/csfishy/taipei-safe-walk-townpass/blob/7b99fea4e4e3b71da1e265cc99d9e9d7c8266834/lib/features/safe_walk/navigation/route_follower.dart#L73
[osm-stores]: https://github.com/csfishy/taipei-safe-walk-townpass/blob/7b99fea4e4e3b71da1e265cc99d9e9d7c8266834/lib/features/safe_walk/navigation/osm_convenience_store_source.dart#L25
[store-planner]: https://github.com/csfishy/taipei-safe-walk-townpass/blob/7b99fea4e4e3b71da1e265cc99d9e9d7c8266834/lib/features/safe_walk/navigation/nearest_store_planner.dart#L85
[city-crime]: https://github.com/csfishy/taipei-safe-walk-townpass/blob/7b99fea4e4e3b71da1e265cc99d9e9d7c8266834/lib/features/safe_walk/safety_data/violent_crime/README.md#L5
[city-limitations]: https://github.com/csfishy/taipei-safe-walk-townpass/blob/7b99fea4e4e3b71da1e265cc99d9e9d7c8266834/lib/features/safe_walk/safety_data/violent_crime/violent_crime_normalizer.dart#L47
[supabase-probe]: https://github.com/csfishy/taipei-safe-walk-townpass/blob/7b99fea4e4e3b71da1e265cc99d9e9d7c8266834/lib/features/safe_walk/platform/supabase/supabase_connection.dart#L34
[supabase-doc]: SAFE_WALK_SUPABASE.md
[crime-warning-data]: https://github.com/csfishy/taipei-safe-walk-townpass/blob/d39608e9d2f2821a8a87063c88dc9d43d10f9c11/docs/SAFE_WALK_CRIME_WARNING_DATA.md#L11
[crime-warning-geography]: https://github.com/csfishy/taipei-safe-walk-townpass/blob/d39608e9d2f2821a8a87063c88dc9d43d10f9c11/docs/SAFE_WALK_CRIME_WARNING_DATA.md#L29
[crime-warning-eligibility]: https://github.com/csfishy/taipei-safe-walk-townpass/blob/d39608e9d2f2821a8a87063c88dc9d43d10f9c11/lib/features/safe_walk/shared/models/crime_warning.dart#L279
[crime-database-evidence]: https://github.com/csfishy/taipei-safe-walk-townpass/blob/9f6de4e0f959fa21b6222ee3d79749abf0ae5b65/docs/SAFE_WALK_CRIME_DATABASE.md#L17
[crime-database-security]: https://github.com/csfishy/taipei-safe-walk-townpass/blob/9f6de4e0f959fa21b6222ee3d79749abf0ae5b65/supabase/crime_reference/01_initialize.sql#L133
[crime-query]: https://github.com/csfishy/taipei-safe-walk-townpass/blob/9f6de4e0f959fa21b6222ee3d79749abf0ae5b65/supabase/crime_reference/03_query_examples.sql#L1
[reset-script]: https://github.com/csfishy/taipei-safe-walk-townpass/blob/7b99fea4e4e3b71da1e265cc99d9e9d7c8266834/scripts/reset_demo_database.py#L24
[reset-privileges]: https://github.com/csfishy/taipei-safe-walk-townpass/blob/7b99fea4e4e3b71da1e265cc99d9e9d7c8266834/scripts/reset_demo_database.py#L154
[reset-truncate]: https://github.com/csfishy/taipei-safe-walk-townpass/blob/7b99fea4e4e3b71da1e265cc99d9e9d7c8266834/scripts/reset_demo_database.py#L331
[reset-targets]: https://github.com/csfishy/taipei-safe-walk-townpass/blob/7b99fea4e4e3b71da1e265cc99d9e9d7c8266834/supabase/demo/targets.json#L3
[demo-gate]: https://github.com/csfishy/taipei-safe-walk-townpass/blob/7b99fea4e4e3b71da1e265cc99d9e9d7c8266834/.github/workflows/build.yml#L182
[unsafe-nearby]: https://github.com/csfishy/taipei-safe-walk-townpass/blob/7b99fea4e4e3b71da1e265cc99d9e9d7c8266834/supabase/nearby_emergency.sql#L139
