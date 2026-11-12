# 臺北安心行：離線能力需求（A 斷網處理／B 離線底圖／C 裝置端步行路線）

> 狀態：Live 交付需求（2026-11-12）。三項能力都以「正式入口可實際操作的 Live 版本」交付，不另做 Mock／Demo／原型 PR；本文件不代表任何能力已完成。Readiness 狀態仍以 [Readiness](SAFE_WALK_LIVE_READINESS.md) 與實際 PR／裝置證據為準。
> 開工前先讀 [AGENTS.md](../AGENTS.md)、[協作規範](SAFE_WALK_COLLABORATION.md)、[Live-first](SAFE_WALK_LIVE_FIRST.md)、[導航 README](../lib/features/safe_walk/navigation/README.md)。本文件不放寬其中任何安全、誠實或授權規定。

## 0. 現況盤點（main `7a77ef7`，2026-11-12）

| OSM 資料 | 目前位置 | 斷網時行為 |
|---|---|---|
| 便利商店／派出所 | `assets/safe_walk/osm_help_points_taipei.json`（3,469 筆：商店 3,247、派出所 222；`retrievedAt` 2026-11-07；bbox 24.96,121.45–25.21,121.67），由 `safe_walk_composition_root.dart` 以 `rootBundle` 載入 `OsmHelpPointSnapshot` | 可查；**但**附近求助流程（`_planNearby`）在全部路線規劃失敗時回「暫時無法規劃步行路線」並清掉清單，使用者看不到本機已有的據點 |
| 地圖圖磚 | 正式地圖 `safe_walk_map.dart`（`SafeWalkMap`）與住家設定頁 `safe_walk_home_setting_view.dart` 各自的 `TileLayer`：`https://tile.openstreetmap.org/{z}/{x}/{y}.png` + `NetworkTileProvider`（只快取看過的圖磚） | 未看過的區域空白，無提示 |
| 步行路線 | `ValhallaAvoidingRoutePlanner`（valhalla1.openstreetmap.de）→ 失敗時 `AvoidingRouteService.fallback` 用 OSRM（routing.openstreetmap.de） | 兩者皆需網路，回 `provider_unavailable` |
| 避讓區域 | `_areas`（通報，Supabase）＋`_crimeAreas`（犯罪參考，Supabase RPC），只存在記憶體 | 未載入前斷網則為空集合 |

**已排除的方案：** 用 `flutter_map_tile_caching` 等工具從 `tile.openstreetmap.org` 預先下載圖磚。OSMF 圖磚政策把「使用者未在檢視的預先抓取（含打包為 .zip／.mbtiles）」定義為批次下載並禁止；另「發佈大量使用該圖磚的 App 需事先許可」。離線底圖的資料來源必須是我們自己由 OSM 原始資料產生的檔案。

## 1. 共通原則

1. **Live-first 不變。** 離線能力是真實資料的另一個來源，不是 Mock。不得用直線、示範座標、虛構店家或固定成功冒充步行路線或即時資料。
2. **離線資料一律揭露快照日期與限制。** 每個離線結果在 UI 與 `SourceMetadata`／warnings 帶上快照日期（例：「離線路網資料：2026-11-07 快照」）。
3. **ODbL 義務。** 打包的向量圖磚與路網圖都是 OSM 衍生資料庫：保留「© OpenStreetMap contributors」標示，在 `safe_walk_sources.dart` 新增來源項，產生腳本與參數放在 repo 內可重現（repo 已公開，即滿足提供衍生資料庫的方式）。
4. **斷網偵測不新增 connectivity 套件。** 以既有 transport 例外（`JsonTransportException`、逾時）與圖磚載入錯誤判定「連不上服務」；不宣稱「裝置沒有網路」，文案用「目前連不上地圖／路線服務」。
5. **不持久化敏感位置。** 通報與犯罪參考座標只用當次記憶體內已取得的資料；寫入裝置儲存屬 Level C（敏感位置儲存），**不在本需求範圍**。
6. **不改 canonical Schema。** 以既有欄位（provider 字串、warnings、`SourceMetadata`）表達離線來源；若確需新欄位，另開 Schema PR（Level B）。
7. **平台範圍。** 離線能力以 iOS／Android 原生為目標；Web 預覽維持現行線上行為，不得因此壞掉（以條件 import 隔離）。
8. Flutter 依 `.fvmrc` 維持 3.47.6；新增依賴與 `pubspec.lock` 變更屬 Level B（M1 小魚確認）。
9. **完成定義（Live）：** 每項能力須同時滿足——
   - 從 TownPass 正式 Safe Walk 入口（非 preview／live-check 測試入口）、`liveRoutes` 開啟的實際組合可操作；
   - 使用真實產生並 commit 的資料檔（圖磚、路網），不是樣本或 fixture；
   - 錯誤、取消、逾時、範圍外、資料缺失皆有正式 UI 與文案；
   - 單元／整合測試通過，Readiness 更新為 WIRED_NOT_VERIFIED，並附 iPhone 飛航模式驗收步驟清單；實機驗收完成後才改 LIVE_VERIFIED。
   - 若發現正式入口本身仍未走 Live（Readiness 曾記錄正式入口固定 Mock），先回報並在同一任務補上必要接線，不能只做出無法從正式入口使用的元件。

