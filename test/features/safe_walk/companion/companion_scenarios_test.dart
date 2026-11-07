import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/safe_walk_contracts.dart';

const _scenarioFile =
    'test/features/safe_walk/companion/fixtures/companion_scenarios.json';

/// Phrases that would claim police, rescue, location tracking or a real
/// person already being contacted (AGENTS.md safety rules for M5).
const _forbiddenPhrases = <String>[
  '警察',
  '報警',
  '救援',
  '定位',
  '看得到你',
  '已經通知',
  '已通知',
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

    test('$id never claims police, rescue, tracking or a contacted person', () {
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
    });
  }
}
