# 附近求助推播通知：實施計畫

狀態：**計畫（PLAN）**，尚未實作、未部署、未在任何遠端資料庫或 Firebase 專案執行。附近通知（R13）維持 **BLOCKED**。本文件只定義要做什麼、先決定什麼、怎麼分階段驗收；不改變任何程式或旗標。

前置文件：[設計提案](SAFE_WALK_NEARBY_HELPER_DESIGN.md)（後端與資料模型）、[安全狀態](SAFE_WALK_NEARBY_SECURITY.md)（重新啟用的必要證據）。

## 1. 為什麼需要推播

目前的傳遞方式是 **App 內通知**：協助者的 App 開啟（前景）時才會每 10 秒查詢並顯示橫幅。App 在背景或關閉時，**完全收不到**求助，也不會更新位置。這對真正的求助情境太窄。推播能在 App 不在前景時叫醒使用者，但它帶來三個不能忽略的問題：

1. **推播要送給誰？** 協助者的位置只在前景更新、10 分鐘後過期。App 關閉後位置過期，就永遠不會被選為收件人。沒有解決這點，光加推播沒有用（見第 3 節 D3）。
2. **推播內容會經過 Apple／Google 的伺服器**，並顯示在鎖定畫面。座標與任何身分都不能放進去。
3. **現行 iOS 預覽包無法收推播**（見第 2 節）。

### 目標與非目標

| 目標 | 非目標 |
|---|---|
| App 在背景或關閉時，已加入的協助者仍可收到「附近有人求助」 | 簡訊（SMS）傳遞 |
| 點擊通知後進入 App 看到與前景相同的求助橫幅 | 官方報案、派遣、受理編號（`officialReceipt` 維持 `null`） |
| 推播內容不含位置與身分 | 通知未加入協助的人、全市廣播 |
| 可隨時撤銷，撤銷後不再收到並刪除裝置 token | 預設啟用任何背景定位（見 D3，需另案決策） |

## 2. 現況（已對照原始碼）

| 項目 | 現況 | 來源 |
|---|---|---|
| 傳遞方式 | 前景輪詢＋App 內橫幅；背景與關閉時不運作 | `nearby_helper_controller.dart`（PR #76） |
| 推播相依 | **沒有** Firebase、`firebase_messaging` 或其他推播套件；只有本機通知 `flutter_local_notifications` | `pubspec.yaml` |
| Android | `applicationId` 為預覽身分 `io.github.csfishy.taipeisafewalktownpass.preview`；release 以 **debug keystore** 簽署；Manifest 已宣告 `ACCESS_BACKGROUND_LOCATION`（官方既有），**沒有** `POST_NOTIFICATIONS` | `android/app/build.gradle`、`AndroidManifest.xml` |
| iOS | CI 建置為 `--no-codesign` 的**未簽章 IPA**；專案**沒有** entitlements 檔、`Info.plist` 沒有 `UIBackgroundModes` → 現行產物**無法**收到 APNs 推播 | `.github/workflows/build.yml`、`ios/Runner/Info.plist` |
| 後端 | Supabase 已有四張私有空表；`001_nearby_helper.sql` 的 RPC 尚未部署；`sos_send` 會寫入 `alert_deliveries` | `supabase/nearby_helper/` |
| 官方通知服務 | `NotificationService` 只做本機通知，且 App 還在執行時才能顯示 | `lib/service/notification_service.dart` |

## 3. 必須先決定的事

下表是整個計畫的前提。**D3 是最關鍵的**；D1、D2 決定能做到多少。表中對 Apple、Google 與 Supabase 平台規定的敘述是撰寫時的理解，P0 需對照當時的官方文件確認，不能直接當事實。

