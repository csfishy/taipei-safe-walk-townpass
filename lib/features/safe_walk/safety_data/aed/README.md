# M4｜AED 設置地點 live 來源

把臺北市政府衛生局「臺北市AED自動體外心臟去顫器設置地點」（data.taipei）轉成共用 `AssistancePoint`。App 內以 `DataTaipeiAedRepository` 讀取（無後端）；`tool/` 是同規則的離線 Python 工具，用來產生快照與測試 fixtures。

## 檔案

| 檔案 | 用途 |
|---|---|
| `aed_normalizer.dart` | 純轉換：原始列 → 正規化 JSON（不碰網路／時鐘），再交共用 `ContractSafetyDataParser` |
| `data_taipei_aed_repository.dart` | `SafetyDataRepository` 實作：分頁讀取、1 小時記憶體快取、取消、明確失敗 |
| `get_connect_aed_fetcher.dart` | 預設傳輸，沿用官方既有的 GetX `GetConnect`，不新增套件 |
| `fixtures/aed_raw_sample.json` | 15 列真實原始資料節錄（2026-11-07） |
| `fixtures/aed_expected_points.json` | Python 工具對上列的輸出；Dart 測試要求逐欄相同 |
| `tool/` | `aed_dump.py`（快照）、`make_fixtures.py`、`test_aed_transform.py`，只用 Python 標準函式庫 |

## M1 接線方式（本 PR 未接線）

```dart
final aed = DataTaipeiAedRepository(fetchJson: getConnectAedFetcher);
final points = await aed.getAssistancePoints(mode: sw.DataMode.live);
```

| 情況 | 行為 |
|---|---|
| `mode: mock` | 拋 `SafeWalkDataUnavailable`；示範資料仍由 `MockSafetyDataRepository` 提供，不混用 |
| 來源讀取失敗、回應格式不符、筆數不完整、全部列都不合契約 | 拋 `AedSourceUnavailable`（訊息不含資料內容），不回空清單、不改用示範資料 |
| 來源設定正常但 0 筆 | 回 `[]` |
| `getAreaStatistics()` | 拋 `SafeWalkDataUnavailable`：此來源沒有統計 |
| 取消 | 開始前取消不發請求；載入中取消不交付結果（快取仍會填入） |
| 詮釋資料讀不到 | `dataUpdatedAt`、`license` 為 `null` |

**Flutter Web 不能用**：data.taipei 只允許 `https://data.taipei` 在瀏覽器跨網域讀取，Web 版會得到 `AedSourceUnavailable`；Android／iOS 不受 CORS 限制。

## 欄位對照與決策

| AssistancePoint | 規則 |
|---|---|
| `id` | `tpe-aed-<區域代碼>-<緯度>-<經度>-<n>`，用來源原字串；n 依內容排序區分同座標多台 AED（全量最多 44 台同點）。不用平台 `_id`（重新匯入會變） |
| `name` | `場所名稱（AED：aed放置地點）`；兩者相同只用場所名稱 |
| `kind` | `public_facility`（契約沒有 AED 類別；不代表官方求助據點） |
| `coordinates` | 字串轉數字，已是 WGS84；不在臺北市範圍（lat 24.95–25.22、lng 121.45–121.67）或無法解析 → 剔除並記錄列號 |
| `address` | 補「臺北市＋區名」；「台北市」統一為「臺北市」；空白 → `null` |
| `publicPhone` | `null`（來源沒有） |
| `recognition` | `not_applicable`：AED 登錄不是合作認可 |
| `availability`／`availabilityCheckedAt` | `unknown`／`null`（來源沒有開放時間） |
| `capabilities` | `["unknown"]`：有 AED 不等於有人協助 |
| `source.retrievedAt` | 讀取當下，`+08:00` |
| `source.dataUpdatedAt` | 平台資源 `last_modified`（視為 Asia/Taipei） |
| `source.license` | 只接受含「政府資料開放授權條款」的平台值，否則 `null` |

區域代碼 63000010–63000120 依序為松山、信義、大安、中山、中正、大同、萬華、文山、南港、內湖、士林、北投；已用各區公所／運動中心地址逐區核對。

已知來源品質問題（照原樣保留，不猜測修正）：少數列的「場所地址」與「aed放置地點」內容對調，例如「臨江街夜市」；7 列地址空白。

## 驗證紀錄（2026-11-07）

- 全量 2,729 列以 Python 工具轉換：轉換 2,729、剔除 0、id 全部唯一（最長 43 字元），以共用 `schemas/safe_walk/v1` 的 JSON Schema（Draft 2020-12）檢查 0 錯誤。
- `python3 -m unittest discover -s lib/features/safe_walk/safety_data/aed/tool`：8 tests OK。
- Dart 測試在 `test/features/safe_walk/safety_data/aed/`；結果以 CI 或本機 `flutter test` 實跑為準。
