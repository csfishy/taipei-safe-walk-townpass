# 臺北離線底圖產製

正式資產是完整 bbox `24.95,121.44–25.22,121.68` 的真實 OSM 向量 MBTiles，非樣本。
CI 只執行 `python tool/offline_map/metadata.py`，不下載 PBF、不啟動 Java。

## 固定來源與授權

- Geofabrik `taiwan-261111.osm.pbf`：2026-11-11 快照，SHA-256
  `6d9b7a214e7617df8473e311466e0a2517209d937c579f6a2134a64421cc838d`。
  與已合入目標分支的 Live-C PR #102 路網、求助點使用同一來源；沿用其既有資產，不重產覆寫。
  三項 sourceDate／sourceSha256 一致，後續圖磚／路網／求助點應一起更新。
- [Protomaps basemaps](https://github.com/protomaps/basemaps/tree/42ffaaa4a85a41bfcb23e43cc0f5b492a5eca123)
  commit `42ffaaa4a85a41bfcb23e43cc0f5b492a5eca123`，profile 4.15.2，Planetiler 0.10.2，Java 21。
  程式 BSD-3-Clause，設計 CC0，OSM 衍生資料庫 ODbL-1.0。保留來源及授權於 assets。
- `TaipeiBasemap.java` 使用官方道路／建物／水系／公園／捷運等各 layer handler；只讀 OSM，
  不下載全球海岸、Natural Earth、landcover。臺北此 inland 範圍不需全球海岸補面；空白背景用樣式底色。
  Qrank 空索引表示 POI 不採全球人氣排序；不是虛構 POI，不移除真實街道名稱。
- `style.json` 改自 `vector_map_tiles_pmtiles 1.5.2` 所附 Protomaps lightV4，
  原 pub archive SHA `197bb1badd9bda5e0e089a771992904b6010cc14972e844abd4e1e313fcb3406`。
  `style.py` 優先 `name:zh-Hant` → `name:zh` → `name` → `name:en`，不帶遠端 glyph/sprite。
  [Protomaps 授權](https://github.com/protomaps/basemaps/blob/42ffaaa4a85a41bfcb23e43cc0f5b492a5eca123/LICENSE.md)：設計 CC0、程式 BSD-3-Clause。
- [Noto Sans CJK TC Regular](https://github.com/notofonts/noto-cjk/tree/main/Sans/OTF/TraditionalChinese)
  完整 OTF 16,435,884 bytes，SIL OFL-1.1，隨附 `Noto-OFL.txt`；SHA 在 meta。
  Flutter TextPainter 直接使用此字型，完全離線，不需要 MapLibre glyph PBF；不使用 PingFang 作底圖字型。
- 執行期 `vector_map_tiles 9.0.0-beta.13`、`vector_tile_renderer 6.1.0`：BSD-3-Clause；
  `vector_map_tiles_mbtiles 1.2.2` 讀取 adapter：MIT；底層 `mbtiles 0.5.1`：BSD-3-Clause；
  sqlite3：MIT，SQLite：public domain。實際傳遞版本以 `pubspec.lock` 為準，App 第三方授權頁保留套件通知。

## 重現（PowerShell）

1. 安裝 Java 21、Maven、Python 3、Flutter 3.47.6；不需系統管理員安裝。
2. 在 checkout 之外下載來源與工具：

   ```powershell
   curl.exe -fL https://download.geofabrik.de/asia/taiwan-261111.osm.pbf -o taiwan-261111.osm.pbf
   git clone https://github.com/protomaps/basemaps.git
   git -C basemaps checkout 42ffaaa4a85a41bfcb23e43cc0f5b492a5eca123
   # 在 basemaps/tiles 執行，PowerShell 的 -D 參數需加引號
   mvn -B '-DskipTests' '-Dspotless.skip=true' package
   ```

3. 從 App repo 執行；WorkDirectory 必須在 checkout 外，避免提交中間檔：

   ```powershell
   ./tool/offline_map/build.ps1 -Pbf /absolute/path/taiwan-261111.osm.pbf -BasemapsJar /absolute/path/basemaps/tiles/target/protomaps-basemap-HEAD-with-deps.jar -WorkDirectory /absolute/path/map-build
   Copy-Item /absolute/path/map-build/taipei.mbtiles assets/safe_walk/map/taipei.mbtiles
   python tool/offline_map/metadata.py --write
   ```

4. 樣式更新才需取上列固定 pub archive、校驗 SHA、解壓後執行
   `python tool/offline_map/style.py /path/to/extracted/package`。字型與授權來源見上，複製後以 meta SHA 檢查；
   更新字型時一併更新來源／授權／meta，不可替換為未授權系統字型。
5. 輸出 z12–z15（z16–z19 overzoom），單檔上限 50,000,000 bytes。
   `metadata.py --write` 驗真實 SQLite／format／zoom，記錄來源、參數、SHA、大小、圖磚數、字型與樣式 SHA。
   MBTiles `version=1.3` 是格式版本，profile 版本另列；不能用 `4.15.2` 填此欄位。
6. 跑 Flutter tests、analyze、Web／native build 與 release verifier；iPhone 驗收見文件 §4。
   重建結果可能因 SQLite 排程／排序不同而 SHA 不同，須更新 meta 並重新驗證，不能重用舊 digest。

## 邊界與更新

App 原生預設離線，先驗／複製到 application-support，以內容 SHA 命名、暫存寫入後重新驗證再 rename。
讀寫失敗明示回退線上；準備中不建立 OSM provider。範圍外顯示灰底＋提示，不偷偷要求線上圖磚。
Web 用條件 import，完全不載入 SQLite／本機檔案程式。地圖與住家選點共用 builder。
資產更新是 App 隨版更新，不做 runtime 下載，CI 不批次抓 OSM 圖磚。

`SAVE_BASEMAP_PREVIEW=1 flutter test test/features/safe_walk/presentation/offline_map_render_test.dart`
可將真實資料渲染圖存到 ignored `artifacts/offline_map/`，供檢查繁中路名；這不是裝置效能驗收。
