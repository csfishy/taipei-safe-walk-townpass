# 附近協助者通知：可審查的重新設計提案

狀態：**提案（DRAFT）**。後端 SQL 與客戶端 transport 已在 `supabase/nearby_helper/` 與 `lib/features/safe_walk/platform/nearby_emergency/` 以隔離方式實作並於本機測試，但**未部署、未接入 App、未在任何遠端資料庫執行**。能力 R13 維持 **BLOCKED**（見 [附近通知安全狀態](SAFE_WALK_NEARBY_SECURITY.md) 與 [Live Readiness](SAFE_WALK_LIVE_READINESS.md)）。本文件只定義「要通過 Level C 審查需要什麼」，不解除任何封鎖。

## 目標與需求來源

隊員提出的需求：

1. 持續把使用者位置存進資料庫。
2. 使用者啟動 SOS 時，找出約 500 公尺內的其他使用者，並把求助資訊送給他們。

舊實作（匿名 UUID 加公開 RPC）已因下列原因退役：呼叫者自帶 UUID 就能冒充任何人，也能讀到他人位置。因此需求必須以「有身分、有同意、有限制、可刪除」的方式重做。以下是需求 1、2 的合規對應。

| 原需求 | 本提案的做法 | 與原需求的差異 |
|---|---|---|
| 持續儲存所有使用者位置 | 只儲存**主動加入協助者**的人的**最新一筆**位置，短 TTL，不留歷史 | 不儲存一般使用者位置；不保留軌跡 |
| SOS 找 500 公尺內使用者 | 伺服器端以 PostGIS 查詢**已同意且位置未過期**的協助者 | 只通知協助者；客戶端永遠拿不到他人座標 |
| 送出求助資訊 | 協助者在 TTL 內可讀到該次求助的位置與時間；不含求助者身分 | 預設不揭露求助者身分 |

## 設計原則

- **身分由伺服器決定**：一律使用已驗證 session 的 `auth.uid()`，不接受任何客戶端傳入的使用者 ID。
- **預設拒絕**：新 schema 全部啟用 RLS、沒有任何直接資料表權限，所有存取只經受限 RPC。
- **最少資料**：每位協助者只有一列最新位置；不存歷史、不存裝置識別、不在日誌記座標。
- **客戶端不讀他人位置**：附近查詢只在伺服器內執行，RPC 回傳筆數或「寄給本人」的通知，不回傳其他人的座標或身分。
- **可撤回、可刪除**：退出協助者時立即刪除位置列；TTL 到期自動清除。
- **明確同意**：定位權限、成為協助者、位置被用於附近通知，是三項分開的同意，各自可撤回。
- **不冒充官方**：SOS 附近通知不是報案；`officialReceipt` 維持 `null`；UI 同時提供 110／119 系統撥號入口。

## 資料模型（草案）

新 schema `safe_walk_nearby`，與 `crime_reference`、`safe_walk_demo` 分開，不由 CI、build 或 Demo reset 觸碰。以下為提案草稿，**不放入 `supabase/` 以免被誤執行**。

