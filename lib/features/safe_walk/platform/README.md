# M1｜小魚：平台、唯一定位入口、求助與整合

先讀根目錄 AGENTS、官方初始化文件及 [五人模組契約](../../../../docs/SAFE_WALK_MODULES.md)。本目錄不包含正式頁面；官方 main／GetX route／theme 保留，不套 React UI。

## 所有權與接點

- 本模組可改 `lib/features/safe_walk/platform/`，新增測試使用 `test/features/safe_walk/platform/`；共用 contracts／models／Schema／fixtures、官方接線、route、CI、依賴由 M1 統一協調。
- `PlatformService.getCurrentPosition()` 明確接 `DataMode mode`、`bool userInitiated`、選用 `SafeWalkCancellation`，輸出 `Future<LocationResult>`。false 使用者操作不得觸發權限；mock 不取裝置 GPS。
- `requestEmergency()` 明確接 mode、channel、userInitiated、allowRealCalls 與選用 `IncidentSummary`，輸出 `EmergencyActionResult`。只有 live＋使用者操作＋允許真實電話才可能 handoff；`officialReceipt` 固定 null。
- 共用模型唯讀匯入 `shared/models/safe_walk_models.dart as sw`，不另外定義 geolocator 版 Position 給其他模組。

## 狀態、缺值與整合

位置失敗為 denied／timeout／unavailable／unsupported；取消可拋共用 `SafeWalkCancelledException`，由 M1 邊界忽略過期結果，或轉 unavailable＋明確取消訊息，不新增 wire status。未知精度／時間遵守 required nullable，不能補假座標。

`TownPassPlatformAdapter` 已包裝官方 `GeoLocatorService.position()`，但未在官方 App 註冊或自動呼叫。只有 live 且明確使用者操作才可能讀位置；mock 只消費注入 fixture，沒有時回不可用。缺少實測精度或來自 native mock provider 的位置不會假標為真實 GPS；live 結果亦套用共用 `positionProblems()`，拒絕超過 60 秒的定位及超前 30 秒以上的時間。M2 消費這一份位置；M1 之後注入 M4 repo／據點 lookup，求助先停止 M5 並取消路線。不等待定位成功才提供求助，也不自行宣稱警方受理或派遣。

## 第一輪交付

以 fake／mock 驗證模式與操作閘門、成功／拒絕／取消、求助不撥號不傳位置；原生權限、電話與 route 接線明列待驗。`platform_service.dart` 是抽象介面；`townpass_platform_adapter.dart` 提供 lazy 位置映射、有限等待與取消，正式求助 Adapter 尚未配置，因此無論旗標如何都不撥號、不傳位置，回 not_configured／cancelled 與固定 null 回執。

預定分支 `feat/m1-platform`：**pending**。先審查初始化 PR，使用者確認合併後才從共同 Flutter base 建立，不自行 merge 或預先建立五個分支。

## M1 導航整合（2026-11-07）

`integration/SafeWalkCompositionRoot` 現在注入 M2 `DefaultRouteService`，使用已驗證的同模式 M4 據點 snapshot 核對途經 ID。`SafeWalkNavigationController` 管理共用 request/result、loading/error、取消與遲到結果；`shared/contracts/safe_walk_navigation_scope.dart` 提供 M3 接線邊界，不新增 GPS 監聽。

原生入口固定 Mock，現有 M3 Demo 操作保留。Live UI/provider 閘門維持關閉，OSRM 僅預備注入、不發請求；Overpass 未接入。M3 尚未消費 scope，目的地變更、SOS 開頁及離開導航的使用者事件仍需由 M3 接上；不能把 scope 測試當成真實路線 UI 已完成。詳見 [M1／M2／M3 接線規格與交接](../../../../docs/SAFE_WALK_NAVIGATION_PRESENTATION_CONTRACT.md)。

本輪完整 Flutter suite：359 通過、12 跳過（10 截圖、2 opt-in live smoke）；Schema／module guard／scoped analyze 通過。完整預設 analyze exit 1，僅 17 項既有 info、無 error/warning；CI 的 `--no-fatal-infos` exit 0。測試包含 22 項 controller、11 項 scope 接線及既有 TownPass 入口／Mock SOS 整合，不包含 iPhone 實機或公共 OSRM／Overpass 驗證。