---

## A. 斷網時的處理（優先，Level A）

### A1 目標
連不上路線／圖磚服務時，使用者仍能看到附近營業中的便利商店與派出所（來自本機快照），並清楚知道「目前無法規劃步行路線」與下一步（緊急求助、稍後重試）。

### A2 需求
- **A2.1 附近求助清單不因路線失敗而消失。** `_planNearby` 在取得據點後，若所有據點路線都失敗且失敗原因屬連線類（`provider_unavailable`／transport 例外／逾時），改為呈現「僅據點、無路線」清單：
  - 每筆顯示名稱、類型、營業狀態（沿用 `OsmHelpPointSnapshot` 判定）、**直線距離與方位**（例：「直線約 320 公尺，東北方」）。
  - 明確標註「直線距離，非步行路線」；**不得在地圖上畫直線或任何路徑**，只標點。
  - 提供「重試規劃路線」與既有「緊急求助」入口。
  - 來源列顯示「OpenStreetMap 快照（2026-11-07）」與既有 limitations。
- **A2.2 路線失敗文案區分原因：** 連不上服務／無路線（`no_route`）／起訖點問題／取消，各自顯示不同訊息與下一步；不得一律顯示「請稍後再試」。
- **A2.3 圖磚失敗提示：** `TileLayer` 載入錯誤（`errorTileCallback` 或等效）在短時間內累積達門檻時，地圖上方顯示非阻斷式提示「目前無法載入地圖底圖，標示的位置仍正確」；恢復後自動隱藏。點位、路線、避讓圓照常繪製。
- **A2.4（D1 已決定）本機據點清單只需定位權限：** 本機快照查詢不送出任何資料，依「定位權限與第三方同意分開」原則，只需定位權限即可顯示 A2.1 清單；路線規劃仍需原本的第三方同意。
- **A2.5 不改變正常流程：** 連線正常時行為、排序、`pickNearbyCandidates` 參數、取消與遲到結果處理維持原樣。

### A3 驗收
- Widget／整合測試以注入的 `routeService` 模擬：全部 `provider_unavailable`、部分成功、`no_route`、取消、遲到結果；驗證清單、文案、不畫直線。
- 圖磚錯誤以 `SafeWalkMap.tileProviderFactoryForTesting` 注入失敗 provider 驗證提示出現／消失。
- `flutter analyze`、`flutter test` 通過；iPhone 開飛航模式實機截圖（人工位置，說明證據限制）。
- Readiness：新增或更新相應列為 WIRED_NOT_VERIFIED，實機後才可評估 LIVE_VERIFIED。

---

## B. 離線底圖（Level B：依賴、資產、原生大小）

### B1 目標
不依賴 `tile.openstreetmap.org`，在臺北快照範圍內（同 bbox 24.96,121.45–25.21,121.67，可外擴 1 km）離線顯示可閱讀的街道底圖（道路、路名、建物、水系、公園、捷運站），步行導航常用縮放 z12–z18 清楚。

### B2 階段

**B-0 方案選定（在同一個實作任務內完成，不另交原型 PR；結果寫入本文件 §B5）**
- 驗證在 Flutter 3.47.6 stable + `flutter_map ^8.3.2` 下可用的向量圖磚方案：
  - 候選 1：`vector_map_tiles`（**不可用 10.x**：依賴 flutter_gpu，僅 main channel）＋ `vector_map_tiles_pmtiles` 讀本機 `.pmtiles`。
  - 候選 2：`vector_map_tiles` ＋ MIT 授權的 `.mbtiles` 讀取器（如 `alfa_vector_mbtiles`）。
  - 備案：自行渲染點陣 `.mbtiles`（z12–z17，臺北範圍）＋ flutter_map 的 MBTiles 點陣 provider。
