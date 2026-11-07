## 使用者功能與完成定義

<!-- LIVE-FIRST DEVELOPMENT + NO PRODUCTION MOCK：直接交付真實 Provider → 正式 UI 的完整使用者流程；不要求先做 Mock／Demo。測試替身只限隔離測試，不得由正式入口選用。 -->

<!-- 依 repository 流程先建立 issue，並填寫關聯；以小型功能或可審查增量提交。 -->
關聯 issue：
完成的使用者功能：
完成定義與接收審查者：
正式入口 → 使用者操作／同意 → 真實 Provider／資料 → UI 結果：
失敗／無資料／取消／逾時與 Unavailable 的阻塞原因、下一步：

## 修改範圍與契約

- 主要修改檔案：
- 影響模組、原主要負責人及同檔案並行協調：
- 新增／修改的契約（無則填無）：
- Stacked parent PR／base／head SHA（不適用則填無）：

## 審查層級

<!-- 依 docs/SAFE_WALK_COLLABORATION.md；跨目錄本身不提升層級。 -->
- [ ] Level A：一般功能；一位具權限的非作者隊員 Review
- [ ] Level B：共用契約／套件／route／原生／大型 UI／CI 等；對應主要負責人合併前確認
- [ ] Level C：真實外部影響／身分權限／敏感位置／正式開關；隊長明確授權及安全／隱私驗收

需確認的主要負責人／隊長與證據：

## 實際驗證

| 命令／檢查 | 實際結果（PASS／FAIL／未執行／skip） | 證據／限制 |
|---|---|---|
| 相關測試／必要 CI | | |

尚未驗證的部分、裝置／外部依賴與後續工作：

## Live 與安全影響

- Live 可用性／啟用開關是否變更：
- 是否有真實外部作用、敏感位置、通知或安全／隱私影響：
- 所需同意、授權與驗收；未完成時的隔離／Unavailable：
- 真實資料來源、日期、精度／限制與 smoke／裝置證據；不得用參考點宣稱精確案發點或安全避讓：
- 持久犯罪資料與 CI／Demo reset 隔離、受限唯讀介面與 App 無管理憑證：

## 提交確認

- [ ] 修改符合 Live MVP 與協作規範，Schema／DI／import guard 仍有效
- [ ] 未弱化既有功能／必要 CI，未把未驗證或 skip 寫成 PASS
- [ ] 已列明適用 A/B/C 審查；不直接推 main、不自行 merge
- [ ] 正式入口 Live-only，無 Mock Provider／DemoGeo／假資料／固定成功或 Mock fallback；canonical DataMode 相容值僅供測試
- [ ] 未以文案、live=true、readiness 變更冒充完成；每項缺口標準確狀態與下一步，Fake 測試不當成 LIVE_VERIFIED
- [ ] 競賽導航在 App 內使用 OSM／合法路網，不導往 Google Maps、不新增 AED；未授權 SMS／附近通知／警消派遣維持 BLOCKED
