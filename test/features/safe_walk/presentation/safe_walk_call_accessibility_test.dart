import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/presentation/mock/companion_scenarios.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_call_view.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_speaker.dart';

class _SpeakerSpy implements SafeWalkSpeaker {
  final spoken = <String>[];
  int stops = 0;

  @override
  bool get available => true;

  @override
  void speak(String text, {void Function()? onDone}) => spoken.add(text);

  @override
  void stop() => stops++;
}

void main() {
  testWidgets(
    'screen reader stops and replays caller speech; pointer tap fires once',
    (tester) async {
      final handle = tester.ensureSemantics();
      final speaker = _SpeakerSpy();
      final line = m5CompanionScenarios.first.steps.first.text;
      final bubble = find.bySemanticsLabel(RegExp(RegExp.escape('對方：$line')));
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      try {
        await tester.pumpWidget(
          MaterialApp(
            home: SafeWalkCallView(
              speaker: speaker,
              onEnd: () {},
              onEmergency: () {},
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('接聽'));
        await tester.pumpAndSettle();
        expect(speaker.spoken, [line]);

        var node = tester.getSemantics(bubble);
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        expect(node.getSemanticsData().hint, '點兩下停止朗讀');
        final stopsBefore = speaker.stops;
        node.owner!.performAction(node.id, SemanticsAction.tap);
        await tester.pumpAndSettle();
        expect(speaker.stops, stopsBefore + 1);
        expect(speaker.spoken, [line]);

        node = tester.getSemantics(bubble);
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        expect(node.getSemanticsData().hint, '點兩下重播');
        node.owner!.performAction(node.id, SemanticsAction.tap);
        await tester.pumpAndSettle();
        expect(speaker.spoken, [line, line]);
        expect(tester.getSemantics(bubble).getSemanticsData().hint, '點兩下停止朗讀');

        final stopsBeforePointerTap = speaker.stops;
        await tester.tap(find.text(line));
        await tester.pumpAndSettle();
        expect(speaker.stops, stopsBeforePointerTap + 1);
        expect(speaker.spoken, [line, line]);
        expect(tester.getSemantics(bubble).getSemanticsData().hint, '點兩下重播');
      } finally {
        await tester.pumpWidget(const SizedBox());
        handle.dispose();
      }
    },
  );
}