| 編號 | 問題 | 選項 | 建議 | 決定者 |
|---|---|---|---|---|
| D1 | 推播通道 | A. FCM（Android 直接、iOS 經 APNs）；B. 自己直連 APNs 與 FCM；C. 第三方服務；D. 不做推播，維持前景 | **A**：Flutter 有官方套件，單一發送端 | M1 小魚、隊長 |
| D2 | iOS 簽章 | A. 取得 Apple Developer 帳號、APNs 金鑰，改為簽章建置（TestFlight 或 ad-hoc）；B. 先只做 Android，iOS 維持前景 | **B 先行**，A 待帳號與 Mac 建置環境到位；Windows 無法本機編譯 iOS | 隊長 |
| D3 | 觸及策略（App 關閉時，怎麼知道誰在附近） | A. 背景定位（iOS Always、Android 背景定位）；B. **固定守護區**：協助者自選最多 3 個圓形區域（例如住家、公司附近），不傳即時位置；C. 顯著位置變化／地理圍欄；D. 延長位置 TTL | **B 先做**：隱私成本最低、不需背景定位；A、C 另案，需獨立的同意、審查與電量評估 | 隊長、M3 莅紋 |
| D4 | 推播內容 | 通用文字，不含座標與身分，點開後經已驗證 session 取詳情 | **通用文字**（見第 5 節） | 隊長 |
| D5 | 發送端 | A. Supabase Edge Function＋outbox；B. 自管伺服器 | **A**：服務帳號金鑰只放在 Function secrets | M1 小魚 |
| D6 | 中斷等級 | iOS Time Sensitive（需 capability，無需特別核准）vs Critical Alerts（需 Apple 特別核准）；Android 高重要性 channel | **Time Sensitive**＋高重要性 channel | M3 莅紋、隊長 |
| D7 | 身分來源 | TownPass 登入或 Supabase Auth（與 #70、#71 同一個待決事項） | 先定案才能綁定 token 到使用者 | M1 小魚、隊長 |

### D3 為什麼影響最大

目前 `helper_locations` 只留最新一筆、TTL 10 分鐘，而且只在前景更新。推播的收件人由伺服器端 `ST_DWithin` 在**有效位置**中挑選，所以：

- 若沒有任何背景位置來源，App 關閉 10 分鐘後這位協助者就不會被選中，推播沒有對象。
- **B 方案（守護區）** 讓協助者主動指定「我通常在這附近、願意被通知」。伺服器只保存圓心（建議以約 100 公尺網格四捨五入）與半徑，不收即時位置。SOS 落在守護區半徑（500、1000 或 2000 公尺）內就通知。缺點是只涵蓋固定地點，涵蓋不到移動中的人，文案不能暗示「附近就一定會通知」。
- **A 方案（背景定位）** 覆蓋最好，但持續追蹤的隱私、電量、商店審查與 `AGENTS.md` 的「不得自動追蹤」都要重新評估，本計畫不預設採用。

## 4. 架構

```
SOS 送出
  └─ nearby_sos_send（既有）建立 alert 與 alert_deliveries
       └─ 新：寫入 push_outbox（每位收件人一筆）
            └─ Edge Function send-nearby-push
                 ├─ 取一批待送項目（跳過已過期的 alert）
                 ├─ 查收件人的裝置 token（只在伺服器內）
                 ├─ 以 FCM HTTP v1 傳送「通用文字」通知
                 └─ 回報處理：成功／token 失效就刪除／暫時錯誤退避重試

協助者的 App
  ├─ 加入協助、並另外同意推播 → 註冊 token（RPC）
  ├─ 前景收到推播 → 直接觸發既有輪詢，顯示既有橫幅
  ├─ 背景點擊通知 → 開啟安心行 → 立即輪詢 → 顯示橫幅（已過期則說明已過期）
  └─ 退出協助、登出、撤銷同意 → 取消註冊並刪除 token
```

## 5. 資料模型與介面（草案，不放入 `supabase/`）

```sql
-- DRAFT ONLY. Not deployed. Not for execution.
create table safe_walk_nearby.helper_devices (
  user_id uuid not null references safe_walk_nearby.helper_profiles (user_id) on delete cascade,
  device_id uuid not null,                        -- App 端為每次安裝產生，非硬體識別碼
  platform text not null check (platform in ('android', 'ios')),
  token text not null check (char_length(token) between 20 and 4096),
  registered_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  primary key (user_id, device_id)
);

create table safe_walk_nearby.push_outbox (
  id uuid primary key default gen_random_uuid(),
  delivery_alert_id uuid not null,
  recipient_id uuid not null,
  state text not null default 'pending'
    check (state in ('pending', 'sent', 'failed', 'skipped')),
  attempts integer not null default 0,
  next_attempt_at timestamptz not null default now(),
  last_error_code text,                           -- 只存錯誤代碼，不存座標或 token
  created_at timestamptz not null default now(),
  foreign key (delivery_alert_id, recipient_id)
    references safe_walk_nearby.alert_deliveries (alert_id, recipient_id) on delete cascade
);

-- 只有 D3 選 B 才需要：
create table safe_walk_nearby.helper_areas (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references safe_walk_nearby.helper_profiles (user_id) on delete cascade,
  center extensions.geography (point, 4326) not null,   -- 已四捨五入至約 100 公尺網格
  radius_m integer not null check (radius_m between 500 and 2000),
  created_at timestamptz not null default now()
);
-- 每位使用者最多 3 個守護區；與裝置數上限（例如 5）由函式檢查。
```

