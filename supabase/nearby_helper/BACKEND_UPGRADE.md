# 附近協助者完整 RPC：既有四表升級包

現況：**owner-only 封鎖版已依後續授權部署，遠端 verifier PASS，通知未啟用，R13 維持 BLOCKED**。見[實際部署紀錄](DEPLOYMENT_20261113.md)。下文記錄前一階段的升級包與本機驗證；其帶 authenticated EXECUTE grant 的原始版本沒有部署。現行遠端使用封鎖版及 `06_verify_locked_backend.sql`，不可再以四表基線或啟用版 verifier 判斷現況。
2026-11-13（Asia/Taipei），基於團隊 main `fe509da`；分支
`feat/nearby-backend-upgrade-20261113`。M1 小魚負責平台／後端；本輪不改 App、共用 wire Schema、套件、正式開關或 CI。
使用者授權遠端唯讀盤點及本機 migration／verifier／升級測試，明確要求先不要部署。

## 已完成的遠端唯讀盤點

目標為 App 既有 Supabase 專案 `gxofnhzkqcmzrftxqddi`（csfishy's Project）。
透過已登入的 Dashboard SQL Editor 執行 `BEGIN TRANSACTION READ ONLY`、catalog 查詢及 `ROLLBACK`。
只查結構與權限，不呼叫業務 RPC、不讀取使用者／位置／通知內容，也沒有計算業務表筆數。
查詢等價版本保存在 [03_inventory.sql](03_inventory.sql)。瀏覽器匯出未成功，本表是當時可見結果的摘要，沒有另存的原始 JSON 證據檔。

| 項目 | 實際觀察 |
|---|---|
| PostGIS | `3.3.7`，位於 `public` |
| pgcrypto | `1.3`，位於 `extensions` |
| pg_cron | extension 清單中未安裝；本次沒有讀排程資料表 |
| 私有表 | `helper_profiles`、`helper_locations`、`alerts`、`alert_deliveries`，共 20 欄 |
| 擁有者／防護 | 四表 owner 均為 `postgres`、RLS 開啟、零 policy、零自訂 trigger |
| API 直接權限 | `anon`、`authenticated`、`service_role` 均無 schema usage、表或欄位存取權 |
| 定位精度 | `accuracy_m real` 可為 NULL，CHECK 允許 NULL 或非負值 |
| 原收件人 FK | `alert_deliveries.recipient_id → helper_profiles.user_id ON DELETE CASCADE` |
| 新版 RPC | 沒有 `public.nearby_*`，私有 schema 也沒有函式 |
| 舊版 RPC | 下列三個 SECURITY DEFINER RPC 均仍允許 `anon`、`authenticated` 執行，PUBLIC execute 為 false |

舊版簽章及當時 `md5(prosrc)`：

| 簽章 | body MD5 |
|---|---|
| `public.set_helper_opt_in(uuid,boolean,double precision,double precision)` | `25877c325a038e05a1c48c9698f05d12` |
| `public.send_emergency_alert(uuid,double precision,double precision,integer)` | `e0ee27f3736f118e478fa967db197bce` |
| `public.fetch_pending_alerts(uuid)` | `3448cc699c5efb1da097b73d95fdc273` |

三者 owner 為 postgres，`search_path=public, extensions`。本包保留它們的定義與 ACL；這是仍須處理的既有風險，不代表本輪已撤權。尚未查驗 Auth anonymous 設定、CAPTCHA、Data API exposed-schema 設定、備份可恢復性或真實裝置。

## 交付檔案

