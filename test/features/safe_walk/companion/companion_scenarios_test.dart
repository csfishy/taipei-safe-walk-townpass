import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/safe_walk_contracts.dart';

const _scenarioFile =
    'test/features/safe_walk/companion/fixtures/companion_scenarios.json';

/// Phrases that would claim police, rescue, location tracking, a contacted
/// person, or a live listener (AGENTS.md M5: no fake live person; the
/// controller never uses a microphone, so nothing "hears" the user).
///
/// This list only blocks known wording; it cannot prove every line is safe.
/// The UI must still show 「模擬通話，未聯絡任何人」 before and during playback.
const _forbiddenPhrases = <String>[
  '警察',
  '報警',
  '救援',
  '定位',
  '看得到你',
  '已經通知',
  '已通知',
  '在線上',
  '不掛電話',
  '陪你',
  '我在',
  '在聽',
  '聽到',
  '聽得到',
  '看到你',
  '看見你',
  '知道你在哪',
  '收到訊息',
  '收到位置',
  '已聯絡',
  '通知家人',
  '保持通話',
  '通話中',
  '正在連線',
];

List<Object?> _loadScenarios() =>
    jsonDecode(File(_scenarioFile).readAsStringSync()) as List<Object?>;

void main() {
  final scenarios = _loadScenarios();

  test('scenario set is non-empty and ids are unique', () {
    expect(scenarios, isNotEmpty);
    final ids = scenarios.map((s) => (s! as Map)['id']).toList();
    expect(ids.toSet().length, ids.length);
  });

  for (final raw in scenarios) {
    final id = (raw! as Map)['id'];

    test('$id satisfies the shared CompanionScenario schema', () {
      expect(validateContract('CompanionScenario', raw), isEmpty);
      final scenario = SafeWalkContracts.companionScenario.parse(raw);
      expect(scenario.steps, isNotEmpty);
    });

    test('$id stays a text preview until owned recordings are registered', () {
      final steps = ((raw as Map)['steps'] as List).cast<Map>();
      expect(steps.every((step) => step['audioSrc'] == null), isTrue);
    });

    test(
      '$id never claims police, rescue, tracking, a contacted person or a live listener',
      () {
        final steps = ((raw as Map)['steps'] as List).cast<Map>();
        for (final step in steps) {
          final text = step['text'] as String;
          for (final phrase in _forbiddenPhrases) {
            expect(
              text.contains(phrase),
              isFalse,
              reason: '"$text" contains "$phrase"',
            );
          }
        }
      },
    );
  }

  test('the submission contains one three-line deterrence scenario', () {
    expect(scenarios, hasLength(1));
    final scenario = scenarios.single! as Map;
    expect(scenario['id'], 'stalker-deterrence');
    expect((scenario['steps'] as List), hasLength(3));
  });
}