所有資料表照舊啟用 RLS、不建立 policy、不授權給 `anon`／`authenticated`。新增的 RPC 一樣只由 `authenticated` 執行，身分一律 `auth.uid()`：

| RPC | 行為 |
|---|---|
| `nearby_push_register(device_id, platform, token)` | 為本人註冊或更新一個裝置；超過裝置數上限被拒絕；token 絕不回傳給任何客戶端 |
| `nearby_push_unregister(device_id)` | 刪除本人該裝置的 token |
| `nearby_helper_set_areas(areas)` | （D3＝B）取代本人的守護區；伺服器端再次四捨五入並限制數量 |

`nearby_helper_opt_out()` 要一併刪除本人所有 token 與守護區；帳號刪除以外鍵級聯清除。

### 推播內容（D4）

- 標題與內文是固定通用文字，例如「附近有人求助」「請開啟 App 查看，並先確認自身安全」。
- **不放**座標、時間、求助者資訊、alert 內容；最多帶一個不可預測的 alert ID，讓 App 知道要輪詢。
- 不承諾有人會來，不說已報警、已查證。
- 鎖定畫面可見，所以通用文字同時也避免洩漏。

## 6. 隱私與安全要求

- token 與守護區屬敏感資料：只存伺服器端、不寫日誌、不出現在回應、不進版控與 CI 日誌。
- FCM 服務帳號金鑰只放在 Edge Function secrets；不放 App、不放 repo、不放 CI。
- 推播另外同意：成為協助者與「用推播通知我」是兩項獨立同意，可分別撤銷。撤銷即刪 token。
- 防濫用：沿用 SOS 的發送限流與 50 人上限，另加**每位收件人每小時最多 3 則推播**（合併同一時段的多則）。
- token 衛生：FCM 回報失效即刪；超過 60 天沒有 `last_seen_at` 的裝置清除；outbox 24 小時後清除。
- 不能保證送達：Android 省電模式、iOS 節流與使用者關閉通知都會讓推播延遲或不到。UI 文案不承諾送達，且提醒使用者同時撥打 110／119。
- 推播只是「叫醒」；是否顯示求助仍以伺服器端有效且寄給本人的 alert 為準。

## 7. 變更面與審查層級

| 範圍 | 內容 | 層級 |
|---|---|---|
| `pubspec.yaml`／lock | `firebase_core`、`firebase_messaging` | B |
| Android 原生 | Google Services Gradle plugin、Firebase 設定、`POST_NOTIFICATIONS`、通知 channel | B |
| iOS 原生 | Push Notifications capability、`aps-environment` entitlement、`UIBackgroundModes: remote-notification`、Firebase 設定、AppDelegate | B（簽章部分另需 D2） |
| CI | 以 secrets 在建置時產生 Firebase 設定檔，不提交；保持 Windows 不宣稱 iOS 建置 | B |
| TownPass 路由 | 點擊推播要在 App 任何位置導向安心行（目前的輪詢控制器只活在安心行畫面內） | B |
| SQL、Edge Function、FCM 金鑰 | 新表、RPC、發送函式 | **C** |
| 啟用、背景定位（若採 D3＝A） | 正式開關與持續位置 | **C** |

## 8. 分階段計畫與驗收

每一階段是獨立的小 PR，依賴未合併成果時使用 stacked PR，並列出 parent 與 head SHA。

### P0：決策（沒有程式）

- 取得 D1～D7 的書面決定。D3 的選擇會改變 P1、P3 的範圍。
- 對照當時的官方文件，確認 FCM HTTP v1、APNs、iOS Time Sensitive、Android 13 通知權限與 Supabase Edge Function 的現行要求。
- **退出條件**：隊長簽核；D2 決定 iOS 是否納入。

### P1：隔離後端（SQL＋Edge Function，使用假的推播閘道）

