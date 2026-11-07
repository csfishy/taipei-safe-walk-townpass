# 臺北安心行：2026 競賽交付形態與授權待確認事項

> 本文件保留查閱時的規則／授權證據與待確認事項；「本次初始化」「未修改 UI／未建立網站」是當時工作範圍，不是現行產品禁令。工程目標以 [Live MVP](SAFE_WALK_LIVE_MVP.md) 為準，原生入口、build／Pages 及功能狀態以目前程式／CI／Readiness 為準；必要授權限制繼續保留，不阻擋合法導航、查詢、TTS 與主動求助入口的開發。

查閱日期：**2026-11-07（Asia/Taipei）**。適用活動：**2026 臺北秋季程式設計節／城市通微服務大黑客松**。

本文件記錄已查到的當年規則、官方技術資料及工程判讀。它不是主辦單位的准許函，也不是本專案授權相容性已完成法律審核的證明。**本次保留上游 `LICENSE`，沒有將官方 TownPass 改授權為 AGPL，也沒有宣稱獨立原生 App 已獲競賽核准。**

## 1. 現在可以確認什麼

| 問題 | 證據與目前結論 |
|---|---|
| 這是 2026 秋季的規則嗎？ | 是。資訊局的 2026-09-01 公告將活動指向 `codefest.taipei`；現行入口轉至 `/2026-fall/`。官網下載的《2026臺北秋季程式設計節_競賽須知(final).pdf》為 **115.08.27 版，共 10 頁**。本文件沒有把 2024 或 2026 春季規則套用到秋季。[市府公告](https://doit.gov.taipei/News_Content.aspx?n=4B2B1AB4B23E7EA8&s=7ECEA3E02747DFFE&sms=72544237BBE4C5F6)、[當年官網規則](https://codefest.taipei/2026-fall/rules/)、[官網下載的 PDF](https://drive.google.com/file/d/1sT5z0Bqy1mOUdRgCKIbaXM6Y3bvYXGOu/view) |
| Flutter 是否被當年規則排除？ | 沒有看到排除。須知第 1 頁「參、一、（三）、4」明列 Flutter／Dart 相關技能；第 4 頁「伍、二、（一）」要求以台北通為基礎開發城市通微服務。這支持採官方 Flutter 專案研究及開發，**不能單憑技能清單推定獨立 APK／IPA 即符合所有交件要求**。[2026 須知，第 1、4 頁](https://drive.google.com/file/d/1sT5z0Bqy1mOUdRgCKIbaXM6Y3bvYXGOu/view) |
| 可否只交獨立原生 App？ | **尚未確認。** 已讀規則沒有明確承諾「只交獨立 Flutter APK／IPA 即可」，也沒有找到「只接受 WebView 網站」的明文。原生功能整合到官方 Flutter App、由官方 App 開啟的 WebView 微服務、獨立安裝包，是不同交付形態；應由主辦確認本隊題目接受哪一種。[2026 須知，伍、二與柒](https://drive.google.com/file/d/1sT5z0Bqy1mOUdRgCKIbaXM6Y3bvYXGOu/view) |
| 參賽成果授權要求是什麼？ | 須知第 4 頁「參、三、（十二）」要求公開釋出競賽開發成果；第 9–10 頁「捌、一」要求團隊開發成果採 AGPL，附示範聲明採 **version 3 or later**。這不是已完成的本專案授權設定。[2026 須知，第 4、9–10 頁](https://drive.google.com/file/d/1sT5z0Bqy1mOUdRgCKIbaXM6Y3bvYXGOu/view) |
| 官方 Flutter 基底目前是什麼授權？ | 本次採用 `taipei-doit/TownPass`，基底 commit 為 `c8e5d4d3f8f699f3d9d6cd68e129ed4da12037b3`；其根目錄 `LICENSE` 是 **GNU GPL version 3**。GitHub 的 `GPL-3.0` 分類不等於已確認每個來源檔、依賴或素材的授權，也不能只因授權文件末尾的通用範例就推定所有上游程式均為 `GPL-3.0-or-later`。[固定基底的 LICENSE](https://github.com/taipei-doit/TownPass/blob/c8e5d4d3f8f699f3d9d6cd68e129ed4da12037b3/LICENSE) |

## 2. 官方架構資料支持哪些整合方式

官方 TownPass README 的開發需求包含 Flutter、Xcode、Android SDK，並以 `flutter run` 啟動；這是官方 Flutter App 專案，不只是網頁模板。[固定基底 README](https://github.com/taipei-doit/TownPass/blob/c8e5d4d3f8f699f3d9d6cd68e129ed4da12037b3/README.md)

官方技術文件同時有 Flutter 與 Web 微服務章節。服務入口範例以 `MyServiceItem.destinationUrl` 指向服務網址；雙向連線文件則說明 Flutter App 透過 `flutter_inappwebview` 與 WebView 交換訊息。**這證明官方存在 WebView 微服務接入方式，不代表 2026 主辦已要求本隊只能採此方式，也不代表任何自訂原生頁面均已獲交件許可。** [官方服務入口文件](https://townpass.taipei/en/docs/flutter/taipeipass-service/custom-design.html)、[官方 App／WebView 雙向連線](https://townpass.taipei/en/docs/two-way-connection/)

工程上的暫定安排：在這份新基底隔離臺北安心行的資料模型、服務介面與平台整合，保留之後替換入口 adapter 的空間。如果主辦要求 WebView／服務網址，再依官方服務入口及雙向訊息介面接入。這只是備案方向；目前沒有因此建立網站、後端、正式通報或 WebView adapter，也沒有操作、複製或修改舊 React 專案。Flutter 原生 UI 不會因保留模型就自動變成可部署的 WebView 微服務；轉接工作仍需另行評估。

## 3. GPLv3 與 AGPLv3：原文與工程判讀分開

### 可以直接對照的 GNU 條款

| 來源 | 原文所處理的事項 | 本文件的工程判讀 |
|---|---|---|
| GPLv3 第 13 條 | 允許 GPLv3 covered work 與 AGPLv3 work 連結或結合；GPL 部分仍受 GPL 約束，AGPL 第 13 條的網路互動特殊要求適用於結合作品。 | 有特定的結合機制；**不能據此刪除上游 GPL 聲明，或將所有上游程式一律改標 AGPL**。[GPLv3 原文](https://www.gnu.org/licenses/gpl-3.0.txt) |
| AGPLv3 第 13 條 | 對支援遠端網路互動的修改版，要求向相應遠端使用者明顯提供免費取得 Corresponding Source 的機會；亦處理與 GPLv3 work 的結合，並保留該 GPL 部分的授權。 | AGPL 多了特定的網路互動源碼提供義務；是否觸發須看實際修改與互動方式，不能僅依「有 HTTP」「是 App」或「是 WebView」判定。[AGPLv3 原文](https://www.gnu.org/licenses/agpl-3.0.txt) |
| GNU FAQ：AGPL／GPL 結合與例外範圍 | 說明兩種 v3 授權的連結機制，並提醒這些條款是有限例外，不是忽略其他授權義務的通行證。 | 「GNU 條款允許特定結合」與「本次競賽接受本隊的授權安排」是兩個問題，後者仍需確認。[GNU FAQ：AGPLGPL](https://www.gnu.org/licenses/gpl-faq.en.html#AGPLGPL)、[GNU FAQ：v3Notwithstanding](https://www.gnu.org/licenses/gpl-faq.en.html#v3Notwithstanding) |

以上是條款內容的摘要及工程判讀，沒有為尚未完成的功能邊界、逐檔授權、素材或全部依賴作出相容保證。GNU FAQ 對 Corresponding Source 亦有專門說明，不能只提供新增幾個檔案就假定履行全部義務。[GNU FAQ：AGPLv3CorrespondingSource](https://www.gnu.org/licenses/gpl-faq.en.html#AGPLv3CorrespondingSource)

### 本次初始化採取的處理

1. 保留官方 `LICENSE`、上游版權／授權聲明及來源 commit，不用換檔名或覆蓋 LICENSE 的方式「解決」差異。
2. 記錄哪些檔案為團隊新增、哪些修改自上游、哪些為外部依賴或素材；團隊對自己沒有權利的內容不能代為重新授權。
3. 將「團隊新模組的授權方式、上游 GPL 部分的保留、結合作品的交付」列為待確認的具體方案。本文沒有先替新模組發布 AGPL 授權，也沒有對既有 GPL 檔案宣稱已獲改授權許可。
4. Repo 建立時為 Private，現已是 Public，且使用者於 2026-11-07 明確確認保留 Public。可見度公開不等於已完成競賽的授權與交付要求；公開的範圍、時間、指定程式庫及必要聲明仍需確認。本文件不會自行改變 Repository 可見度。
5. 規則另有一年不得下架及得獎者協作／授權安排；這些競賽文字不應被簡化成「GNU 授權一年後自動失效」。若期間或範圍有疑義，請主辦說明，並對照實際適用的 GNU 條款。[2026 須知，捌](https://drive.google.com/file/d/1sT5z0Bqy1mOUdRgCKIbaXM6Y3bvYXGOu/view)、[GPLv3 原文第 2 條](https://www.gnu.org/licenses/gpl-3.0.txt)

## 4. 請 M1 向主辦確認並保留回覆

以下均為 **待確認**；目前沒有主辦回覆，也沒有發出詢問或建立已核准紀錄。

| 問題 | 需要的明確答覆 |
|---|---|
| 原生功能交付 | 以官方 TownPass Flutter 基底新增安心行模組、提交修改源碼並展示 Android／iOS App，是否可作本隊正式成果？是否仍必須提供可由官方 App 開啟的 WebView 服務網址？ |
| 整合目標 | 指定的官方 repo、branch／commit、功能入口與合併單位是什麼？接受功能模組／patch，還是要求可移轉部署的獨立微服務？ |
| GPL 與 AGPL 的範圍 | 主辦要求的 AGPL v3-or-later 聲明，應涵蓋哪些團隊新增及修改成果？保留 TownPass 上游 GPLv3、另清楚識別團隊貢獻的安排是否接受？需哪些授權文件及權利人確認？ |
| 公開與交件 | 最遲何時公開、公開至哪個指定程式庫、應附哪些源碼／建置資料／聲明？一年不得下架及得獎後額外授權安排的適用範圍如何區分？ |
| 現場安裝與展示 | 評審是否接受開發簽章裝置展示？需要哪些平台與可安裝產物？未簽署 iOS 包不能直接當成已完成的現場安裝交付。 |
| 最新公告 | 2026-08-27 須知後的工作坊／競賽當日公告有無改動上述事項？請以主辦指定的最新版本為準。 |

確認後在本文件補上：回覆日期、主辦單位／回覆者身分、原文或可存取的紀錄連結、接受的交付形態、授權範圍與仍保留的條件。沒有證據前，不把狀態改為「已核准」或「授權已完全符合」。規則第玖條保留主辦修正與解釋權。[2026 須知，第 10 頁](https://drive.google.com/file/d/1sT5z0Bqy1mOUdRgCKIbaXM6Y3bvYXGOu/view)

## 5. 與後續功能選型直接相關的當年限制

2026 須知「伍、二」還要求核心／關鍵資料採合法公開開放資料並註明來源；非必要資料可用模擬值。第三方軟體／套件及服務須符合當年開源、可移轉、可維運及上架限制。雲端 AI 可用於開發，但作品執行時的 LLM 即時推論須在裝置端，固定預產內容不能冒稱即時 AI。這些是後續資料、地圖與陪伴功能選型的檢查點；初始化 mock、套件可編譯或採 Flutter，都不能代替成品符合性驗收。[2026 須知，第 4–5 頁](https://drive.google.com/file/d/1sT5z0Bqy1mOUdRgCKIbaXM6Y3bvYXGOu/view)

## 6. 來源與查閱方式

- [2026 秋季官網](https://codefest.taipei/2026-fall/)與[規則頁](https://codefest.taipei/2026-fall/rules/)：頁面使用 JavaScript；本次亦以文字讀取其[官方當年資料檔](https://codefest.taipei/2026-fall/_nuxt/BIFx-t61.js)，找到規則與下載連結，沒有執行該程式。該 UTF-8 文字的 SHA-256 為 `62afcdb9db75e4e7efd8b9613ef1eecd8f92f13739d8aba3b664f93fd705046a`；它是查閱時的內容指紋，並非主辦數位簽章。
- 官網下載連結 [url.taipei/sJ6m](https://url.taipei/sJ6m) 解析到上述 [Google Drive PDF](https://drive.google.com/file/d/1sT5z0Bqy1mOUdRgCKIbaXM6Y3bvYXGOu/view)。本次透過已連接的 Google Drive 讀取原件文字，確認檔名、115.08.27 版與第 1–10 頁內容；不是只依搜尋摘要推斷。
- [芳和實驗中學轉知公告](https://www.fhehs.tp.edu.tw/news/%E5%8F%B0%E5%8C%97%E5%B8%82%E9%9B%BB%E8%85%A6%E5%95%86%E6%A5%AD%E5%90%8C%E6%A5%AD%E5%85%AC%E6%9C%83%E6%89%BF%E8%BE%A6%E8%87%BA%E5%8C%97%E5%B8%82%E6%94%BF%E5%BA%9C%E8%B3%87%E8%A8%8A%E5%B1%80%E4%B8%BB/)附[同年須知 PDF](https://www.fhehs.tp.edu.tw/wp-content/uploads/doc/fh700/2026%E8%87%BA%E5%8C%97%E7%A7%8B%E5%AD%A3%E7%A8%8B%E5%BC%8F%E8%A8%AD%E8%A8%88%E7%AF%80_%E7%AB%B6%E8%B3%BD%E9%A0%88%E7%9F%A5.pdf)：僅作備援及交叉核對，優先採官網下載原件與主辦後續公告。
- [官方 TownPass 程式庫](https://github.com/taipei-doit/TownPass)、[固定基底 LICENSE](https://github.com/taipei-doit/TownPass/blob/c8e5d4d3f8f699f3d9d6cd68e129ed4da12037b3/LICENSE)及上述官方技術文件：架構與上游授權證據，不是本隊參賽核准。
- GNU 官方 [GPLv3](https://www.gnu.org/licenses/gpl-3.0.txt)、[AGPLv3](https://www.gnu.org/licenses/agpl-3.0.txt)及 [FAQ](https://www.gnu.org/licenses/gpl-faq.en.html#AGPLGPL)：已讀兩份第 13 條原文；本文件摘要與工程建議不替代完整條款。

本文件僅記錄規則、授權證據與待確認事項；上游 LICENSE 未替換。初始化另在 README 前置團隊文件入口並新增團隊 CI，保留原 README 內容，未修改官方 UI。沒有向主辦發送詢問，也未對競賽資格、最終交付或授權相容性作出已通過宣告。