| 檔案 | 用途 |
|---|---|
| [20261113000000_upgrade_nearby_backend.sql](migrations/20261113000000_upgrade_nearby_backend.sql) | 獨立、交易式、一次性前向 migration；留在手動目錄，不由 CI／App 自動執行 |
| [04_verify_backend.sql](04_verify_backend.sql) | 獨立唯讀 catalog verifier，不呼叫業務或清除 RPC |
| [run_upgrade_tests.cjs](local_test/run_upgrade_tests.cjs) | 僅接受 loopback 與自動產生的 disposable database 名稱；完整升級與併發測試 |
| [20_upgrade_fixture.sql](local_test/20_upgrade_fixture.sql) | 非空舊版四表、人工資料與舊 RPC stand-in |
| [21_assert_preserved.sql](local_test/21_assert_preserved.sql) | 升級前後資料雜湊、無關資料與舊 RPC 定義／ACL 比對；驗新 FK cascade |
| [30_test_upgraded_backend.sql](local_test/30_test_upgraded_backend.sql) | 既有完整行為測試，適配 public PostGIS 與聯絡人 sender_name |
| [generate_upgrade.py](local_test/generate_upgrade.py) | 無網路／資料庫連線的產生器；`--check` 檢查產物一致性 |
| [verify_backend_extra.sql](local_test/verify_backend_extra.sql) | verifier 範本片段，不能單獨拿來當完整驗收 |

歷史 `001_nearby_helper.sql` 與 `02_verify.sql` 保留原樣。前者是 fresh-install 來源，後者只驗原四表，不能用來驗完整 RPC。產生器從兩者衍生完整、可單獨審查的 SQL；部署時無須產生器，也沒有 psql include 依賴。

## migration 的具體行為

1. 設定 5 秒 lock timeout、60 秒 statement timeout，鎖定既有四表，先驗證舊版 20 欄、型別、defaults、12 個約束、GiST、RLS、零 policy／trigger／私有函式及有效 API ACL。版本／結構漂移或已存在新版 RPC 直接中止；只接受 schema owner 執行。
2. 要求現有 PostGIS 位於 public、pgcrypto 位於 extensions；不安裝或搬移 extension。
3. 補上 consent_version 的 1–64 字 CHECK。既有不合法資料會使整筆交易失敗，不自動修剪／刪除。
4. 將既有收件人 FK 改指向 `auth.users(id)`，保留 CASCADE 並驗證既有資料。
5. 新增 `helper_areas`、`contact_invites`、`trusted_contacts`、`contact_invite_attempts`，必要索引、13 個新版 public RPC 及私有 `purge_expired()`。
6. PostGIS 呼叫明確使用 public，雜湊與隨機碼使用 extensions；所有函式固定空 search_path。表與 schema 不授予 API 存取；只授予 authenticated 執行 13 個 public RPC，清除函式不授予任何 API 角色。
7. 同帳號的寫入先取得 transaction advisory lock，再檢查限流與寫入，避免併發首次定位／SOS 繞過限制。聯絡人寫入另共用一把 transaction advisory lock，使邀請碼消耗、配對數量與撤銷依序執行；這是吞吐量取捨，尚未做負載驗收。
8. **提交前執行與 verifier 相同的完整 postconditions**。欄位、函式內容、權限或新增物件不符即整筆回滾，不留下部分升級。

既有四表的業務資料不變；migration 本身沒有 seed、清除、位置上傳或通知動作。清除函式只建立而不呼叫；不建立 Cron job，不開啟匿名登入，不改其他業務 schema，不調整舊版 RPC。

升級後固定為 8 表、37 欄、26 個約束（7 PK、10 CASCADE FK、2 UNIQUE、7 CHECK）、13 個 public RPC 與 1 個私有函式。
verifier 另檢查有效／原始 ACL、非 owner 的多餘 schema／表／欄位 grant、函式 owner、input names／型別、output、default、body MD5、SECURITY DEFINER、search_path 與索引。
它不讀業務內容，不驗證「通知已送達」，也不證明資格或營運政策已完成。

## 重現本機測試

需要 Node.js、Python 3、**僅監聽本機**的 PostgreSQL 16＋PostGIS＋pgcrypto，以及獨立工具目錄的 `pg` Node 套件。
`pg` 不加入 App 的相依套件或 lockfile。測試管理帳號為隔離環境的 postgres，環境需允許建立 database／角色與 extensions。

```powershell
python supabase/nearby_helper/local_test/generate_upgrade.py --check
node supabase/nearby_helper/local_test/run_upgrade_tests.cjs --pg-module <外部工具目錄>/node_modules/pg --port 55439 --expect-postgis 3.3.7 --report <本機報告路徑>.json
```