```sql
-- DRAFT ONLY. Not deployed. Not for execution.
create table safe_walk_nearby.helper_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  consent_version text not null,
  consented_at timestamptz not null,
  revoked_at timestamptz
);

create table safe_walk_nearby.helper_locations (   -- 每位協助者最多一列
  user_id uuid primary key references safe_walk_nearby.helper_profiles(user_id)
    on delete cascade,
  geog extensions.geography(Point, 4326) not null,
  accuracy_m real check (accuracy_m is null or accuracy_m >= 0),
  reported_at timestamptz not null,
  expires_at timestamptz not null                   -- 例如 reported_at + 10 分鐘
);
create index on safe_walk_nearby.helper_locations using gist (geog);

create table safe_walk_nearby.alerts (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references auth.users(id) on delete cascade,
  client_request_id uuid not null,                  -- 冪等
  geog extensions.geography(Point, 4326) not null,
  radius_m integer not null default 500 check (radius_m = 500),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,                  -- 例如 created_at + 30 分鐘
  unique (sender_id, client_request_id)
);

create table safe_walk_nearby.alert_deliveries (
  alert_id uuid not null references safe_walk_nearby.alerts(id) on delete cascade,
  recipient_id uuid not null references safe_walk_nearby.helper_profiles(user_id)
    on delete cascade,
  delivered_at timestamptz not null default now(),
  seen_at timestamptz,
  primary key (alert_id, recipient_id)
);

alter table safe_walk_nearby.helper_profiles  enable row level security;
alter table safe_walk_nearby.helper_locations enable row level security;
alter table safe_walk_nearby.alerts           enable row level security;
alter table safe_walk_nearby.alert_deliveries enable row level security;
-- 不建立任何 policy、不授予 anon／authenticated 直接資料表權限。
```

### RPC（草案）

所有函式為 `SECURITY DEFINER`，固定 `search_path`，內部以 `auth.uid()` 判斷身分，`anon` 不可執行。

| RPC | 行為 |
|---|---|
| `helper_opt_in(consent_version)` | 為本人建立協助者資料並記錄同意版本與時間 |
| `helper_opt_out()` | 標記撤回並**立即刪除**本人位置列 |
| `helper_report_location(lat, lng, accuracy_m)` | 僅限已同意者；驗證座標範圍與精度（精度可省略，超過 500 公尺會被拒絕）；時間一律用伺服器時間；每位協助者最小更新間隔 10 秒；覆寫本人唯一一列並設定 `expires_at` |
| `sos_send(lat, lng, accuracy_m, client_request_id)` | 驗證登入與限流；以 `client_request_id` 冪等；建立 alert；用 `ST_DWithin(…, 500)` 找出**未過期、已同意、非本人**的協助者並依距離取上限人數（例如 50）；寫入 deliveries；**只回傳收件人數**，不回傳任何身分或座標 |
| `helper_fetch_alerts()` | 只回傳寄給本人、未過期的 alert（求助位置、時間、剩餘有效期）；不含求助者身分。結果可重複，由客戶端以 `alert_id` 去重，避免 App 當機而遺失 SOS；首次讀取記錄 `seen_at` |

### 保留與清除

- `helper_locations`：TTL 約 10 分鐘（可調），過期列由排程每分鐘清除，並在查詢條件中同時排除過期列。
- `alerts`、`alert_deliveries`：TTL 到期後刪除；稽核紀錄只留不含座標的事件（時間、筆數、結果）。
- 帳號刪除時以外鍵 `on delete cascade` 清除。
- 日誌、錯誤回報與分析不得包含座標。

## 濫用與安全防護

- 發送限流：每位求助者短時間內次數上限，並有冷卻時間；超出回明確失敗，不靜默丟棄。
- 冪等與重送：同一 `client_request_id` 不重複通知。
- 協助者上限與距離排序：單次最多通知固定人數，避免大量廣播。
- 防止窺探位置：不提供「附近有幾位協助者」等可用來逐步定位他人的查詢；`sos_send` 的回傳人數只在實際送出後回報。
- 偽造位置：伺服器驗證精度、時間與合理移動；無法完全防止，審查時須記錄此限制。
- 檢舉與封鎖：協助者可標記濫用，並可暫停接收。
- 求助者身分預設不對協助者揭露；是否提供聯絡方式為另案決策。

## 客戶端變更範圍

- 以經驗證 session 的 `AuthenticatedNearbyAlertTransport` 取代已退役的 `SupabaseNearbyAlertTransport`，**不新增 client boolean 來解鎖舊 RPC**。
- 位置只在使用者明確操作（SOS）或協助者**前景**共享期間更新；背景定位需要額外 OS 權限與另案審查，不納入第一階段。
- 保留現有規則：SOS 先中斷語音與導航；mock 模式不讀位置、不連後端；取消後忽略遲到結果。
- M3 負責同意畫面（定位、成為協助者、位置用於附近通知三項分開）與撤回入口，並在同一畫面提供 110／119 系統撥號入口，文案不稱已通知警方或已有人趕到。