- 量測：檔案大小、iPhone／中階 Android 首次載入時間、平移縮放 FPS、記憶體、中文路名字型顯示。
- 依序嘗試，**第一個在 3.47.6 stable 可編譯、繁中路名可讀、iOS／Android 皆可運作者即採用**；全部失敗才用點陣備案。不得因選型困難停在報告。
- 產出：選定方案、版本鎖定、量測數據、授權清單（每個套件與樣式檔的授權），寫入 §B5 並隨實作 PR 提交。

**B-1 資料產生工具**
- 新增 `tool/offline_map/`：從 Geofabrik 臺灣 `.osm.pbf` 以 planetiler 產生臺北範圍向量圖磚。
- 圖磚 schema／樣式優先選擇授權義務最少者（建議 Protomaps basemap schema 與其樣式；若用 OpenMapTiles schema，需另加 OpenMapTiles 標示並確認 CC-BY 義務）。**選定前在 PR 列出授權依據。**
- 輸出 `taipei.pmtiles`（或 `.mbtiles`）＋ `taipei_basemap.meta.json`（來源 pbf 名稱與日期、bbox、zoom 範圍、工具版本、SHA-256、授權字串）。
- 中文字型：樣式使用的 glyph 需支援繁中；說明來源與授權（不得假設 PingFang 可再散布）。
- 腳本可重現、不在 CI 自動下載大型資料（CI 只驗 meta 與 SHA-256）。

**B-2 打包與載入**
- （D2 已決定）資產直接放 `assets/safe_walk/map/` 並列入 `pubspec.yaml`，單檔須 ≤ 50 MB；超過時降低最大縮放（例如 maxzoom 15，z16–z18 以 overzoom 顯示）或縮小外擴範圍，直到符合。不使用執行期下載。
- PMTiles 需要檔案路徑時，首次使用把 asset 複製到 App 支援目錄（以 meta 中 SHA-256 判斷是否需更新），失敗時回退到線上圖磚並顯示提示。
- 正式地圖 `SafeWalkMap` 與住家設定頁 `safe_walk_home_setting_view.dart` 共用同一個底圖來源選擇（抽出共用 builder，不各寫一份）：`offline`（預設，原生）／`online`（Web、或離線檔不可用時）。範圍外區域顯示線上圖磚（若可連線）或灰底＋「離線地圖範圍外」提示。
- 保留 `tileProviderFactoryForTesting` 等測試注入點；新增離線圖層的測試注入點。
- 地圖角落 attribution 改為「© OpenStreetMap contributors」＋所選 schema／樣式要求的標示，點擊開啟版權頁（沿用現有行為）。

**B-3 文件與來源**
- `safe_walk_sources.dart` 新增「離線底圖（OSM 快照 YYYY-MM-DD）」來源項；更新 Readiness R5 列與本文件 §B5。

### B3 驗收
- 飛航模式下，臺北範圍內 z12–z18 底圖完整、路名可讀；範圍外提示正確。
- APK／IPA 大小增量、首次啟動複製耗時、記憶體記錄於 PR。
- 無任何請求送往 `tile.openstreetmap.org`（原生、離線模式時）；以網路紀錄或 mock transport 驗證。
- `flutter analyze`、`flutter test`、Web build 不壞；CI 的 APK／IPA 檢查（`tool/verify_native_release.py`）依新資產調整並通過。

### B5 Live-B 實作與方案選定（2026-11-13）

工作分支 `feat/offline-live-b` 保留既有歷史，以 fast-forward 更新至最新
`origin/feat/offline-map` **`04337aa0eb2db24a728216eed36716d57d075da3`**；PR 目標仍為
`feat/offline-map`，不 merge。正式 `TPRoute.safeWalk` 已設 `liveRoutes: true`，
本次直接接 `SafeWalkMap` 與住家選點，不另建 preview 入口。

