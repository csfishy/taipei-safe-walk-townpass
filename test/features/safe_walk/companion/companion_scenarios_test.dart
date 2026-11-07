import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/safe_walk_contracts.dart';

const _scenarioFile =
    'test/features/safe_walk/companion/fixtures/companion_scenarios.json';

/// Phrases that would claim police, rescue, location tracking, a contacted
/// person, or a live listener (AGENTS.md M5: no fake live person; the
/// controller never uses a microphone, so nothing "hears" the user).
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
}
