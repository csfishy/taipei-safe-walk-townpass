# 安心行主卡：預設最近求助地點

2026-11-13（Asia/Taipei）。依使用者確認，每次從首頁按「安心行」主卡，都進入「最近求助地點」，自動查詢並預覽步行路線；使用者按「開始導覽」才啟動持續定位與方向感測。

## 行為與範圍

- 先載入回報緩衝資料，再查詢附近據點；回報失敗保留不完整資料揭露。
- 使用目前位置或手動起點，沿用既有 OSM 快照、營業狀態篩選、直線距離排序與最多三個可路由據點的規則。
- 有家、未設定家都先預覽求助地點。切換「目的地」後才規劃家／常用地點；切換到未設定的家時才呈現設定操作。
- 預覽只取得單次位置，不開始 GPS／方向串流。開始、結束導覽分別啟動與停止既有單一監聽；重新進入回到預覽。
- 變更起點重新查詢；回報更新重新計算求助地點路線，保留可用的已選據點 ID。
- 切換目標、離開、背景及 SOS 取消舊工作，遲到結果不能覆蓋目前目標。由 SOS／通話返回時依目前目標類別呈現，首頁主卡則一律重設為最近求助地點。
- 沿用本機路線與第三方同意邊界、50 公尺產品避讓緩衝、來源／限制與錯誤揭露。

## 變更分類與檔案

Level A，一般 UI／callback／導航狀態接線；無 shared wire 契約、Schema、依賴、原生設定、正式開關或部署變更。現行主責為 M1 小魚；原技術聯絡範圍為 M1 platform/integration、M2 navigation、M3 presentation。

主要程式：`safe_walk_flow.dart`、`safe_walk_map_view.dart`、`safe_walk_home_view.dart`、`safe_walk_composition_root.dart`。測試涵蓋主卡入口、有／無家、重新進入、預覽與正式導覽、手動起點、定位失敗重試、晚到查詢、回報重載與既有目的地流程。

工作基線：`45b881c`；開工已 fetch 並確認與 `origin/main` 一致，開放 PR 無重疊檔案。分支：`fix/default-nearby-help`。

## 驗證邊界

Flutter 3.47.6。隔離測試使用人工座標、據點與 Provider，不操作真實通知、電話或使用者資料。Windows 測試與分析不能代替 iPhone 的系統定位權限、實際 GPS 行走與方向感測驗收；本次未進行正式部署。

2026-11-13 本機實跑：

| 檢查 | 結果 |
|---|---|
| `flutter test --no-pub --reporter expanded` | 1,310 通過，20 依既有設定略過，0 失敗。略過為 3 項真實服務 smoke 與 17 項設計截圖測試。 |
| 額外重跑 `safe_walk_live_route_test.dart`（含最後新增的已選據點重查回歸） | 10 通過，0 略過、0 失敗。此檔案的最後一個新增案例在上述全套之後另行驗證。 |
| Safe Walk scoped analyze（含 tool、tests、兩個 vector map 套件） | No issues found。 |
| `dart run tool/generate_safe_walk_contracts.dart --check` | Schema／Dart 同步。 |
| `dart run tool/check_safe_walk_baseline.dart` | TownPass 歷史及模組邊界通過。 |
| `git diff --check` | 通過。 |

證據位於本機忽略的 `build/default-nearby-verified-tests.log`、`build/default-nearby-targeted-final.log`、`build/default-nearby-final-analyze.log`。未執行真實服務 smoke、實機驗收、Android／iOS build 或遠端 CI；本機驗證時尚未推送，未進行部署。