| 順序 | 結果／依據 |
|---|---|
| a：vector_map_tiles + PMTiles | Flutter 3.47.6 下 `flutter pub get` 失敗。`vector_map_tiles_pmtiles 1.5.2` → `pmtiles ^1.3.0` → `latlong2 ^0.9.0`，與 App `^0.10.1` 衝突；不 override、不降級既有 map 套件。 |
| b：vector_map_tiles + MIT MBTiles adapter | 選用 `vector_map_tiles 9.0.0-beta.13`（BSD-3-Clause）、`vector_map_tiles_mbtiles 1.2.2`（MIT）、`mbtiles 0.5.1`（BSD-3-Clause）、`vector_tile_renderer 6.1.0`（BSD-3-Clause）。依賴解析成功；真實全檔可解碼與離線渲染繁中。舊 `alfa_vector_mbtiles 0.0.6` 限 flutter_map 4／latlong2 0.8，不採用。原生雙平台編譯證據以本 PR Checks 為準，未完成前不得宣稱通過。 |
| c：點陣 MBTiles | b 已可解依賴與渲染，未採用；若原生編譯發現不可修復問題，須在同一任務繼續此備案。 |

實際鎖定版本見 `pubspec.lock`，不使用 vector_map_tiles 10.x。新增依賴／資產／CI／封包驗證
為 Level B，依現行 AGENTS 的活動後分工由 M1 小魚記錄確認，尚未 merge。

- 完整產製工具與授權：[tool/offline_map/README.md](../tool/offline_map/README.md)。
  使用 Java 21、Planetiler 0.10.2、固定 Protomaps profile commit，臺灣 PBF 與 Live-C #102
  同為 **2026-11-11**，SHA `6d9b7a214e7617df8473e311466e0a2517209d937c579f6a2134a64421cc838d`。
  D4 同日求助點已在 #102 產製，本 PR 不覆寫父分支既有快照；整合時一併採用。
- `taipei.mbtiles` **26,607,616 bytes**，完整 bbox **24.95,121.44–25.22,121.68**；
  z12–z15，z16–z19 overzoom；SHA 與圖磚數見同目錄 meta。字型獨立檔 **16,435,884 bytes**，
  各單檔低於 50,000,000 bytes。不是從 OSM 圖磚伺服器批次下載。
- Protomaps v4 schema／light 樣式，設計 CC0、程式 BSD-3-Clause；繁中字型 Noto Sans CJK TC
  OFL-1.1（隨附授權）。Flutter 直接渲染 OTF，不使用遠端 glyph/sprite，也不依賴 PingFang 再散布。
  稠密巷弄名稱於 z17 起顯示，捷運／火車站增加文字標示。快照不保證現況、可通行或安全。
- 兩地圖共用 `SafeWalkBasemap`，原生預設離線；準備中不建立線上 provider。
  先驗證支援目錄檔案 SHA，必要時從 asset 複製、重新驗 SHA、atomic rename；失敗提示後回退線上。
  範圍外灰底＋「離線地圖範圍外」，不暗中送出 OSM 請求。Web 條件 import 保持線上。
- CI 只驗 meta 與 SHA。native verifier 驗封包內圖磚／樣式／字型與 meta；犯罪資料隔離 guard
  僅容許此公開底圖的**確切路徑＋固定內容 SHA**，其他 SQLite／犯罪資料、改名冒充或包內未知檔仍拒絕。

本機測試包含：原生準備／成功不建網路圖層、範圍內外、複製失敗回退、Web 不開離線檔、
遲到載入釋放、SHA 暖載入／損毀修復／新版本、真實全檔 z12／z15 解碼與 Noto 繁中渲染。
Windows 渲染測試不代表 iPhone／Android 效能。APK／IPA 增量、首次複製時間、雙平台編譯、
analyze／完整 tests／Web build 的當次結果記錄在 PR，不能以工具存在或測試替身宣稱通過。
實體 iPhone／中階 Android 的 FPS、記憶體、飛航模式、VoiceOver 仍需 §4 驗收，狀態維持
**WIRED_NOT_VERIFIED**；尚無實機證據不得改成 LIVE_VERIFIED。

---

## C. 裝置端步行路線（Level A 程式＋Level B 資產／依賴）

### C1 目標
連不上 Valhalla／OSRM 時，仍能在臺北快照範圍內，於裝置上以真實 OSM 步行路網計算路線，並套用同樣的三級避讓（`AvoidLevel.full`／`center`／`none`）與轉彎提示。