runner 不接受遠端 host、連線字串或既有目標 database。它固定連 `127.0.0.1`，確認伺服器實際位址，再建立隨機 `nearby_upgrade_<12位hex>` 資料庫，於 finally 關閉 session 並刪除本輪建立的測試 database；不刪目錄、角色或其他 database。不得修改 runner 的 host 限制以便連到 Supabase。
`--expect-postgis` 會在每個 fixture 的 migration 前，分別核對實際 library、已安裝 SQL scripts 與 extension 的精確發佈版號。3.3.7 的 `postgis_scripts_installed()` 另含十六進位來源 revision（例如 `3.3.7 a0c7967`），比較時辨識該後綴，報告保留完整原值；dev／prerelease／未知後綴或不同版號仍拒絕。`--report` 輸出版本、每組結果與測試輸入檔案的 SHA-256，供比對已驗證的 SQL 是否與工作區一致。
本機 bootstrap 會建立假的 auth.users／auth.uid，**不可拿到遠端執行**；人工 SQL fixtures 也有本機 database 名稱／位址檢查。

先前驗證：2026-11-13，Windows，可攜式 PostgreSQL **16.15**＋PostGIS **3.6.2**＋pgcrypto **1.3**。
完整 runner **18 組測試通過**；其中既有行為 suite 含 73 處結果斷言與 50 處預期拒絕呼叫（含迴圈，並非獨立案例總數）。
測試使用 npm `@embedded-postgres/windows-x64@16.15.0-beta.19`、OSGeo `postgis-bundle-pg16-3.6.2x64.zip` 及外部工具目錄的 pg 用戶端。
遠端 PostGIS 是 **3.3.7**；本輪已補完相同發佈版號的隔離重驗，結果見下節。這不代表遠端的 PostgreSQL、GEOS、PROJ、Auth 或權限環境已全部複製，也沒有執行遠端 migration。

Schema generator `--check`、正常 module boundary guard、犯罪資料隔離 guard、SQL 產物 `--check`、Node 語法及文件連結／空白檢查依本輪實跑紀錄驗證。無 App 程式變更，未執行 Flutter build／裝置測試；本機測試不等於遠端部署驗收。

涵蓋非空升級與資料保留、13 RPC 的 anon／無 session 拒絕、跨帳號存取、499／501 公尺、10 分鐘位置 TTL、30 分鐘 SOS TTL、guard areas、聯絡人邀請／上限／撤銷、清除與級聯刪除、50 位 helper 上限及聯絡人去重、並行 SOS 冪等／限流、首次定位限流與同邀請碼跨帳號競爭。
負向升級涵蓋 schema 漂移、extension schema 錯誤、既有新版 RPC、既有無效 consent 與新增表繼承危險 default grant 的**交易末端回滾**。verifier mutation 測試涵蓋函式、權限、索引、FK 與 CHECK 被更動的拒絕。

## 2026-11-13：PostGIS 3.3.7 精確版本相容性重驗

**PASS：18 組全部通過。** 實際執行時間為臺北時間 15:45:03–15:46:26。
機器可讀的[測試報告](local_test/evidence/postgis-3.3.7.json)包含每組結果、完整版本及 11 份實際測試輸入的 SHA-256；已逐一比對工作區一致。

| 項目 | 實際值 |
|---|---|
| 環境 | Windows 主機內的可丟棄 QEMU／Alpine Linux 3.18，僅使用人工身分與位置 |
| PostgreSQL | 15.13，x86_64-alpine-linux-musl |
| PostGIS library | `3.3.7` |
| PostGIS SQL scripts | `3.3.7 a0c7967` |
| PostGIS extension | `3.3.7` |
| pgcrypto | `1.3`，位於 extensions |
| PostGIS schema | public，與已盤點遠端相同 |
| GEOS／PROJ | `3.11.2-CAPI-1.17.2`／`9.2.1` |

本輪相容性修正限於測試 runner：原先要求 `postgis_scripts_installed()` 原字串完全等於 `3.3.7`，會錯誤拒絕官方 3.3.7 的 `3.3.7 a0c7967`。現在只辨識正式版號後的十六進位來源 revision，仍逐一核對 library／scripts／extension 的精確發佈版號，完整字串保存在報告中。負向驗證也確認此環境在要求 `3.6.2` 時會在 migration 前拒絕。