## 通知方式：App 內通知（目前實作）

求助**不是用簡訊**傳給附近的人，而是由對方的 App 在**開啟期間**收到並顯示：

- 協助者在首頁「附近協助者」卡片看完同意說明後加入。App 開啟期間每 4 分鐘左右更新一次位置（伺服器只保留最新一筆，10 分鐘 TTL），並每 10 秒查詢一次寄給自己的求助。
- 收到求助時，在目前畫面上方顯示橫幅（位置、時間、「未經查證」提醒、知道了／110／119），同一則只顯示一次。
- App 進入背景即停止查詢與更新位置；回到前景會更新位置並恢復。離開安心行或關閉 App 後，位置最多 10 分鐘內自動刪除。
- **沒有推播**：專案目前沒有 FCM／APNs，所以 App 關閉或在背景時**收不到通知**。要做到這點需要推播基礎建設與其同意流程，屬另案決策（見下表「通知管道」）；實施計畫見[附近求助推播通知：實施計畫](SAFE_WALK_NEARBY_PUSH_PLAN.md)。
- 官方的本機通知（`NotificationService`）尚未接入；它同樣只能在 App 還在執行時顯示。

SOS 求助者的按鈕是另一端：確認後送出位置，只回報後端通知的人數；原有的簡訊報警卡片是獨立功能，不受影響。

## 守護區（觸及策略 B，已隔離實作，待隊長決定是否採用）

單靠即時位置時，App 一關閉、位置過期，協助者就不會被選為收件人。守護區讓協助者**主動指定**願意被通知的地點，不必持續上傳即時位置：

- 每位協助者最多 **3 個**圓形守護區，半徑只能是 500 或 1000 公尺（上限 1 公里；原本曾考慮 2 公里，為降低被濫用的風險而縮小）。中心由**伺服器**四捨五入到約 100 公尺（小數第 3 位），不論客戶端送什麼。
- 設定時（加入後，在首頁卡片）要另外確認；App 以「目前位置」建立，確認前不讀位置。停止協助、退出與帳號刪除會一併刪除守護區。
- SOS 的收件人是兩種人的聯集，**每人只通知一次**，上限 50 人仍適用：(1) 有效的即時位置在 500 公尺內；(2) 某個守護區涵蓋 SOS 位置（SOS 到區域中心的距離不超過該區半徑）。求助者看到的說明因此改為「500 公尺內的人，以及設了守護區、範圍涵蓋這裡的人」。
- 沒有推播時的實際效果：收件資料保留 30 分鐘（alert TTL），協助者在這段時間內開啟 App 就會看到橫幅；**不會主動提醒**。這已寫進守護區卡片的說明。
- RPC：`nearby_helper_set_areas(p_areas jsonb)`（取代全部，需為有效協助者，兩次設定至少相隔 10 秒）、`nearby_helper_get_areas()`（只回傳本人的區域）。

### 已知風險：伺服器無法驗證守護區中心

客戶端可以送出**任何**座標。惡意帳號可以成為協助者、把守護區放在自己根本不在的地方，藉此收到那一帶所有 SOS 的精確位置。即時位置有同樣的偽造空間，但守護區讓它不必每 10 分鐘維持一次，也能涵蓋到最遠 1 公里。現有緩解只能降低、不能消除：每人最多 3 區、半徑上限 1 公里、設定限流、SOS 本身限流與 50 人上限、求助者身分不會揭露。真正的緩解需要 D7（可信身分）與協助者資格審核，並且要決定是否要求守護區中心先有近期的實際位置紀錄。半徑上限已降到 1 公里。**在這之前建議維持 BLOCKED。**