### C2 路網資料（`tool/offline_route/`）
- 從與 B 相同的 Geofabrik 臺灣 pbf 擷取同一 bbox（外擴 1 km）的步行可通行路段：
  - 納入：`highway` ∈ {footway, pedestrian, path, steps, living_street, residential, service, unclassified, tertiary, secondary, primary, track, corridor, crossing 相關} 及 `foot=yes|designated|permissive`；
  - 排除：`foot=no`、`access=private|no`（無 foot 例外者）、`highway=motorway|motorway_link|trunk|trunk_link`（無明確步行許可者）、施工中路段。
  - 規則寫成設定檔並附測試，PR 列出與 OSRM foot profile 的差異。
- 輸出精簡二進位 `taipei_walk_graph.bin`（建議 CSR：節點 lat/lng 以 1e-7 int32、邊長公尺 uint16/32、街名索引、每邊 flags），加 `taipei_walk_graph.meta.json`（來源日期、bbox、節點／邊數、SHA-256、規則版本、授權）。
- 目標（需實測後修正）：檔案 ≤ 15 MB、於 isolate 載入 ≤ 1.5 s（中階手機）。

### C3 路線計算（`lib/features/safe_walk/navigation/offline_graph_route_planner.dart`）
- 實作既有 `AvoidingRoutePlanner` 介面，與 `ValhallaAvoidingRoutePlanner` 回傳相同形狀的 `AvoidRouteOption` 清單。
- 圖在 isolate 中載入與計算（不阻塞 UI）；支援 `SafeWalkCancellation`。
- 起訖點吸附到最近可通行路段，超過既有 `maxEndpointSnapMeters`（500 m）回 `provider_unavailable`，訊息說明「離線路網範圍外或附近無步行路段」。
- A* ＋ 球面距離啟發式。避讓：
  - `full`：排除與任何 `AvoidArea` 圓（半徑 50 m）相交的邊；
  - `center`：排除距圓心 < `AvoidArea.centerRadiusMeters`（15 m）的邊；
  - `none`：不排除。
  - 起點或終點位於圓內時，比照 Valhalla 版處理並加上 `AvoidingRouteService.insideWarning`；`passedAreaIds` 依實際幾何計算（優先沿用 `navigation/coordinate_math.dart`、`route_reference_area_check.dart` 既有的距離函式，不重複實作）。
- 轉彎提示：以節點方位角變化與街名變化產生 `List<RouteInstruction>`（`TurnKind` 角度門檻寫成常數並測試），無名路段 `street: null`；合併同名連續路段。
- 回傳 `RouteCandidate`：`walkingNetworkVerified: true`、provider id `offline-osm-graph`，warnings 必含「離線路網資料：YYYY-MM-DD 快照，可能與現況不同」。不得帶任何 mock 字樣。

### C4 接線（`platform/integration/`）
- （D3 已決定，PR 中請 M2 Steven Review）順序：Valhalla（線上避讓）→ **離線路網（避讓）** → OSRM（線上、不避讓）。理由：連不上 Valhalla 時，多半 OSRM 也連不上；且離線版能避讓，比 OSRM 的一般路線更符合產品安全目標。
- 離線版不送出任何資料，**不需第三方路線同意**，但仍需定位權限與導航啟動狀態；`hasConsent` 邏輯拆成「第三方送出同意」與「導航作用中」兩個條件，離線版只檢查後者。
- 避讓區域取 `[..._areas, ..._crimeAreas]` 當下值；若因斷線未曾載入，warnings 加「目前未取得通報與犯罪參考位置，此路線未套用避讓」，並在 UI 顯示。
- `_storeRoutes`（附近據點路線）同樣受益：A 的「僅據點」清單在 C 完成後應自動恢復為「據點＋離線路線」。

### C5 驗收
- 單元測試：路段篩選規則、二進位格式讀寫、A* 正確性（小型手工圖）、三級避讓、起訖點在圓內、吸附失敗、取消、轉彎提示角度門檻與街名合併。
- 對照測試：選 10 組臺北實際起訖點，以 Valhalla 結果為參考，比較距離差（目標 ±25% 內）與避讓結果；離線結果不得穿過 `full` 等級應避開的圓。資料與結果存 `test/fixtures/offline_route/`（不含真實住家或個人位置）。
- 效能：3 km 路線計算 ≤ 500 ms（中階手機，目標值）；記錄於 PR。
- iPhone 飛航模式實走或模擬位置驗收（說明證據限制）。

