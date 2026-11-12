# 臺北裝置端步行路網

來源為 Geofabrik Taiwan 的真實 OSM PBF。工具只用 Python 3.11+ 標準庫，不需 osmium、服務端路由引擎或執行期下載。不要將 PBF 放進 Git／assets；資產只有 CSR、metadata 和公開求助點快照。

## 重現

```sh
curl -fL https://download.geofabrik.de/asia/taiwan-261111.osm.pbf -o /path/outside-checkout/taiwan-261111.osm.pbf
python tool/offline_route/build_graph.py \
  --pbf /path/outside-checkout/taiwan-261111.osm.pbf \
  --source-date 2026-11-11 \
  --output assets/safe_walk/route \
  --help-points assets/safe_walk/osm_help_points_taipei.json
python -m unittest discover -s tool/offline_route -p 'test_*.py' -v
flutter test test/features/safe_walk/navigation/offline_graph_route_planner_test.dart
dart tool/offline_route/benchmark.dart
```

本版 PBF SHA-256：`6d9b7a214e7617df8473e311466e0a2517209d937c579f6a2134a64421cc838d`。指定日期是來源快照日；求助點 `retrievedAt` 記錄實際產生時間，不冒充 OSM 更新時間。相同 PBF、規則與程式重產的 bin 完全相同；求助點除了 `retrievedAt` 外相同。更新時一併重產路網與求助點；Live-B 底圖應使用這個相同 PBF／SHA／快照日，不能標成已在此 PR 產生。

規則在 `rules.json`，範圍為 `[south, west, north, east] = [24.95,121.44,25.22,121.68]`。每條被接受的 OSM way 保留所有形狀節點，僅保留兩端都在 bbox 內的線段；不裁出人造連線、不按幾何交叉建立不存在的 OSM 路口。不同 layer／橋／隧道只有共享 OSM node 才連通。尊重 `oneway:foot=yes|1|true|-1`；一般車輛 oneway 不限制步行。阻擋不可步行的 barrier node；步行明確允許可覆寫一般 access 限制，`foot=no/private/use_sidepath` 永遠排除。沒有 `highway` 的物件不是步行線段。

## 格式 SWWALK01

所有數字 little endian。24-byte header：8-byte ASCII magic `SWWALK01`、uint32 節點數 N、邊數 E、街名數 S、街名 JSON UTF-8 byte 數 B。接著 N 個 `(int32 latE7,int32 lonE7)`、N+1 個 uint32 CSR offsets、E 個 16-byte edge `(uint32 target,uint32 millimetres,uint32 streetIndex,uint8 flags,3 zero bytes)`、B bytes 街名陣列（空字串表示無名）。flags bit0 表示階梯。長度向上取整到毫米，A* 球面啟發式不高估。節點依 OSM ID、街名依 Unicode、邊依 tuple 排序；保留雙向路段為兩個有向邊。

Dart parser 驗 magic、尺寸／offset／索引／座標／bbox／日期／SHA-256；每次請求在可被取消終止的 isolate 解析與計算，最多 15 秒，沒有同步 UI thread A*。資產 bytes 可在記憶體重用，敏感通報／犯罪區域只在請求的記憶體中使用，沒有寫檔。最近線段吸附建立虛擬起訖點，部分路段仍遵守方向與避讓，不把原始起點到吸附點畫成路徑。

## 與 OSRM foot profile 的差異與限制

對照 [OSRM 官方 foot.lua](https://github.com/Project-OSRM/osrm-backend/blob/master/profiles/foot.lua)（本次取回 2026-11-12）：共同忽略車輛單行、尊重步行單行、foot 優先於 access；此工具以距離最短為成本，沒有 OSRM 的 surface 速度、路口時間及 ferry／railway platform／parking／pier 特例，ETA 保留 null。納入 corridor／crossing；排除 area=yes，沒有廣場內部網格或 ferry。此版 access blacklist 依需求為 private/no（另排 foot=use_sidepath），OSRM 還列 agricultural／forestry／delivery。此版 barrier blacklist 比 foot.lua 的 yes/wall/fence 擴充 retaining_wall/hedge/block/jersey_barrier，但未處理 audible fence 等例外。

不讀 relations（包含步行轉向限制）、access:conditional、開放時段、車道／人行道 separate 推論；不宣稱無障礙或每條道路目前可通行。stairs 仍可走，未套用照明／遮蔭，沿用 preference 未套用揭露。OSM 缺漏可能造成斷路；無路即 no_route，資料毀損或吸附超過 500 m 即 unavailable，絕不補直線。

求助點同 PBF 擷取 shop=convenience／amenity=police 的 node 與完整 bbox 內 way；way 採外框代表中心，並非出入口。不解析 relation，缺漏屬資料限制，不補手工據點。來源日及 SHA 與 route meta 一致，3,699 筆；並非官方認可清單。

## 對照、效能與發佈

`test/fixtures/offline_route/taipei_pairs.json` 是十組公開地標，沒有住家／個人軌跡。只有明確需要更新真實對照時才執行 `python tool/offline_route/fetch_reference.py`，每次請求間隔 1.2 秒；CI 不連 Valhalla、不下載 PBF。`valhalla_reference.json` 保存真實回應形狀、距離和取得時間；正常測試驗十組距離 ±25%，且 full 的每條線段離人工 50 m 測試圓大於 50 m。單元測試另以隔離小圖驗證三種不同路徑、單行、取消、吸附、圓內端點及轉彎門檻；小圖不放 assets、不進正式入口。

實測數據與 iPhone 清單見 [離線需求 C6](../../docs/SAFE_WALK_OFFLINE.md#c6-live-c-實作與實測2026-11-12)。`desktop_results.json` 僅是桌機數據；中階手機效能與 iPhone GPS／飛航模式尚未驗收。

`tool/verify_native_release.py android|ios PACKAGE` 現在也檢查封包內 route bin／meta 是否吻合本次 source 的 SHA、尺寸與 ODbL；沒有該 SHA 的 APK／IPA 不能當驗證完成。本機僅有 Windows，本次沒有新的原生 release 封包。

## 授權

路網與求助點為 OSM 衍生資料庫，以 **ODbL 1.0** 提供，© OpenStreetMap contributors，來源由 Geofabrik 提供；不是由 repo 程式碼授權取代資料授權。公開 repo 的 `assets/safe_walk/route/` 提供完整衍生資料庫，這個目錄提供產生工具與參數；下游須保留 attribution、ODbL 告知及相同授權義務。參閱 [OSM copyright](https://www.openstreetmap.org/copyright)、[ODbL 1.0](https://opendatacommons.org/licenses/odbl/1-0/) 與 [PBF 官方格式](https://github.com/openstreetmap/OSM-binary/blob/master/osmpbf/osmformat.proto)。工具為本專案撰寫，沒有複製 OSRM profile 或 protobuf 原始碼。