**migration 與 verifier 無須修改**，18 組涵蓋上述全部升級、權限、距離、TTL、聯絡人、併發、去重及回滾測試。此次測試使用的 SQL 雜湊：

```text
migration 17535042aa58baf30f037e065f5cbb0bb83cf2ca7a480333bdc33e3f055d79bf
verifier  9874032fe8cc5fcad3ba1830f5cd5a6acefbc6ab422a6390b1969ea00af14b0a
```

使用經核對的 [PostGIS 官方 3.3.7 發佈原始碼](https://postgis.net/stuff/postgis-3.3.7.tar.gz)，與[官方 MD5 檔](https://postgis.net/stuff/postgis-3.3.7.tar.gz.md5)相符：

```text
MD5    2c2d406fcf2769601ddc6b4605475de9
SHA256 2d52f4951b1121894463186201ae532d629ea29ab3c31ee8ece8085ea086013d
```

重現時，先在隔離 Linux 安裝 PostgreSQL 15 server／dev／contrib、GEOS／PROJ／json-c／libxml2 dev、gcc／g++／make／pkgconf／Perl／Node.js，以及外部工具目錄的 pg 套件。原始碼未修改，建置核心 extension 時停用不涉及本功能的 raster／topology／SFCGAL／protobuf／address-standardizer：

```sh
./configure CFLAGS='-O0 -g0 -fPIC' CXXFLAGS='-O0 -g0 -fPIC' \
  --with-pgconfig=/usr/libexec/postgresql15/pg_config \
  --without-raster --without-topology --without-sfcgal \
  --without-protobuf --without-address-standardizer
make -j4 with_llvm=no
make install with_llvm=no INSTALL='/usr/bin/install -c' MKDIR_P='/bin/mkdir -p' \
  install_sh='/bin/sh /root/postgis-3.3.7/build-aux/install-sh'
```

以上 PG_CONFIG 與 install_sh 為本輪隔離環境路徑，其他環境須改為其實際路徑。Alpine PGXS 的安裝工具預設路徑不適用此 source tree，故明確指定原始碼附帶的 build-aux/install-sh；未修改 PostGIS 程式。此為功能相容性測試，未做效能驗收。

以隔離帳號初始化本機 PostgreSQL、只監聽 127.0.0.1，再執行上節的 `--expect-postgis 3.3.7 --report ...` 指令。runner 會自行建立／清理測試 database；本輪完成後 PostgreSQL 與 VM 均已關閉。未連線遠端資料庫、未啟用正式通知，R13 保持 BLOCKED。

## 後續部署與啟用前仍須處理

本次交付不是部署指令，也不更新 Readiness。後續須另外取得部署授權／Level C 安全審查，重新唯讀盤點確認目標未漂移，準備並驗證可恢復備份；先在受控環境驗證本包，再安排正式操作。
本 migration 有新 public RPC 的 EXECUTE grant，**不能在資格／防濫用未完成前把「部署但不開 UI」當作安全隔離**。

- Supabase Auth `auth.uid()` 提供 ownership，但匿名帳號不等於協助者資格；目前 RPC 的 helper 身分仍來自本人 opt-in，尚缺伺服器資格審核及抗大量建立帳號措施。
- 舊三個匿名 RPC 的撤權／退役與既有位置資料保留須另外審查；本包不改它們，不能宣稱全專案已安全。
- 本包沒有 FCM／APNs、背景接收、CAPTCHA、裝置驗證、安全憑證儲存或營運監測。現有 client 的傳遞仍是前景輪詢＋橫幅。
- Auth anonymous sign-ins 的設定、帳號建立速率、同意及保留政策、Cron 清除排程、雙裝置收送／退出／撤回驗收，均未在遠端執行或確認。
- 若升級失敗，交易會回滾；若升級已提交，**沒有破壞性的自動 down migration**。不要用刪表／重跑初次建表來回退，應保留資料並另做修正或依備份復原方案處理。
