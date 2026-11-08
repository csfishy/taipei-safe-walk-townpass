// 由 M5 的 test/features/safe_walk/companion/fixtures/companion_scenarios.json 產生。
// M5 改劇本時請同步更新；safe_walk_companion_sync_test.dart 會比對兩邊是否一致。
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart' as sw;

/// 單一嚇阻劇本：男性英文台詞由裝置 TTS 朗讀，女性繁中台詞顯示在螢幕上供使用者照讀。
final List<sw.CompanionScenario> m5CompanionScenarios = [
  sw.CompanionScenario(
    id: 'stalker-deterrence',
    label: '疑似遭人跟蹤',
    steps: [
      sw.CompanionStep(
        id: 'line-1',
        text:
            "Damn it, babe, where the hell are you? You should've been home by now. I'm already downstairs waiting for you.",
        audioSrc: null,
        pauseAfterMs: 1200,
      ),
      sw.CompanionStep(
        id: 'line-2',
        text:
            "What? Don't turn around. I can see your location. Keep walking toward the lights. I'm coming to get you right now.",
        audioSrc: null,
        pauseAfterMs: 1200,
      ),
      sw.CompanionStep(
        id: 'line-3',
        text:
            "I see you. Keep walking straight toward me. I'm right here, and I'm watching everything around you.",
        audioSrc: null,
        pauseAfterMs: 0,
      ),
    ],
  ),
];
