# 地圖回報持久資料

使用者主動選點並按「標示到地圖」時，App 透過公開 client key 呼叫 `safe_walk_map_report_submit`；資料庫確認後才更新地圖。`safe_walk_map_report_query` 提供重新進入時的持久回報。這些是使用者公開分享、未經核實的地圖標記，不是官方報案、警方受理或犯罪參考來源紀錄。

`01_map_report_api.sql` 是需審查後手動套用的 Level C SQL，不由 App、CI、build、seed 或 Demo reset 執行。獨立 private `safe_walk_reports` schema 啟用 RLS／FORCE、撤銷 client 直接存取，只開放新增、查詢與單筆排除三個驗證參數、空 search_path、固定輸出欄位的 RPC。它不改動 `crime_reference`、`safe_walk_demo` 或附近求助設定。

儲存欄位僅回報 UUID、分類、使用者選點、說明及伺服器時間。不記錄 GPS 歷程、使用者身分、聯絡人、電話或官方受理編號。說明與點位會公開供地圖查詢，提交前必須揭露並提醒不要輸入個資。

- UUID 是冪等 request id，不是身分或更新權杖。同一 UUID 與原內容重試只回原紀錄；內容不同回衝突，不覆蓋原資料。未知提交結果可重試原 request id。
- 依 2026-11-08 使用者明確要求，任何可查看公開回報的 App 使用者都可在該回報詳情右側按「已排除」，透過 `safe_walk_map_report_resolve(p_report_id)` 實體刪除那一筆 `reports` 資料。這是社群排除模式，未宣稱身分驗證、原作者 ownership 或警方確認；沒有匿名修改內容、批次刪除、座標條件刪除或直接讀寫資料表的介面。
- 分類限定五項；座標需有限且在 WGS84 範圍；說明最長 500 字元。查詢每頁最多 200、offset 最多 5000，選用 bbox 每方向最多 0.5 度。回傳總筆數讓 App 揭露資料截斷。
- 新增以交易鎖序列化、每分鐘全域最多 60 筆、總容量 100,000 筆；重試既有 UUID 不受新資料限額影響。這是容量／突發保護，不是每人身分驗證或完整防濫用。未核實資料與官方資料保持分離，無靜默清除／到期或 Demo reset。
- 取消／逾時無法保證已送出的 INSERT 回滾，App 不得宣稱「取消即未儲存」。需保留同一 request id 供相同內容安全重試；讀取重載可核對已提交回報。

## 地圖回報「已排除」

點選黃色三角形後，詳情右側提供「已排除」。App 等待資料庫對該 UUID 的刪除確認後，移除標記、關閉詳情並重新計算回報避讓；等待時禁止重複操作，失敗則保留原標示與重試提示。已被其他人排除的回報可安全重試，重新載入不會再顯示。

既有服務使用手動增量 `04_resolve_map_reports.sql`；新安裝的 `01_map_report_api.sql` 已同步。排除 RPC 只接受一個 UUID，實體刪除對應回報的座標、分類、補充內容與時間。private `resolved_ids` 僅保留 UUID 和排除時間，防止原本延遲的提交重試重新建立已刪回報，不保留回報位置、說明或身分。沒有資料的 UUID 不會新增技術紀錄；每分鐘最多 60 次實際排除、技術紀錄容量 1,000,000 筆是全域容量保護，不是每人防濫用驗證。

`05_verify_resolve_rollback.sql` 只對交易內新建的人工 UUID 驗證單筆實體刪除、保留另一筆、重試／不存在目標、重讀、拒絕舊 UUID 重建及直接表權限；全部 ROLLBACK，不清除既有回報。SQL 套用本身不刪除任何回報。本次是 App 介面與接線變更，按鈕需更新至包含此功能的版本後才能使用。

`02_verify_rollback.sql` 以 anon 角色驗證新增、原 UUID 重試、重新查詢、衝突、分類／NaN／查詢上限與直接表權限，所有人工測試 INSERT 在同一交易 ROLLBACK。套用後另用公開 client key 驗證真實 HTTP RPC、錯誤與 App 操作；SQL 測試不等同裝置驗收。

