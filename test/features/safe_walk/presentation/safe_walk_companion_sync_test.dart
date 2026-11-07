// M3 畫面用的陪伴劇本必須與 M5 的劇本檔一致；M5 改了劇本卻沒同步時這裡會失敗。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/presentation/mock/companion_dialogues.dart';
import 'package:town_pass/features/safe_walk/presentation/mock/companion_scenarios.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart' as sw;

void main() {
  test('m5CompanionScenarios 與 M5 companion_scenarios.json 相同', () {
    final raw = jsonDecode(File('test/features/safe_walk/companion/fixtures/companion_scenarios.json').readAsStringSync()) as List<Object?>;
    final m5 = raw.map(sw.CompanionScenario.fromJson).toList();
    expect(m5CompanionScenarios.map((s) => s.toJson()).toList(), m5.map((s) => s.toJson()).toList());
  });

  test('每個劇本的每一句都有回覆可選', () {
    for (final c in m5CompanionScenarios) {
      final replies = companionReplies[c.id];
      expect(replies, isNotNull, reason: c.id);
      expect(replies!.length, c.steps.length, reason: c.id);
      for (final r in replies) {
        expect(r, isNotEmpty, reason: c.id);
      }
    }
  });

  test('回覆與完整句子不含會讓旁人起疑或刺激對方的字眼', () {
    const banned = ['不對勁', '跟著我', '跟蹤', '可疑', '報警', '求救', '危險'];
    final all = [
      for (final rs in companionReplies.values)
        for (final r in rs) ...r,
      ...callTemplates,
    ];
    for (final text in all) {
      for (final w in banned) {
        expect(text.contains(w), isFalse, reason: '「$text」含有「$w」');
      }
    }
  });

  test('每個完整句子都有對方的回應，且不假裝真人在線', () {
    const forbidden = ['陪你', '我在', '在線上', '在聽', '聽到', '看到你', '定位', '已通知', '報警'];
    for (final t in callTemplates) {
      final ack = callTemplateAcks[t];
      expect(ack, isNotNull, reason: t);
      for (final w in forbidden) {
        expect(ack!.contains(w), isFalse, reason: '「$ack」含有「$w」');
      }
    }
  });
}
