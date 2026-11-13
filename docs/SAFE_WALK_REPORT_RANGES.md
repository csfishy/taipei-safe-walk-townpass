# 安心行地圖 GPS 回報範圍

2026-11-13（Asia/Taipei），追蹤 [Issue #109](https://github.com/csfishy/taipei-safe-walk-townpass/issues/109)。使用者已確認：500 公尺中心固定、100 公尺詳情限制只適用三角形使用者回報、地圖停留期間持續前景定位。本次取代 #108「僅正式導覽時持續定位」的規則；#107 原有實機驗收仍保持開啟。

## 行為

- 一般模式：最新有效 GPS 為中心繪製 100 公尺環，隨位置更新；拖曳地圖不改變資格。範圍外僅顯示中性三角，無詳情點擊、類型／狀態朗讀或回報的 50 公尺緩衝圓。犯罪參考點及求助地點維持原行為。
- 回報模式：主動取得有效 GPS，固定這次的中心，鏡頭框選完整 500 公尺範圍；走動、路線更新與手動起點不移動該中心。選點、既有回報標示、「用我目前的位置」及送出前都驗證範圍，含精確邊界。
- 可用「重新定位回報範圍」重建中心並重新選點；取消或成功後切回 100 公尺模式。若新回報在目前位置 100 公尺外，不自動開啟其詳情。
- 使用 Haversine 距離，圓以真實公尺繪製。回報／詳情要求 GPS 來源、誤差不超過 30 公尺及既有 60 秒新鮮度檢查；手動導航座標不可代替 GPS。
- 無有效 GPS 時停用相關操作並提供重試；一般範圍環不顯示，既有回報中心即使仍顯示也不能選點或送出。移動、定位失效或過期使已開啟的詳情失去資格時收起詳情，「已排除」也再次驗證。
- GPS 串流與導航共用一份；沒有路線、未同意第三方查詢、手動導航起點或尚未開始導覽，仍可更新地圖範圍。唯有按「開始導覽」才啟動路線跟隨、方向感測及偏離改道。
- 結束導覽保留前景地圖 GPS；離開、背景、SOS 或退出取消 GPS／非同步定位。返回前景只恢復地圖 GPS，不自動恢復導覽或回報選點；晚到結果不得復活舊工作。GPS 串流錯誤後，重試會重新建立監聽。
- 所有回報仍參與既有 50 公尺產品避讓計算；隱藏詳情／緩衝顯示不會刪除資料或縮小避讓範圍。持續 GPS 更新本身不觸發第三方查詢。

## 範圍、審查與證據限制

主責 M1 小魚，修改 platform/integration 與 presentation（原技術聯絡範圍 M1／M3），沿用 M2 路線及 M4 回報持久化。Level A，普通狀態與 callback 接線；無 shared wire 契約、Schema、依賴、原生設定、後端 RPC／RLS 或正式部署開關變更。

工作基線 `b59e088`，任務分支 `feat/gps-report-ranges`；開工已 fetch 並核對 main／開放 PR，無重疊檔案。位置只留前景記憶體，不新增軌跡儲存或外傳。這是 App 互動限制，既有回報 API 仍提供資料供避讓，不能當成伺服器 GPS 存取控制。未操作真實回報、警消、電話或通知，未修改持久犯罪資料。

主要程式：`report_range.dart`、`safe_walk_map_view.dart`、`safe_walk_map.dart`、`safe_walk_flow.dart`、`safe_walk_composition_root.dart`。單元與 widget／integration 測試使用人工座標、注入位置串流與 Provider；不能代替實機。

## 本機驗證結果

Flutter 3.47.6，Windows，2026-11-13：

| 檢查 | 實際結果 |
|---|---|
| `flutter test --no-pub --reporter expanded` | 1,322 通過、20 依既有設定略過、0 失敗。略過為 3 項真實服務 smoke 與 17 項設計截圖。 |
| `report_range_test.dart` + `safe_walk_live_route_test.dart` 重點回歸 | 21 通過、0 略過、0 失敗；這些案例也包含於最終全套測試。 |
| `flutter analyze --no-pub lib/features/safe_walk tool test/features/safe_walk third_party/vector_map_tiles/lib third_party/vector_map_tiles_mbtiles/lib` | No issues found。 |
| `dart run tool/generate_safe_walk_contracts.dart --check` | Schema／Dart 同步。 |
| `dart run tool/check_safe_walk_baseline.dart` | TownPass 歷史與模組邊界通過。 |
| `git diff --check` | 通過。 |

忽略的本機證據檔：`build/gps-ranges-verified-tests.log`、`build/gps-ranges-focused-final.log`、`build/gps-ranges-final-analyze.log`。本機審查涵蓋固定中心、實際公尺距離、所有回報入口、GPS／導航分離、取消與重試、來源／無障礙內容及 shared／import 邊界；不將隔離測試標記為實機 LIVE_VERIFIED。

## 尚未完成的實機驗收

- [ ] iPhone：首次允許、拒絕、永久拒絕、系統定位關閉與精確位置設定；重試可理解且無替代假座標。
- [ ] 開始回報時取得當下位置，500 公尺環完整可見；實際走動中心固定，內／外／邊界選點符合規格；手動起點無法移動範圍。
- [ ] 100 公尺環跟隨步行，範圍外三角不可開詳情；已開詳情越界收起；VoiceOver 不朗讀範圍外內容；犯罪參考點與求助地點不受限。
- [ ] GPS 漂移、室內與都市高樓環境：30 公尺精度與 60 秒新鮮度門檻、靜止時位置更新及定位失敗重試。
- [ ] 導覽／回報切換、路線重算、已選求助地點、鏡頭跟隨與結束導覽；不重複開啟 GPS。
- [ ] 背景、前景恢復、SOS、離開與快速重新進入；GPS 與方向感測啟停，無遲到回報或自動續導航。
- [ ] 長時間停留地圖的耗電、弱訊號／離線、真實據點及回報資料、50 公尺避讓與來源限制呈現。

尚未執行 Android／iOS build、實機 GPS 行走、真實服務 smoke 或遠端 CI；本機驗證時尚未推送；本次未部署或合併。
