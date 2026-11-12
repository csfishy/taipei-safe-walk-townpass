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

### C6 Live-C 實作與實測（2026-11-12）

`feat/offline-live-c` stacked 於 Live-A／PR #101 的 `9340b4c4262aab3a13434c561a9721a79cac91a4`，PR 目標 `feat/offline-map`（開工整合分支 SHA `3542156195cff7d032fecf704a5b683e24fa4a79`）。未合併，不代表 main 成果。Readiness：**WIRED_NOT_VERIFIED**，不宣稱 iPhone 或中階手機已驗收。

已下載 Geofabrik 真實 `taiwan-261111.osm.pbf`（來源快照 2026-11-11），SHA-256 `6d9b7a214e7617df8473e311466e0a2517209d937c579f6a2134a64421cc838d`。資料與產生器見 [tool/offline_route](../tool/offline_route/README.md)，規則為 `taipei-foot-v1`。路網及 3,699 筆 node／way 求助點以同一 PBF 於本次產生；Live-B 圖磚未在此項產生，應沿用相同來源 SHA／快照日，不能把更新需求當成已有圖磚。

| 量測項目 | 實測與限制 |
|---|---|
| bbox | 24.95,121.44–25.22,121.68 |
| 路網節點／有向邊 | 473,961／1,068,246；保留完整 way 形狀節點 |
| bin 大小 | 23,223,303 bytes（23.22 MB，22.15 MiB）；低於 50 MB 硬上限，**未達原 15 MB 目標** |
| bin SHA-256 | `736de50987c6c9c4333218909737eb4877f9d1b15188419b95cb3a597827543b` |
| 桌機檔案讀取＋SHA／完整結構驗證 | 427.463 ms |
| 約 3 km 三級路線計算（已載入圖） | 3,043.85 m／162.805 ms，含兩端線段吸附、三次 A*、避讓檢查與轉彎提示 |
| 冷 isolate 建立＋解析驗證＋3 km 規劃 | 560.543 ms；每次請求目前會建立 request isolate 並解析，取消會終止該 isolate |
| 十組真實公開地標對照 | 與 Valhalla 距離差 −6.002%～−0.542%，10/10 在 ±25%；10/10 full 結果所有線段均未觸及人工測試 50 m 圓（最小 51.341 m） |
| 裝置效能 | **未執行**中階手機 ≤1.5 s 載入／≤500 ms 規劃、記憶體與 iPhone 驗收，桌機數據不能替代 |

數據檔：[公開起訖點](../test/fixtures/offline_route/taipei_pairs.json)、[真實 Valhalla 回應](../test/fixtures/offline_route/valhalla_reference.json)、[Windows Dart 3.13.5 效能與距離結果](../test/fixtures/offline_route/desktop_results.json)。來源對照是 opt-in 線上驗證；一般測試只讀已存結果，不在 CI 查公共服務或下載 PBF。

正式 `TPRoute.safeWalk` 仍走 Live，已移除入口自動授第三方同意。使用者拒絕路線外傳同意仍可選本機路網；定位／前景導航狀態另檢查，背景、離開、取消、SOS 仍終止工作。預設原生組合順序為 Valhalla → offline-osm-graph → OSRM，目的地和 `_storeRoutes` 共用同樣組合，各次呼叫讀 `[..._areas, ..._crimeAreas]` 的當下記憶體值。未曾載入區域時正式 warnings／UI 顯示「目前未取得通報與犯罪參考位置，此路線未套用避讓」，只有部分資料時揭露未套用完整避讓；來源警語含 2026-11-11 快照日期。未把任何通報／犯罪位置寫入儲存，也未改 canonical Schema。

Level B：資產／pubspec／直接宣告既有 crypto 3.0.7／官方入口／release 檢查需 **M1 小魚確認**；D3 請 **M2 Steven Review**，D4 請 M4 信義核對。一般導航／UI 接線為 Level A。沒有部署、merge、通知／警消送出或新的 Level C 敏感儲存。

驗證命令與實際結果以 PR 為準；需完整執行 scoped analyze、完整 Flutter tests、Python 路網及 native release 測試、Schema／module guard、Web build。Windows 未產生本次 SHA 的 APK／IPA，`verify_native_release.py` 的真實封包驗證仍待原生 CI，不把工具單元測試或 `--help` 當封包通過。全專案 analyzer 若包含既有 lint，須與 scoped 結果分開報告。

本次在最新 Live-A `9340b4c` 上實跑：完整 `flutter test --no-pub` **1,276 通過、20 跳過、0 失敗**；scoped analyze（safe_walk／tool／tests／正式 route）零問題；Python 路網 5、native release verifier 19、metadata 7、workflow 4 項通過；codegen、固定 lock、Schema `--check`、正常 history/module guard、犯罪資料隔離、Markdown 本地連結與 diff check 通過；Web build 通過（flutter_tts 既有 Wasm dry-run 提示不等於 Wasm 編譯通過）。全目錄 `flutter analyze --no-pub` **失敗**：工作區既有 ignored `artifacts/` 歷史檔案缺生成程式，以及官方舊 lint，共 1,032 項（750 errors／26 warnings／256 infos），未修改那些檔案，不能列為 PASS。20 個跳過是既有 opt-in／裝置類案例，非本次真實路網測試跳過。iPhone、中階手機、當次 APK／IPA、飛航實走與原生 release 封包驗證未執行。

#### Live-C 的 §4 iPhone 驗收補充（尚未執行）

1. 記錄 build SHA、iPhone／iOS，從 TownPass 正式入口進入；使用公開地標人工或模擬位置，註明不是實走 GPS 證據。首次選擇拒絕第三方傳送同意，允許定位，確認仍能規劃 offline-osm-graph，沒有路線第三方外送。
2. 先在線上取得通報／犯罪參考避讓，再開飛航模式，規劃三種選項，核對 full 除端點圓例外外不觸及 50 m、center 不進 15 m；圓內起訖必須揭露無法完整避開。
3. 全新工作階段開飛航模式，確認「未套用避讓」與離線快照日；附近求助顯示「據點＋離線路線」，不顯示假 ETA 或用直線冒充步行路徑。
4. 開始、偏離重算、換目的地、取消、背景、返回、SOS：定位與 isolate 工作停止，遲到結果不得恢復。移到 bbox 外超過 500 m，確認 provider_unavailable 的範圍／步行路段提示；找不到連通路則顯示 no_route。
5. 範圍內底圖 z12–z18 驗收依 Live-B；本項只有路網，無底圖仍保留點位、路徑、避讓與既有載入提示。不得將未交付底圖列成通過。
6. 關閉飛航模式、明確同意第三方查詢並重新規劃，確認回 Valhalla；撤回同意後重新規劃應只用本機。回到線上不是暗中授權傳送位置。
7. 記錄冷／暖啟動、3 km 時間、記憶體、APK／IPA 大小增量、VoiceOver／文字放大與截圖；完成前維持 WIRED_NOT_VERIFIED。

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