---

## 2. 已決定事項

| ID | 事項 | 決定 | Review |
|---|---|---|---|
| D1 | A 的本機據點清單權限 | 只需定位權限，不需第三方路線同意 | M3 莅紋（呈現） |
| D2 | B／C 大型資產放置 | 放 repo assets，單檔 ≤ 50 MB；超過就降縮放或範圍，不做執行期下載 | M1 小魚 |
| D3 | 路線備援順序 | Valhalla → 離線路網 → OSRM | M2 Steven |
| D4 | 離線資料更新節奏 | 圖磚、路網與求助點快照用同一份 pbf、同日產生；隨版本更新 | M4 信義 |
| D5 | 圖磚 schema／樣式 | 優先 Protomaps schema 與樣式；不可行時改 OpenMapTiles 並加其標示 | M1 小魚 |

## 3. 交付拆分（每項都是可 Live 操作的完整功能）

| 交付 | 內容 | 層級 | 依賴 |
|---|---|---|---|
| Live-A | A 全部，接正式入口 | A | 無 |
| Live-C | 路網工具、真實 `taipei_walk_graph.bin`、`OfflineGraphRoutePlanner`、正式接線、同意拆分、文案、Readiness | B（資產）＋A | Live-A（可 stacked） |
| Live-B | 方案選定、圖磚工具、真實底圖檔、依賴、`SafeWalkMap` 離線圖層、來源、Readiness | B | 無（可與 Live-C 並行） |

**整合分支：** 所有離線相關修改集中在團隊 origin 的 `feat/offline-map`（自 main `7a77ef7` 建立）。各交付的工作分支從 `feat/offline-map` 最新 head 開出，PR 目標為 `feat/offline-map`；三項全部完成並依 §4 驗收後，再由 `feat/offline-map` 開 PR 回 main。開工前先將 main 的最新變更合入 `feat/offline-map`，不 force push、不 rebase 已推送的整合分支。

各交付可在同一分支內分多個 commit，必要時拆成 stacked PR，但**最後一個 PR 合併後必須是正式入口可用的狀態**，不留「工具已做、未接線」的中間成果當作完成。每個 PR 依 AGENTS.md 列出使用者功能、完成定義、主要檔案、影響模組／原主責、契約變更、層級、實際測試／skip、未驗部分及 Live／安全影響；不自動 merge、不 force push。

## 4. iPhone 飛航模式驗收清單（三項共用）

1. 連線狀態開啟 Safe Walk，確認正常流程不變（路線、據點、避讓）。
2. 開啟飛航模式（保留定位），重新進入 Safe Walk。
3. 底圖：臺北範圍內平移、縮放 z12–z18，路名可讀；移到範圍外出現提示。
4. 附近求助：可看到營業中據點；Live-C 完成前為「僅據點」清單，完成後為「據點＋離線路線」。
5. 目的地路線：規劃成功並顯示「離線路網資料：YYYY-MM-DD 快照」；若先前未載入避讓資料，出現「未套用避讓」提示。
6. 開始導航、偏離、重算、取消、背景、SOS 中斷皆正常。
7. 關閉飛航模式，確認自動回到線上路線與圖磚，提示消失。
8. 使用人工位置或模擬位置時，在證據中註明限制；不使用真實住家位置。

Live-B 補充驗收（裝置尚未執行）：記錄裝置／OS／build SHA，從正式入口與住家選點各測一次。
清除 App 資料後即開飛航模式，記錄首次 asset 複製耗時；再進入確認不重複複製。
臺北 bbox 內 z12–z18 看街道、繁中路名、建物、公園、水系與捷運站，平移到範圍外看灰底提示，
返回範圍內恢復。以 proxy／封包紀錄確認沒有 `tile.openstreetmap.org` 請求；其他路線服務請求
與圖磚分開記錄。測試注入複製失敗時須看到回退提示，恢復連線後才可取得線上底圖。
原生有效離線底圖在恢復連線後仍維持離線，Web 保持線上；上列第 7 步的線上回復不表示
原生需丟棄有效離線底圖。記錄首次／暖載入、FPS、峰值記憶體與包大小，未執行逐項寫明。