## 身分：每支手機一個匿名帳號（已隔離實作，待隊長決定是否採用）

附近通知的後端靠 `auth.uid()` 判斷「誰是誰、資料歸誰」，所以每個使用者都需要伺服器核發的身分。目前實作的是 **Supabase 匿名登入**（`SupabaseAnonymousNearbySession`，官方入口已接上）：

- **何時建立**：不在 App 啟動時。只有在使用者第一次**加入協助者**或**送出 SOS**時才建立一個匿名使用者（沒有姓名、電話或信箱）；沒用過這個功能的人不會有帳號。同意文字與 SOS 確認畫面都會說明「會用匿名帳號代表這支手機」。
- **怎麼保存**：只把 refresh token 存在 App 偏好設定，access token 只在記憶體。重新啟動後用它換新 session，不會重建帳號。**這不是安全儲存**（專案沒有 `flutter_secure_storage`，加入依賴屬 Level B）：作業系統備份或已 root 的裝置可能取得它，取得者就能以這支手機的身分行動。移到安全儲存是記錄在案的後續工作。
- **網路抖動不會丟掉身分**：refresh 失敗只在伺服器明確拒絕時才重建；逾時、5xx 一律保留原身分並稍後重試。伺服器拒絕（例如專案沒開匿名登入）後 5 分鐘內不再重試，介面顯示「目前無法使用」。
- **讀位置之前先確認身分就緒**：服務會先等身分建立完成，失敗就直接拒絕，不白讀一次位置。
- **重新安裝＝新帳號**：舊帳號的協助者資料與守護區留在伺服器，沒有人再能讀它。**孤兒守護區仍會被 SOS 選為收件人**（佔用 50 人上限、白白產生投遞資料）。建議後續為 `helper_profiles` 加 `last_seen_at`，並讓 `purge_expired()` 清除 30 天沒有活動的協助者（含其守護區與裝置）；這個 SQL 變更尚未做。

### 它解決什麼、不解決什麼

| 解決 | **不**解決 |
|---|---|
| 每份資料有伺服器驗證的擁有者，RLS 與 `auth.uid()` 規則才成立；客戶端不能冒用別人的 ID | **資格**：任何人都能自動取得身分，再成為協助者去收 SOS 位置 |
| 同一個身分的限流與冪等有意義 | 單一帳號的限流可以用重新安裝或重複建帳號繞過 |
| 不需要任何個人資料就能運作 | 無法證明是同一個真人，也無法封鎖惡意者（封鎖只能針對那一個匿名帳號） |

因此**附近通知仍然是 BLOCKED**：匿名身分只是補上「可信身分」的一半，缺少「接收資格」與抗濫用。真正的緩解需要資格審核、CAPTCHA 或裝置驗證（Play Integrity／App Attest）、以及帳號建立速率限制，這些都還沒做。

### 部署前必須的手動設定（Level C）

1. 在 Supabase 專案的 Auth 設定**開啟 Anonymous sign-ins**（預設關閉）；沒開的話，App 會一律顯示「目前無法使用」。
2. 檢視匿名登入的速率限制，評估是否啟用 CAPTCHA（我對 Supabase 現行限制的理解需對照官方文件確認）。
3. 部署 RPC 後端：先在 PostGIS 上跑完本機 SQL 測試；目標專案的 PostGIS 在 `public` 且資料表已存在，所以**不能直接套用** `001_nearby_helper.sql`，要依 `supabase/nearby_helper/README.md` 走審查過的前向 migration。
4. 這會在 `auth.users` 為每位使用者建立列；請確認隊長同意在這個專案（與犯罪參考資料同一個專案）建立匿名使用者，或改用隔離的專案。

這是 D7 的「Supabase 匿名」選項。TownPass 官方登入的橋接沒有評估，且需要市府配合，所以不在此實作。