## 2026-11-08 修正與驗證

根因是原本地圖按鈕只向記憶體 `anomalies` 新增資料，未接資料庫，遠端也沒有地圖回報資料表／RPC。現在正式 composition 注入 `MapReportWiring`，提交收到資料庫確認後才顯示成功；進入地圖重新查詢持久資料，再更新 50 公尺產品避讓。讀取失敗保留明確錯誤與重試；提交失敗保留原內容與 UUID。未配置不假成功。

- 既有專案 `gxofnhzkqcmzrftxqddi` 已套用 `add_map_report_persistence`；無既有回報資料需遷移。
- `02_verify_rollback.sql` 在真實資料庫通過：anon 新增、相同 UUID 重試只一筆、讀取、非法輸入／衝突拒絕；anon／authenticated 直接讀表拒絕，authenticated RPC 讀取成功。驗證後回報筆數為 0；沒有留下人工回報。
- 公開 client key 的真實 HTTP 查詢成功，非法座標提交回 HTTP 400／`22023`，未新增資料。會留下公開資料的 HTTP 成功新增測試被自動核准審查拒絕，因此沒有執行；實際 INSERT 以可回滾的資料庫交易驗證。
- 新增 Repository／presentation／composition 測試共 29 項通過。整個 Safe Walk 測試曾跑 943 項通過、20 項 skipped；最後新增兩項背景／查詢競爭回歸後，受影響的 presentation／composition／Live loop 共 94 項重跑通過。完整 Safe Walk 靜態分析無問題；Schema 同步、模組邊界及犯罪資料隔離檢查通過。Web release 編譯通過（既有 `flutter_tts` 的 Wasm dry-run 警告不影響 JavaScript release build）。
- 沒有修改既有犯罪參考資料（查驗共 2,542 筆）、Demo reset、附近協助者或 TownPass 登入流程。未重新發布 App，未完成 iPhone 實機驗收；不以此宣稱全產品 LIVE_VERIFIED。

## 2026-11-08 高精度座標確認誤判修正

實際原生 App 的提交回 HTTP 200，資料也已儲存，但資料庫 session 的 `extra_float_digits=0` 將座標 JSON 四捨五入至 15 位有效數字。App 為核對儲存內容而使用嚴格 double 相等，故地圖點選產生的較長座標會被誤判為「尚未確認回報已儲存」。先前測試的短小數座標未涵蓋這個邊界。

`03_fix_float_precision.sql` 已以 `fix_map_report_float_precision` 套用至既有專案；只將兩個 RPC 的函式區域 `extra_float_digits` 固定為 `3`，使 JSON 保留 double 的精確往返值。新安裝的 `01_map_report_api.sql` 同步設定。這不改動回報內容、ACL／RLS、函式權限／簽章、全域設定或犯罪參考資料；已安裝版本的嚴格核對可直接恢復，無須重裝 App。既有冪等 UUID 機制繼續生效，重試不增加相同回報。

修正前，真實 HTTP 讀取的座標位元 checksum 與資料庫不符；修正後相符。查驗只輸出筆數與是否相符，不輸出回報座標或說明；既有 3 筆回報保留。`02_verify_rollback.sql` 改用高精度人工座標，在外層精度仍為 `0` 時驗證提交、同 UUID 重試、重讀、JSON 轉文字再解析及設定作用域還原，測試資料全部回滾。Dart 回歸覆蓋完整精度成功及截短回應拒絕，保留嚴格內容核對。

此次資料庫回滾驗證、公開 HTTP 精度核對與 32 項回報 Repository／接線／畫面測試均通過；完整 Safe Walk 嚴格靜態分析、Schema 同步、模組邊界及犯罪資料隔離檢查通過。未呼叫正式 HTTP 新增來產生人工公開回報，未等待 App 封裝。

技術依據：[PostgreSQL 浮點輸出與 extra_float_digits](https://www.postgresql.org/docs/17/datatype-numeric.html#DATATYPE-FLOAT)、[函式 SET 設定作用域](https://www.postgresql.org/docs/17/sql-createfunction.html)。
