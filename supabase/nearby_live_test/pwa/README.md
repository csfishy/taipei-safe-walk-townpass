# PWA v2 — 手動升級，未部署

僅擴充既有 `safe_walk_nearby_live_test`；不修改 `safe_walk_nearby`、13 個 owner-only `nearby_*`、舊 3 RPC、Auth、SMTP、犯罪資料庫。
不延長 Live 截止、不開啟推播。使用者授權先實作及隔離驗證，暫不部署。

升級前先執行 immutable v1 `../03_verify.sql` 與 `../04_production_snapshot_readonly.sql`，保存正式資料／ACL 摘要。
`01_upgrade.sql` 本身在交易內再核對 v1 schema／函式 body／ACL；有 drift 就 rollback。
新增表 2、private helper 2、receiver RPC 6、worker RPC 2；修改既有 `swtest_send` 與帳號 opt-out，維持原簽名。
`swtest_logout` 重新宣告相同實作，session FK cascade 會移除該 session 裝置與 outbox。
升級後總計 private 表 8、helper 4、public swtest RPC 15。直接 schema/table 權限仍全部關閉。

`02_verify.sql` 是新的唯讀 v2 verifier，同時內含未變更的正式 backend verifier。
它核對 PostGIS 3.3.7、19 個函式 body hash/security-definer/search_path/owner/ACL、RLS/no policies、物件數與新表 constraints/index。
原 v1 verifier 在 v2 後應拒絕執行（數量不同），不能沿用舊 PASS。

```sh
python supabase/nearby_live_test/pwa/generate_verifier.py --check
node supabase/nearby_live_test/pwa/run_tests.cjs --pg-module /local/node_modules/pg --report /local/pwa-report.json
```

runner 強制 localhost:55439、隨機 `nearby_upgrade_*` 拋棄式 DB、實際 PostGIS 3.3.7；不接受遠端 DSN。
從正式舊版 upgrade fixture、鎖定正式 backend、已有人／位置／呼救的 v1 升級，含 CRLF 與權限 drift rollback。
人工帳號 `*.example.invalid` 與人工座標只在隔離 DB；無信件／推播／外部位置查詢。
測試結果見 `evidence/postgis-3.3.7.json`；實際 PG 15.13，不冒稱遠端 PG 17.11。

位置是每裝置最後一筆，不儲存軌跡；30 分鐘有效，session／global deadline 更短時從短。
期限在每次選收、fetch、更新與 worker claim 即時生效，不依賴排程。
`03_cleanup.sql` 是 owner-only 手動／可信排程腳本：實體移除過期 outbox、清空到期裝置位置，session/Live 結束則刪除 subscription。
建議部署獲准後每分鐘執行；本次沒有建立 Cron。未排程時資料仍可能實體留存，不能把 RPC 失效宣稱為已刪除。
有效 alert 的 outbox 會保留到 alert／裝置到期，供前景地圖讀取；provider TTL 60 秒不等於呼救 30 分鐘有效期。

後續部署須先重新確認遠端 v1 結構，套用 `01_upgrade.sql`，執行 `02_verify.sql` 及正式 snapshot 比對；
再經授權配置 worker、VAPID、HTTPS 網頁、清理排程及 `control.push_enabled`。不要重新執行 48h enable 腳本當成升級步驟。
回復停用：owner 關閉 `push_enabled`、停止 worker 與前端入口；若已啟用 PWA，須同時撤銷 lease／清空位置與未送出工作。
不要直接 drop 新表或倒灌舊 `swtest_send`；應另寫經驗證的 forward migration。