## 緊急聯絡人（App 內通知，已隔離實作）

**這不是簡訊。** 聯絡人透過「邀請碼配對」成為你的緊急聯絡人，你按 SOS 時，他們在**自己的 App 內**收到通知。簡訊直接送到手機號碼，不需要對方有帳號；App 內通知需要對方有身分，所以必須先配對。

### 怎麼運作

- **配對**：你輸入一個名字（1 到 20 字，之後聯絡人會看到它）並產生一組邀請碼。邀請碼是 8 個字元，取自 31 個不易混淆的字元（沒有 I、L、O、0、1），**24 小時內有效、只能用一次**，資料庫只存它的 SHA-256 雜湊，同時最多 3 組未使用。你用自己信任的方式交給對方（不經過簡訊，也不經過本 App），對方在自己的臺北安心行輸入後就成為你的聯絡人。
- **數量**：每人最多 5 位聯絡人；一個人最多可以當 20 個人的聯絡人。
- **SOS**：你送出 SOS 時，聯絡人**不論距離**都會收到，看到**精確的 SOS 位置**和**你設定的名字**。附近協助者仍然**不會知道是誰發的**。SOS 回傳給你的人數現在**包含聯絡人**，所以結果文字是「已通知 N 位」，不再只寫附近協助者。
- **聯絡人不需要成為協助者**：不需要協助者資料、不分享任何位置。
- **你看不到聯絡人是誰**：你只看得到連結編號與加入日期；聯絡人只看到你設定的名字。任何一方都能**立刻**結束連結（你移除，或對方「不再接收」）。
- **傳遞方式**：聯絡人與協助者共用同一個前景輪詢，**沒有推播，App 關閉時什麼都收不到**。App 啟動時只會還原「這支手機本來就有的身分」，用來重新讀取聯絡人並恢復接收；**從不在此時建立新身分**，沒用過這個功能的人不會有帳號。

### RPC

`nearby_contact_invite_create`、`nearby_contact_invite_accept`、`nearby_contact_list_mine`、`nearby_contact_remove`、`nearby_contact_following`、`nearby_contact_unfollow`。`nearby_helper_fetch_alerts` 現在多回傳 `from_contact` 與 `sender_name`，**也服務聯絡人**（不是協助者、但有人把他設為聯絡人，也可以讀自己的求助）；一般協助者收到的 `from_contact` 為 false、`sender_name` 為空。

### 為什麼 `accept` 回傳狀態字串，而不是丟錯誤

猜邀請碼必須被限流，但函式一丟例外，整個交易就回滾，**失敗次數的紀錄也跟著消失**，限流等於沒有。所以 `nearby_contact_invite_accept` 在邀請碼錯誤、過期、已使用、自己的碼、對方已滿或自己已達上限時，都**正常回傳** `invalid`／`self`／`owner_full`／`following_full`（成功回傳 `ok`），讓每次嘗試都留在 `contact_invite_attempts`；只有每人每小時超過 10 次才丟 `PT429`。格式明顯不合的碼，App 在本機就擋下，不送出、不佔用嘗試次數。

### 已知風險與限制

- **邀請碼經過的管道不在 App 控制之內。** 24 小時內任何拿到碼的人都能成為你的聯絡人，之後會看到你每次 SOS 的精確位置與你設定的名字。
- **猜不到，但交出去就收不回。** 31 個字元、8 位共約 8.5×10¹¹ 種組合，加上每人每小時 10 次嘗試與 24 小時有效，猜中的機率可以忽略；但匿名身分免費，攻擊者能取得無限個身分，所以真正的防線只是**不要把碼交給不該拿到的人**。
- **你看不到聯絡人是誰**，因此無法分辨碼是否被攔截，**唯一的線索是聯絡人數量是否異常增加**。沒有任何機制驗證對方就是你想邀請的那個人。
- **沒有推播**：聯絡人只有在 App 開啟時才收得到，不能保證他及時看到。
- **名字以明文顯示**給聯絡人，請不要用會洩漏過多個資的名字。
- 這是**配對**，不是資格審核；整個附近通知仍是 BLOCKED，啟用屬 Level C。

