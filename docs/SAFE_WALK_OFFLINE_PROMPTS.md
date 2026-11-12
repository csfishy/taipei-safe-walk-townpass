# 離線能力：交給 Code 模式的提示詞（Live 交付版）

> 搭配 [SAFE_WALK_OFFLINE.md](SAFE_WALK_OFFLINE.md)。三段提示詞各開一個 Code 工作階段。建議順序：Live-A → Live-C；Live-B 可與 Live-C 並行。
> 每段都要求做到「正式入口可實際操作」為止，不接受只交工具、元件或報告。

---

## 提示詞 1：Live-A 斷網時的附近求助與底圖提示

```
目標：在 taipei-safe-walk-townpass 交付可 Live 運作的「斷網時附近求助與底圖提示」，規格見 docs/SAFE_WALK_OFFLINE.md §A，完成定義見 §1 第 9 點。

開工前：
1. 讀 AGENTS.md、docs/SAFE_WALK_OFFLINE.md（§0、§1、§A、§2、§4）、lib/features/safe_walk/navigation/README.md、lib/features/safe_walk/presentation/README.md、docs/SAFE_WALK_LIVE_READINESS.md。
2. git fetch 團隊 origin，從最新 origin/main 建分支 feat/offline-live-a；回報基底 SHA。
3. 確認 TownPass 正式 Safe Walk 入口實際以 liveRoutes 開啟、走 safe_walk_composition_root 的 Live 組合。若不是，先回報差異，並在本任務補上讓正式入口走 Live 的最小接線（屬 Level A 以外者照 AGENTS.md 分級標示）。

實作：
- safe_walk_composition_root.dart 的 _planNearby：全部據點路線因連線類原因失敗時，保留本機快照據點，顯示「僅據點、無路線」清單（名稱、類型、營業狀態、直線距離與方位、「直線距離，非步行路線」標註、重試、緊急求助、OSM 快照日期）。地圖只標點，不畫直線或任何路徑。
- D1：本機據點清單只需定位權限，不需第三方路線同意；路線規劃仍需原同意。
- 路線失敗文案依 provider_unavailable／no_route／起訖點問題／取消分開，各有下一步。
- safe_walk_map.dart：圖磚載入錯誤累積時顯示非阻斷提示，恢復後自動隱藏；點位、路線、避讓圓照常繪製。
- 正常連線時的行為、排序、取消、遲到結果處理維持原樣。

限制：不新增依賴、不改 canonical Schema、不加 connectivity 套件、不把任何位置寫入裝置儲存；沿用 TPColors 與既有元件。

驗證：注入 routeService 測全部 provider_unavailable、部分成功、no_route、取消、遲到結果、無第三方同意時的本機清單；用 SafeWalkMap.tileProviderFactoryForTesting 注入失敗圖磚測提示出現與消失。執行 flutter analyze、flutter test 與 AGENTS.md 要求的適用檢查。

收尾：更新 Readiness（WIRED_NOT_VERIFIED）並附 §4 的 iPhone 驗收步驟；commit、push 團隊 origin、開 PR（不 merge），PR 依 AGENTS.md 格式。回報 PR 連結、SHA、測試結果（未執行／失敗／跳過分開列）與尚未完成的實機驗收。
```

---

## 提示詞 2：Live-C 裝置端離線步行路線（含避讓）