- 新增 `helper_devices`、`push_outbox`（與 D3＝B 時的 `helper_areas`）、三個 RPC，以及 outbox 寫入。
- Edge Function 以**介面注入的推播閘道**實作，測試只用假閘道，不連真的 FCM。
- 驗收：
  - SQL（需要 PostGIS 環境）：`anon` 全部拒絕；跨帳號不能讀寫他人的 token 或守護區；裝置數與守護區數上限；退出協助與帳號刪除會級聯清除；守護區四捨五入與 500 公尺邊界；收件人限流。
  - Function：成功、token 失效就刪除、暫時錯誤退避重試且有次數上限、過期 alert 跳過、同一收件人合併與限流、內容不含座標、日誌不含 token。
- 不部署。

### P2：客戶端（用假註冊器測試）

- `PushRegistrar` 介面＋假實作；`firebase_messaging` 只在實作中；Web 為 no-op。
- 另外同意推播後才要求通知權限並註冊 token；token 更新、登出、退出協助時取消註冊。
- 前景訊息觸發既有輪詢；背景點擊進入安心行並輪詢；已過期要顯示說明。
- 驗收：Widget 與控制器測試涵蓋同意前不註冊、撤銷會取消註冊、重複 token 不重複註冊、過期 alert 的說明、不顯示過度承諾的文字。

### P3：觸及策略（依 D3）

> **進度**：D3＝B 的後端、App 與測試已在另一個 PR 以隔離方式實作（細節與已知風險見[設計提案](SAFE_WALK_NEARBY_HELPER_DESIGN.md)的「守護區」一節），**仍待隊長決定是否採用**；A、C 尚未評估。在沒有推播時，守護區只讓協助者在 30 分鐘內開啟 App 就看得到求助。

- D3＝B：守護區設定畫面與 `nearby_helper_set_areas`，`nearby_sos_send` 同時挑選守護區命中的協助者。
- D3＝A 或 C：另寫獨立的同意、電量、商店審查與隱私評估，再決定是否實作。
- 驗收：D3＝B 時的 SQL 測試（網格化、500 公尺邊界、上限）與 Widget 測試。

### P4：真實端對端（需要真實資源）

- 需要：隔離的 Firebase 專案、隔離的 Supabase 專案、至少兩支測試裝置（先 Android；iOS 待 D2）、測試身分。
- 驗證：App 關閉時收到通知；點擊後看到橫幅；撤銷後不再收到；token 失效被清除；限流有效。
- 記錄裝置、系統版本、建置 SHA 與日期；不使用真實求助，也不通知陌生人。

### P5：審查與啟用

- 安全與隱私審查、Level C 授權；只有 P4 證據齊全才更新 Readiness。在此之前維持 BLOCKED。

## 9. 風險與替代方案

| 風險 | 說明 | 緩解 |
|---|---|---|
| iOS 無法測試 | 需要付費帳號、簽章與 Mac 建置 | D2 先 Android；iOS 在 CI 保持未簽章，不宣稱支援 |
| 誤報與騷擾 | 推播放大每一次濫用 | 限流、人數上限、收件人每小時上限、通用文字、可撤銷 |
| 觸及範圍被誤解 | 守護區只涵蓋固定地點 | 文案明講「只在你設定的區域附近通知」，不暗示隨時隨地 |
| 延遲或不送達 | 平台省電與節流 | 不承諾送達；提醒同時撥打 110／119 |
| 個資 | token 與守護區是個資 | 最小保存、短保留、可刪除、不寫日誌；上線前走隱私審查 |
| 成本與維運 | Firebase、Supabase Edge Function 用量 | P4 前估算；設用量上限與告警 |

**替代方案**：若團隊決定不做推播（D1＝D），維持現在的前景 App 內通知，並在加入卡片與求助頁明確寫出「請保持 App 開啟」；這已經是目前實作的行為與文案。

## 10. 待決事項彙總

| 問題 | 需要誰決定 |
|---|---|
| D1～D7（見第 3 節） | 隊長、M1 小魚、M3 莅紋 |
| 是否有 Apple Developer 帳號與 APNs 金鑰；誰負責簽章 | 隊長 |
| 誰擁有並保管 Firebase 專案與服務帳號金鑰 | 隊長、M1 小魚 |
| 守護區的半徑、數量與網格大小 | 隊長、M3 莅紋 |
| 推播文案與是否加入聲音或震動 | M3 莅紋 |
| 個資保存期限與隱私聲明文字 | 隊長 |

## 11. 不在範圍內

- 簡訊或電話備援。
- 官方警消通報或派遣。
- 預設啟用背景持續定位。
- 解除任何既有的 BLOCKED 狀態。
