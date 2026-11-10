// M3 畫面用的陪伴劇本必須與 M5 的劇本檔一致；M5 改了劇本卻沒同步時這裡會失敗。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/presentation/companion_dialogues.dart';
import 'package:town_pass/features/safe_walk/presentation/companion_scenarios.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart' as sw;

void main() {
  test('m5CompanionScenarios 與 M5 companion_scenarios.json 相同', () {
    final raw = jsonDecode(File('test/features/safe_walk/companion/fixtures/companion_scenarios.json').readAsStringSync()) as List<Object?>;
    final m5 = raw.map(sw.CompanionScenario.fromJson).toList();
    expect(m5CompanionScenarios.map((s) => s.toJson()).toList(), m5.map((s) => s.toJson()).toList());
  });

  test('單一劇本在每句男性台詞後（最後一句除外）各提供一段女性照讀稿', () {
    expect(m5CompanionScenarios, hasLength(1));
    for (final c in m5CompanionScenarios) {
      final replies = companionReplies[c.id];
      expect(replies, isNotNull, reason: c.id);
      expect(replies!.length, c.steps.length - 1, reason: c.id);
      for (final r in replies) {
        expect(r, hasLength(1), reason: c.id);
      }
    }
  });

  test('女性照讀稿與五段嚇阻順序固定', () {
    expect(companionReplies['stalker-deterrence'], [
      ['我快到了啦，還在路上，再幾分鐘。'],
      ['好，我走大路，不要催啦。'],
      ['我在便利商店旁邊，前面就是路口。'],
      ['好，我看到你了，我現在直接走過去。電話先不要掛。'],
    ]);
  });

  test('照讀台詞不含會讓旁人起疑的字', () {
    const suspicious = ['不對勁', '跟著我', '跟蹤', '有人', '回頭', '報警', '危險', '救命', '害怕'];
    for (final line in companionReplies.values.expand((l) => l).expand((l) => l)) {
      for (final w in suspicious) {
        expect(line.contains(w), isFalse, reason: '「$line」含「$w」');
      }
    }
  });

  test('所有男性台詞都是英文且最後一句不再要求女性回覆', () {
    final scenario = m5CompanionScenarios.single;
    expect(scenario.steps, hasLength(5));
    for (final step in scenario.steps) {
      expect(RegExp(r'[\u4e00-\u9fff]').hasMatch(step.text), isFalse);
    }
    expect(scenario.steps.last.pauseAfterMs, 0);
  });
}