```
目標：交付可 Live 運作的裝置端離線步行路線：連不上 Valhalla 時，正式入口仍能用真實 OSM 步行路網在手機上規劃含三級避讓的路線並導航。規格見 docs/SAFE_WALK_OFFLINE.md §C、§1、§2（D2、D3、D4）、§3、§4。

開工前：
1. 讀 AGENTS.md、docs/SAFE_WALK_OFFLINE.md、lib/features/safe_walk/navigation/README.md、navigation/avoid_area.dart、navigation/valhalla_avoiding_route_planner.dart、navigation/default_route_service.dart、navigation/coordinate_math.dart、navigation/route_reference_area_check.dart、shared/route_instructions.dart、platform/integration/avoiding_route_service.dart、platform/integration/safe_walk_composition_root.dart（建構 OsrmWalkingRouteProvider／ValhallaAvoidingRoutePlanner／AvoidingRouteService 的段落、_planNearby）。
2. 若 Live-A 已合併，從最新 origin/main 建 feat/offline-live-c；否則從 Live-A 分支最新 head 建 stacked 分支，PR 寫明 base 與 SHA。

實作（同一任務完成，可分多個 commit）：
1. 路網工具 tool/offline_route/：從 Geofabrik 臺灣 .osm.pbf（與 assets/safe_walk/osm_help_points_taipei.json 同一份或同日資料，D4）擷取 bbox 24.95,121.44–25.22,121.68 的步行可通行路段；篩選規則寫成設定檔並測試，README 說明重現步驟及與 OSRM foot profile 的差異。工具語言自選，沿用 scripts/ 的依賴慣例。
2. 二進位格式 taipei_walk_graph.bin（CSR：節點 1e-7 int32、邊長、街名索引、flags）與 meta.json（來源日期、bbox、節點／邊數、SHA-256、規則版本、ODbL 授權）；格式寫進 README。實際產生臺北全範圍資料並 commit 到 assets/safe_walk/route/、列入 pubspec.yaml。D2：單檔須 ≤ 50 MB，超過就精簡欄位或範圍直到符合。
3. lib/features/safe_walk/navigation/offline_walk_graph.dart：解析、驗證版本與 SHA-256、最近路段吸附；可在 isolate 使用。
4. lib/features/safe_walk/navigation/offline_graph_route_planner.dart：實作 AvoidingRoutePlanner，形狀與 ValhallaAvoidingRoutePlanner 一致；isolate 載入與計算、支援取消、A*；三級避讓（full 排除與 50 m 圓相交的邊、center 排除距圓心 < 15 m 的邊、none 不排除）；起訖點在圓內加 insideWarning；passedAreaIds 用既有距離函式；吸附超過 maxEndpointSnapMeters 回 provider_unavailable 並說明範圍外；依方位角與街名產生 RouteInstruction（門檻常數化）；RouteCandidate 為 walkingNetworkVerified true、provider id offline-osm-graph、warnings 含「離線路網資料：YYYY-MM-DD 快照，可能與現況不同」。
5. 正式接線（D3）：Valhalla → 離線路網 → OSRM，保留每個 service 只取最新呼叫與取消語意；hasConsent 拆成「第三方送出同意」與「導航作用中／前景／未取消」，離線版只檢查後者；避讓區域取 [..._areas, ..._crimeAreas] 當下值，未曾載入時 warnings 與 UI 顯示「目前未取得通報與犯罪參考位置，此路線未套用避讓」；_storeRoutes 同樣套用，Live-A 的「僅據點」清單在離線路線可用時自動變成「據點＋路線」；路線卡片與導航畫面顯示離線來源與快照日期；safe_walk_sources.dart 新增離線路網來源。

限制：不把通報或犯罪座標寫入裝置儲存（Level C，不在範圍）；不改 canonical Schema；資產與 pubspec 變更為 Level B，PR 標明需 M1 小魚確認、備援順序請 M2 Steven Review。

驗證：
- 單元：篩選規則、格式讀寫、損壞檔、吸附、A*（手工小圖）、三級避讓、圓內起訖、範圍外、取消、轉彎提示。
- 整合：注入 transport 模擬 Valhalla 與 OSRM 皆失敗 → 走離線版；Valhalla 失敗且離線範圍外 → 走 OSRM；遲到結果不覆蓋；未載入避讓資料的 warning；無第三方同意仍可離線規劃；附近求助在離線時顯示據點＋路線。
- 對照：真實圖選 10 組臺北起訖點（不含真實住家或個人位置），與 Valhalla 參考結果比較距離（目標 ±25%）並確認 full 等級不穿圓，fixture 放 test/fixtures/offline_route/。
- 量測並寫入 PR：資產大小、載入時間、3 km 路線計算時間（目標 ≤ 500 ms）。
- flutter analyze、flutter test、適用的 Python 測試、Web build 不壞、tool/verify_native_release.py 依新資產調整並通過。

收尾：更新 Readiness（新增離線路線能力列，WIRED_NOT_VERIFIED）、navigation/README.md、docs/SAFE_WALK_OFFLINE.md 實測數據；push 團隊 origin、開 PR（不 merge）。回報 PR 連結、SHA、測試結果、量測數據與 §4 iPhone 驗收步驟。
```

