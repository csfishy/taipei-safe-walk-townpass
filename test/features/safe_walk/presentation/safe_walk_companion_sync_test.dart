// M3 畫面用的陪伴劇本必須與 M5 的劇本檔一致；M5 改了劇本卻沒同步時這裡會失敗。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/presentation/mock/companion_scenarios.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart' as sw;

void main() {
  test('m5CompanionScenarios 與 M5 companion_scenarios.json 相同', () {
    final raw = jsonDecode(File('test/features/safe_walk/companion/fixtures/companion_scenarios.json').readAsStringSync()) as List<Object?>;
    final m5 = raw.map(sw.CompanionScenario.fromJson).toList();
    expect(m5CompanionScenarios.map((s) => s.toJson()).toList(), m5.map((s) => s.toJson()).toList());
  });
}
