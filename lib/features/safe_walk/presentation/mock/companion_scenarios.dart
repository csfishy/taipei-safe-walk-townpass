// 由 M5 的 test/features/safe_walk/companion/fixtures/companion_scenarios.json 產生（PR #13）。
// M5 改劇本時請同步更新；safe_walk_companion_sync_test.dart 會比對兩邊是否一致。
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart' as sw;

/// M5 陪伴劇本：對方一句一句說，每句之後停 pauseAfterMs；沒有錄音（audioSrc 為 null）。
final List<sw.CompanionScenario> m5CompanionScenarios = [
  sw.CompanionScenario(
    id: 'walk-home-night',
    label: '晚上走路回家',
    steps: [
      sw.CompanionStep(id: 'line-1', text: '喂，你到哪了？', audioSrc: null, pauseAfterMs: 3000),
      sw.CompanionStep(id: 'line-2', text: '嗯嗯，那你繼續走。', audioSrc: null, pauseAfterMs: 2500),
      sw.CompanionStep(id: 'line-3', text: '旁邊亮不亮？往人多、有燈的那邊走。', audioSrc: null, pauseAfterMs: 3500),
      sw.CompanionStep(id: 'line-4', text: '不用急，慢慢走。', audioSrc: null, pauseAfterMs: 3000),
      sw.CompanionStep(id: 'line-5', text: '快到家了嗎？進門前先看一下四周。', audioSrc: null, pauseAfterMs: 3000),
      sw.CompanionStep(id: 'line-6', text: '要是真的覺得不對勁，馬上用求助，別管這通電話。', audioSrc: null, pauseAfterMs: 2000),
    ],
  ),
  sw.CompanionScenario(
    id: 'scenario-rideshare',
    label: '叫車回家',
    steps: [
      sw.CompanionStep(id: 'line-1', text: '喂，你上車了嗎？', audioSrc: null, pauseAfterMs: 3000),
      sw.CompanionStep(id: 'line-2', text: '好好好，那你大概幾點到？', audioSrc: null, pauseAfterMs: 3000),
      sw.CompanionStep(id: 'line-3', text: '你走哪條路？', audioSrc: null, pauseAfterMs: 3000),
      sw.CompanionStep(id: 'line-4', text: '好，到了先確認下車地點和四周。', audioSrc: null, pauseAfterMs: 2500),
      sw.CompanionStep(id: 'line-5', text: '不用說話也沒關係。', audioSrc: null, pauseAfterMs: 4000),
      sw.CompanionStep(id: 'line-6', text: '快到了，先留意車外環境和下車位置。', audioSrc: null, pauseAfterMs: 2500),
    ],
  ),
  sw.CompanionScenario(
    id: 'late-night-transit-wait',
    label: '深夜公車站或捷運出口等車',
    steps: [
      sw.CompanionStep(id: 'line-1', text: '喂？你在哪個站等車？', audioSrc: null, pauseAfterMs: 3500),
      sw.CompanionStep(id: 'line-2', text: '嗯，你旁邊有人嗎？', audioSrc: null, pauseAfterMs: 3000),
      sw.CompanionStep(id: 'line-3', text: '沒關係。車還要多久？', audioSrc: null, pauseAfterMs: 3000),
      sw.CompanionStep(id: 'line-4', text: '你站在有燈的地方嗎？亮一點比較好。', audioSrc: null, pauseAfterMs: 2500),
      sw.CompanionStep(id: 'line-5', text: '嗯嗯，不著急。', audioSrc: null, pauseAfterMs: 4000),
      sw.CompanionStep(id: 'line-6', text: '車來了就上車，路上小心。', audioSrc: null, pauseAfterMs: 2500),
    ],
  ),
  sw.CompanionScenario(
    id: 'cannot-move-safely',
    label: '沒辦法安全移動時',
    steps: [
      sw.CompanionStep(id: 'line-1', text: '喂，先不要急著走。', audioSrc: null, pauseAfterMs: 2500),
      sw.CompanionStep(id: 'line-2', text: '走不了的話，就先留在原地，不用勉強。', audioSrc: null, pauseAfterMs: 3500),
      sw.CompanionStep(id: 'line-3', text: '能的話，靠近燈下或店家門口。', audioSrc: null, pauseAfterMs: 3500),
      sw.CompanionStep(id: 'line-4', text: '如果覺得危險，馬上用求助，不用等。', audioSrc: null, pauseAfterMs: 3000),
      sw.CompanionStep(id: 'line-5', text: '不方便說話的話，求助畫面也可以用文字。', audioSrc: null, pauseAfterMs: 3000),
      sw.CompanionStep(id: 'line-6', text: '等到覺得安全了，再慢慢走。', audioSrc: null, pauseAfterMs: 2500),
    ],
  ),
  sw.CompanionScenario(
    id: 'rideshare-mismatch',
    label: '車號或司機不符時',
    steps: [
      sw.CompanionStep(id: 'line-1', text: '喂，車到了嗎？', audioSrc: null, pauseAfterMs: 2500),
      sw.CompanionStep(id: 'line-2', text: '先別急著上車，對一下車牌號碼。', audioSrc: null, pauseAfterMs: 3500),
      sw.CompanionStep(id: 'line-3', text: '司機名字和車型也看一下，跟叫車資料一樣嗎？', audioSrc: null, pauseAfterMs: 4000),
      sw.CompanionStep(id: 'line-4', text: '如果不一樣，就不要上車，先待在人多的地方。', audioSrc: null, pauseAfterMs: 3500),
      sw.CompanionStep(id: 'line-5', text: '已經在車上的話，覺得路線不對就先用求助。', audioSrc: null, pauseAfterMs: 3000),
      sw.CompanionStep(id: 'line-6', text: '確認沒問題再上車。', audioSrc: null, pauseAfterMs: 2000),
    ],
  ),
  sw.CompanionScenario(
    id: 'elder-short-walk',
    label: '長者版：走路回家（短句）',
    steps: [
      sw.CompanionStep(id: 'line-1', text: '喂，你在哪裡？', audioSrc: null, pauseAfterMs: 2500),
      sw.CompanionStep(id: 'line-2', text: '走大路，走亮的地方。', audioSrc: null, pauseAfterMs: 3000),
      sw.CompanionStep(id: 'line-3', text: '慢慢走，不要急。', audioSrc: null, pauseAfterMs: 3000),
      sw.CompanionStep(id: 'line-4', text: '累了就找店家坐一下。', audioSrc: null, pauseAfterMs: 3000),
      sw.CompanionStep(id: 'line-5', text: '怕的話，按求助。', audioSrc: null, pauseAfterMs: 2500),
      sw.CompanionStep(id: 'line-6', text: '到家記得關好門。', audioSrc: null, pauseAfterMs: 2000),
    ],
  ),
];