---

## 提示詞 3：Live-B 離線底圖

```
目標：交付可 Live 運作的離線底圖：原生 App 在臺北範圍內不連 tile.openstreetmap.org 也能顯示可閱讀的繁中街道底圖。規格見 docs/SAFE_WALK_OFFLINE.md §B、§1、§2（D2、D4、D5）、§3、§4。

開工前：
1. 讀 AGENTS.md、docs/SAFE_WALK_OFFLINE.md、presentation/safe_walk_map.dart、presentation/safe_walk_sources.dart、presentation/README.md、tool/verify_native_release.py、docs/SAFE_WALK_LIVE_READINESS.md（R5）。
2. 從最新 origin/main 建分支 feat/offline-live-b；回報基底 SHA。

實作（同一任務完成，不另交原型 PR）：
1. 方案選定（§B2 B-0）：在 Flutter 3.47.6 stable、flutter_map ^8.3.2 下依序嘗試 (a) vector_map_tiles（不可用 10.x，因其依賴 flutter_gpu）＋ vector_map_tiles_pmtiles 讀本機 .pmtiles；(b) vector_map_tiles ＋ MIT 授權的 .mbtiles 向量讀取器；(c) 點陣 .mbtiles（自行渲染）＋ flutter_map MBTiles 點陣 provider。第一個能在 iOS／Android 編譯、繁中路名可讀者即採用，不得停在報告。結果（版本、理由、授權清單、量測）寫入 docs/SAFE_WALK_OFFLINE.md 新增的 §B5。
2. 圖磚工具 tool/offline_map/：用 planetiler 從 Geofabrik 臺灣 pbf（D4：與求助點快照、路網同一份或同日）產生 bbox 24.95,121.44–25.22,121.68 的圖磚與 meta.json（來源日期、bbox、zoom、工具版本、SHA-256、授權）。D5：優先 Protomaps schema 與樣式，不可行時改 OpenMapTiles 並加其標示。glyph 須支援繁中並寫明授權（不得假設 PingFang 可再散布）。README 寫重現步驟；CI 只驗 meta 與 SHA-256，不下載 pbf。
3. 實際產生臺北全範圍檔案，commit 到 assets/safe_walk/map/ 並列入 pubspec.yaml。D2：單檔 ≤ 50 MB，超過就降低 maxzoom（以 overzoom 顯示高縮放）或縮小範圍直到符合。
4. App 接線：依選定方案加入依賴（Level B，PR 標明需 M1 小魚確認）；需要檔案路徑時首次使用把 asset 複製到 App 支援目錄，以 SHA-256 決定是否更新，失敗時回退線上圖磚並沿用 Live-A 的提示；SafeWalkMap 與 safe_walk_home_setting_view.dart 共用同一個 offline／online 底圖來源（抽出共用 builder），原生預設 offline、Web 維持 online（條件 import 隔離）；範圍外顯示線上圖磚或「離線地圖範圍外」提示；路線、點位、避讓圓疊在離線底圖上正常顯示；attribution 與 safe_walk_sources.dart 加入離線底圖來源與快照日期；保留並新增測試注入點。
5. 若 Live-A 尚未合併，圖磚失敗提示的依賴部分以最小實作處理並在 PR 說明，避免與 Live-A 衝突。

驗證：離線模式不送出任何 tile.openstreetmap.org 請求（注入 provider 或網路紀錄驗證）；範圍內外、複製失敗回退、Web 走線上的測試；flutter analyze、flutter test、Web build、tool/verify_native_release.py 依新資產調整並通過；PR 記錄 APK／IPA 大小增量、首次複製耗時、平移縮放流暢度觀察。

收尾：更新 Readiness R5（WIRED_NOT_VERIFIED）與 presentation/README.md；push 團隊 origin、開 PR（不 merge）。回報 PR 連結、SHA、選定方案、測試結果、量測數據與 §4 iPhone 驗收步驟。
```
