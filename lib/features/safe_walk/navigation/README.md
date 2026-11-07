# M2｜Steven：座標運算與 RouteService

先讀根目錄 AGENTS、官方初始化文件及 [五人模組契約](../../../../docs/SAFE_WALK_MODULES.md)。本目錄不新增地圖 Widget、route 或 GPS watcher。

## 所有權與輸入輸出

- 可改 `lib/features/safe_walk/navigation/`；測試使用 `test/features/safe_walk/navigation/`。共用契約、套件與官方 route 需求交 M1，不直接修改其他模組。
- `RouteService.planRoute(RouteRequest request, {SafeWalkCancellation? cancellation})` 回 `Future<RouteResult>`。
- request 含 M1 提供的 origin、destination、requestId、mode、departAt、preference、繞行上限與 assistancePointIds；只消費定位，不再次要求或監聽 GPS。
- 結果為 RouteSuccess 或 RouteFailure，保留同一 requestId／mode。失敗 no_route／provider_unavailable／invalid_input／cancelled 時 routes 為空。
- 距離／秒數未知依共用模型用 null；座標內部 lat／lng、GeoJSON `[lng, lat]`，不得互換。不自造第二個 Route 或 Position model。

## Mock 與整合

先使用共用 fixture 與注入 fake provider。無 live provider 明確回 provider_unavailable，不用 mock／直線路徑冒稱真實步行網路。取消或舊請求不得覆蓋新結果。

M1 將完整據點 lookup／provider 注入本模組；不得直接 import M4 實作。途經點 ID／來源／營業狀態須核對，行政區歷史犯罪統計不能直接形成即時道路安全分數。

## 第一輪交付

純 Dart 座標測試、固定 request 的 mock 成功／失敗、requestId 一致與取消案例；真實 provider 未接入則明列。本次 `route_service.dart` 只有抽象介面，不聲稱導航功能已完成。

預定分支 `feat/m2-navigation`：**pending**，待初始化 PR 審查並由使用者確認合併後，才由 M1 從共同 Flutter base 建立。