### Schema 變更與部署

為了讓聯絡人（不一定是協助者）能收到投遞，`alert_deliveries.recipient_id` 現在參照 `auth.users`（原本是 `helper_profiles`），並新增三張資料表（`contact_invites`、`trusted_contacts`、`contact_invite_attempts`），`nearby_helper_fetch_alerts` 的回傳欄位也變了。**已經在遠端套用的資料表需要一份經過審查的前向 migration**；`001_nearby_helper.sql` 只是全新安裝版本。這份 SQL（**包含新增的測試**）**仍從未在 PostGIS 上執行過**，部署前必須先跑完 `supabase/nearby_helper/README.md` 的本機測試。

## 驗收條件

**後端**
- `anon` 呼叫所有 RPC 皆被拒絕。
- 帳號 A 無法讀取、修改或確認帳號 B 的位置、alert 或投遞列（跨帳號拒絕測試）。
- 未同意、已撤回、位置過期的協助者不會被選為收件人。
- `helper_opt_out` 後位置列立即消失。
- 500 公尺邊界：約 499 公尺的協助者收到，約 501 公尺的不收到；求助者本人不會收到自己的 alert。
- 限流、冪等、人數上限皆有測試；併發送出不重複投遞。
- 回應與日誌中沒有他人座標或身分。
- TTL 清除與帳號刪除級聯刪除有測試。

**客戶端**
- 三項同意分開；撤回後取消進行中的請求並忽略遲到結果。
- SOS 路徑在後端不可用時顯示 Unavailable 與原因，不假稱已通知。
- 取消、離開頁面、進背景不產生後續副作用。

**實機與審查**
- 兩支裝置、使用測試身分的端對端驗證，記錄部署版本、裝置與結果；不使用真實危難，也不通知陌生人。
- 通過安全與隱私審查，並取得隊長對 Level C 的明確授權後，才可啟用。

## 實施順序

1. 本提案審查（本 PR），決定下列待決事項。
2. 在**隔離的新專案或隔離 schema** 建立後端與測試；不對現有 Supabase 主庫、`crime_reference` 或 `safe_walk_demo` 執行。
3. 客戶端 transport 與同意畫面，以 fake 後端先完成取消與生命週期測試。
4. 安全審查與跨帳號、濫用測試。
5. Level C 授權後，小範圍測試身分實機驗證。
6. 最後才評估是否更新 Readiness；在證據齊全前維持 BLOCKED。

## 待決事項

| 問題 | 需要誰決定 |
|---|---|
| 使用者身分來源：TownPass 登入、Supabase Auth，或兩者之間的橋接方式 | M1 小魚、隊長 |
| 協助者資格：是否限制在經過驗證的帳號，或需要額外的資格審核 | 隊長 |
| 通知管道：目前為「App 開啟期間的 App 內輪詢＋橫幅」；是否加推播（FCM／APNs）以涵蓋背景與關閉狀態，及其同意與成本 | M1 小魚、隊長 |
| 協助者看到的位置精度：精確座標或模糊化區域 | 隊長、M3 莅紋 |
| 位置更新頻率與 TTL：是否允許背景定位及其 OS 權限審查 | 隊長、M1 小魚 |
| 後端落點：新的隔離專案或現有專案的新 schema | 隊長 |
| 位置與 alert 的保留期限及法規／隱私條款文字 | 隊長 |

## 不在範圍內

- 持續保存所有使用者的位置歷史或軌跡。
- 通知未加入協助者的使用者。
- 官方警消案件自動派遣（R14，無授權，維持 BLOCKED）。
- 取消 `officialReceipt` 為 `null` 的限制。
- 解除任何既有的 BLOCKED 狀態。
