# 臺北安心行：官方犯罪警示資料與地理化

2026-11-07（Asia/Taipei）。M4 需求正式改為犯罪資訊地理化、警示辨識及步行導航避讓，**不新增 AED 功能**。既有暴力犯罪月統計保留，只能說明全市歷史趨勢，不能變成逐路段／逐時風險分數。本文件記錄 PR A 的來源、內部型別與地理證據；PR B 消費可靠範圍比較經 OSRM 路網驗證的候選，不能任意改 polyline。

## 實際取得的官方資料

CSV 與必要詮釋資料已實際下載，完整可重現樣本位於 test/features/safe_walk/safety_data/crime_warning/fixtures/；source_manifest.json 記錄 URL、取得時間、raw／UTF-8 SHA-256、編碼及筆數。metadata samples 僅保留解析所需官方欄位，未保留無關職員聯絡資訊。原始 CSV 不補值、不加座標。

| 資料集 | 實際資源／欄位／編碼 | 筆數與適用性 |
|---|---|---|
| [臺北市婦幼安全警示地點](https://data.taipei/dataset/detail?id=985743f7-a33e-4ac1-ad2e-7ef5ffea02e2) | resource f87ecf10-7379-49de-8945-cb50017ec838；UTF-8；編號、縣市別代碼、地點位置、管轄分局、郵遞區號、備註 | 22；官方婦幼安全提醒，可對可靠地理化範圍做候選交集，但不是即時案件 |
| [臺北市街頭隨機搶奪案件點位資訊](https://data.taipei/dataset/detail?id=404ca667-bcc4-4f3b-9217-fdcc1da400b2) | resource 6ecb4c41-fbc9-4b04-b182-a7da6c780f8d；Big5；編號、案類、發生日期、發生時段、發生地點、備註 | 54；來源地址預先模糊化，保留原日期及文字，**不納入精確路段避讓** |
| [臺北市街頭隨機強盜案件點位資訊](https://data.taipei/dataset/detail?id=ea2819ff-c869-480e-b7a9-2e5f7906a696) | resource 37b75aab-e504-413a-911d-987651aacbfb；Big5；同上案件欄位 | 26；同樣只供歷史文字參考，不還原為精確發生點 |

三者均沒有經緯度欄位。資料頁／metadata 標示政府資料開放授權條款第 1 版，使用時保留提供機關「臺北市政府警察局婦幼警察隊／臺北市政府警察局刑事警察大隊」與來源，並遵循[資料平台授權條款](https://data.taipei/rule)。Big5 原檔以 .raw.big5 保存，另附精確轉碼的 UTF-8 CSV 供測試；fixtures/.gitattributes 保留 CSV 原始 bytes。預設 GetConnect transport 支援主要 UTF-8 CSV／JSON，次要 Big5 來源若未提供經核對的 Unicode decoder，應報格式不可用，不能猜編碼或靜默亂碼。

主要資料檔名為「資料大平台-115上半年婦幼安全警示地點.csv」，資源更新 2026-07-27 10:40:10+08:00，metadata 更新 2026-07-27 10:40:38+08:00，發布日為 2022-01-21。原檔名與資源名稱保留；發布日不當成發生日期。來源描述「近三年」但沒有逐列發生日期或明確起訖，observedPeriod 保留 null，不自行推算案件期間。

搶奪資源更新 2026-05-04，強盜資源更新 2026-08-05；資料頁文字／檔名／metadata 期間可能不一致，因此逐列原始民國日期與時段保留，不以頁面描述覆蓋。

## 內部契約與失敗語意

新增 shared/models/crime_warning.dart，屬程序內整合型別，**沒有改 canonical JSON Schema、AssistancePoint、AreaStatistics 或生成模型**；共用 API 依 Level B 審查。

- CrimeLocationRecord：sourceId、datasetId、resourceId、category、原 locationText、observedPeriod、publishedAt、dataUpdatedAt、retrievedAt、sourceUrl、license、sourceResourceName／sourceFileName／metadataUpdatedAt、mode、sourceLimitations 及原 CSV sourceFields。沒有可靠幾何的列仍保留，不能因無座標消失成「無警示」。
- CrimeWarningZone：連到同一原始 record，含 Polygon／MultiPolygon／已確認路段 LineString、spatialPrecision、confidence、獨立圖資來源／授權、核對／取得／有效期限、accuracyMeters、匹配證據及限制。GeoJSON 固定 [longitude, latitude]；路段 corridorWidthMeters 是有證據的全寬，不是半徑。
- CrimeWarningSnapshot：records／zones、mode、取得時間、ready／empty／stale／unavailable、isComplete、warnings、unlocatedRecordCount；isComplete 指來源抓取與解析完整，不代表每列都有座標。22 列完整取得但僅 1 列地理化時，仍明示其餘 21 列。
- 官方 Repository 僅提供 live；Mock 未配置會明確拋錯，不連線、不用 fixtures 補成功。未配置、抓取／格式失敗、成功空資料、資料過期及取消各有語意；錯誤不包含原資料 payload。
- 來源年齡超過 190 天、更新時間未知／未來、地理核對過期、授權缺失、模式不符、模糊精度或歷史模糊地址，不得作精確避讓。190 天是配合半年更新的保守工程門檻，不是官方逐列有效期限；六小時記憶體 cache 不跳過資料年齡檢查。
- 取消在每次 await 與輸出前重查，遲到結果不填 cache；資料失效不切 Mock。getWarnings(forceRefresh: true) 失敗明確報錯，不回舊成功假裝已更新。

VerifiedCrimeGeographicResolver 只用離線、可審查的 mapping，必須同時精確匹配 sourceId 和原 locationText；官方文字改成「附近」等情況立即不匹配。沒有線上模糊 geocoding、沒有公共 Nominatim 批次查詢。

## 本次可靠地理化範圍

production catalogue 位於 safety_data/crime_warning/reviewed_taipei_crime_geography.dart，只含 **編號 11「中正區二二八和平公園」**。它使用真實公共場所範圍，不是犯罪發生點，也不是以捷運站中心或任意半徑模擬。

| 證據 | 核對方法與限制 |
|---|---|
| [官方公園圖資](https://data.taipei/dataset/detail?id=5b277432-f534-4d09-a24c-d3f6b514e042) | resource f3ce4bb6-712a-41ae-902b-f8a6099eac85；原圖形 feature id L0101-5.123／項次143，原 CRS EPSG:3826。原屬性名稱為「無」，**沒有只憑名稱猜測或最近鄰配對** |
| [官方公園登錄 API](https://parks.gov.taipei/parks/api/) | 命名登錄 SeqNo374「二二八和平公園」座標落在唯一公園 polygon 內，再對照官方說明的範圍及面積；來源與完整 resource hashes 記錄在 catalogue provenance |
| 座標轉換與原始證據 | 以已存在工具的 proj4dart 3.0.0 從 EPSG:3826 轉為 EPSG:4326／GeoJSON；沒有新增 runtime dependency。park_228_geographic_evidence.json 保存原 feature、官方登錄與轉換後範圍，供獨立比對 |
| 精度／有效性 | 類別 confirmedPublicPlace／verified 表示場所匹配與範圍來源已核對，不代表警察逐點或測量精度認證。官方未給公尺誤差，accuracyMeters 保留 null，不能顯示成0公尺；比較的是「目前已標示範圍」，不保證真實邊界或範圍外安全。圖資更新時間未提供也保持 null |
| 保留期間 | mapping 核對採90天期限，CSV仍受190天來源門檻；到期需重新查證，不讓舊 mapping 永久成有效警示。官方公園範圍可能變更，位置／入口與建設差異仍須裝置及現地驗收 |

目前定位成功率：主要來源 **1/22＝4.55%**；三來源合計 **1/102＝0.98%**。這是本次已核對的 mapping 覆蓋率，不是 geocoder 的泛化正確率。其他 **101 筆本次未可靠地理化**：主要來源21筆與模糊化歷史案件80筆，不作精確路段懲罰。

主要來源尚未地理化的編號為1–10、12–22，包括捷運場所、民主紀念園區、磺港公園、松廉／松壽路段、道南橋涵洞附近及潭美公園公車站。這些文字不是沒有價值；在取得與文字範圍相符的可靠圖資前，僅可作文字／區域參考。尤其「附近」、空橋／廊道、捷運站範圍不能用單點或整個街廓假替代。磺港公園的命名點未找到可唯一核對的官方範圍，因此排除。

## 測試與尚未驗收

crime_warning_test.dart 使用真實官方 CSV 樣本與明確標示的人工幾何 fixture，涵蓋三來源欄位／編碼、空值／重複／錯欄、metadata／日期／授權、GeoJSON順序、多邊形／洞／路段驗證、模糊地點排除、模式隔離、過期、timeout、取消與遲到 cache；production catalogue 另核對精確編號／文字、僅1個有效範圍、21個主要來源未定位及精度 null。

本次單元測試33項通過。另以 SAFE_WALK_CRIME_LIVE=1 執行 crime_warning_live_test.dart，使用實際 GetConnect transport、OfficialCrimeWarningRepository 與正式離線 catalogue，成功讀取官方 metadata／CSV：22列、1個地理範圍、21列未定位、status ready；該真實來源測試1項通過，正常 suite 預設 skip。未傳送使用者座標、未停用 TLS 驗證；來源成功仍不等於服務永久可用。

Parser／Repository／offline resolver 與真實公開來源測試不代表 App 或 iPhone 已驗收，不能標 LIVE_VERIFIED。正式 M1／M2／M3 端到端、地圖顯示、GPS／同意、OSRM 候選、裝置行走與誤差觀察由 PR B 與後續受控驗收補上。保留警示為歷史或官方提醒、不是此刻正在犯罪，也不跨類型加總人身風險分數。

本次實跑：資料／模型／Repository 測試 33 通過，新增範圍 strict analysis 無問題，Schema --check／正常 module guard 通過。另以 opt-in crime_warning_live_test.dart 執行真 GetConnect → 官方 metadata／UTF-8 CSV → production catalogue，1/1 通過，實際取得22筆／1個地理範圍／21筆未定位、status ready；沒有 GPS、地址查詢或 TLS 繞過。此 smoke 預設跳過，不把未執行時當 PASS。這些證據證明來源與 Parser 可實際運作，仍不代表 iPhone 或整個 Live 導航已驗收。
