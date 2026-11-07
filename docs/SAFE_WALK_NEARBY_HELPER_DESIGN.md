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

- 每位協助者最多 **3 個**圓形守護區，半徑只能是 500、1000 或 2000 公尺。中心由**伺服器**四捨五入到約 100 公尺（小數第 3 位），不論客戶端送什麼。
- 設定時（加入後，在首頁卡片）要另外確認；App 以「目前位置」建立，確認前不讀位置。停止協助、退出與帳號刪除會一併刪除守護區。
- SOS 的收件人是兩種人的聯集，**每人只通知一次**，上限 50 人仍適用：(1) 有效的即時位置在 500 公尺內；(2) 某個守護區涵蓋 SOS 位置（SOS 到區域中心的距離不超過該區半徑）。求助者看到的說明因此改為「500 公尺內的人，以及設了守護區、範圍涵蓋這裡的人」。
- 沒有推播時的實際效果：收件資料保留 30 分鐘（alert TTL），協助者在這段時間內開啟 App 就會看到橫幅；**不會主動提醒**。這已寫進守護區卡片的說明。
- RPC：`nearby_helper_set_areas(p_areas jsonb)`（取代全部，需為有效協助者，兩次設定至少相隔 10 秒）、`nearby_helper_get_areas()`（只回傳本人的區域）。

### 已知風險：伺服器無法驗證守護區中心

客戶端可以送出**任何**座標。惡意帳號可以成為協助者、把守護區放在自己根本不在的地方，藉此收到那一帶所有 SOS 的精確位置。即時位置有同樣的偽造空間，但守護區讓它不必每 10 分鐘維持一次，也能涵蓋到最遠 2 公里。現有緩解只能降低、不能消除：每人最多 3 區、半徑上限 2 公里、設定限流、SOS 本身限流與 50 人上限、求助者身分不會揭露。真正的緩解需要 D7（可信身分）與協助者資格審核，並且要決定是否把半徑上限降到 1000 公尺或要求先有近期的實際位置紀錄。**在這之前建議維持 BLOCKED。**

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
