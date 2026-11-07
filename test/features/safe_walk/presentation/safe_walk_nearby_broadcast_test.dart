// 緊急求助頁的「通知附近的人」：兩段式確認、誠實的結果文字、離開頁面即取消。
// 這裡只測呈現與取消；沒有任何後端，也沒有真實位置。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_flow.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_nearby_broadcast.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';

const _forbidden = ['已報警', '已通報', '已派遣', '馬上有人', '救援已', '有人正在趕來', '警方已'];

// The card changes height between steps, so its text may sit just outside the
// built viewport; these finders still see it and _show scrolls it into view.
Finder _t(String text) => find.text(text, skipOffstage: false);
Finder _tc(String text) => find.textContaining(text, skipOffstage: false);

Future<void> _openEmergency(WidgetTester t, SafeWalkNearbyBroadcast? b) async {
  t.view.physicalSize = const Size(390 * 3, 844 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      home: SafeWalkFlow(key: UniqueKey(), nearbyBroadcast: b),
    ),
  );
  await t.pumpAndSettle();
  await t.tap(_t('緊急求助').first);
  await t.pumpAndSettle();
}

// The sending spinner never stops animating, so pumpAndSettle would time out.
Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 500));
}

Future<void> _show(WidgetTester t, Finder f) async {
  await t.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
  await _settle(t);
}

Future<void> _tap(WidgetTester t, String text) async {
  await _show(t, _t(text));
  await t.tap(_t(text));
  await _settle(t);
}

String _allText(WidgetTester t) => t
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
    .join('\n');

void _expectNoOverclaim(WidgetTester t) {
  final text = _allText(t);
  for (final phrase in _forbidden) {
    expect(text, isNot(contains(phrase)), reason: phrase);
  }
}

class _Calls {
  int count = 0;
  SafeWalkCancellation? token;
  Completer<NearbyBroadcastOutcome>? pending;
}

SafeWalkNearbyBroadcast _available(
  _Calls calls, {
  Future<NearbyBroadcastOutcome> Function(SafeWalkCancellation)? run,
}) => SafeWalkNearbyBroadcast(
  unavailableReason: null,
  onBroadcast: (cancellation) {
    calls.count++;
    calls.token = cancellation;
    if (run != null) return run(cancellation);
    return (calls.pending = Completer<NearbyBroadcastOutcome>()).future;
  },
);

void main() {
  testWidgets('without a broadcast dependency the card is not shown', (
    t,
  ) async {
    await _openEmergency(t, null);
    expect(_t('通知附近的人'), findsNothing);
    expect(_tc('通知附近的人：目前無法使用'), findsNothing);
    expect(_t('撥打 110 報警'), findsOneWidget);
  });

  testWidgets('unavailable: shows the real reason, offers no button', (
    t,
  ) async {
    final calls = _Calls();
    await _openEmergency(
      t,
      SafeWalkNearbyBroadcast(
        unavailableReason: '測試：尚未登入',
        onBroadcast: (c) async {
          calls.count++;
          return const NearbyBroadcastSent(1);
        },
      ),
    );
    await _show(t, _t('通知附近的人：目前無法使用'));
    expect(_tc('測試：尚未登入'), findsOneWidget);
    expect(_tc('請撥打 110／119'), findsWidgets);
    expect(_t('通知附近協助者'), findsNothing);
    expect(_t('確認通知'), findsNothing);
    expect(calls.count, 0);
    _expectNoOverclaim(t);
  });

  testWidgets('first tap only asks to confirm; nothing is sent', (t) async {
    final calls = _Calls();
    await _openEmergency(t, _available(calls));
    await _tap(t, '通知附近協助者');
    await _show(t, _t('確認通知'));
    expect(_tc('設了守護區'), findsWidgets);
    expect(_tc('不是報警'), findsOneWidget);
    expect(_tc('110／119'), findsWidgets);
    expect(calls.count, 0);
    await _tap(t, '取消');
    expect(_t('通知附近協助者'), findsOneWidget);
    expect(_t('確認通知'), findsNothing);
    expect(calls.count, 0);
  });

  testWidgets('confirm sends once; the count is reported without promises', (
    t,
  ) async {
    final calls = _Calls();
    await _openEmergency(t, _available(calls));
    await _tap(t, '通知附近協助者');
    await _tap(t, '確認通知');
    expect(calls.count, 1);
    expect(_t('正在取得位置並通知…'), findsOneWidget);
    expect(_t('確認通知'), findsNothing);
    calls.pending!.complete(const NearbyBroadcastSent(3));
    await _settle(t);
    await _show(t, _t('已通知 3 位附近協助者'));
    expect(_tc('不代表有人會趕到'), findsOneWidget);
    expect(calls.count, 1);
    _expectNoOverclaim(t);
  });

  testWidgets('zero recipients is stated plainly', (t) async {
    final calls = _Calls();
    await _openEmergency(t, _available(calls));
    await _tap(t, '通知附近協助者');
    await _tap(t, '確認通知');
    calls.pending!.complete(const NearbyBroadcastSent(0));
    await _settle(t);
    await _show(t, _t('已送出，但附近沒有人可通知'));
    expect(_tc('沒有已加入協助的人'), findsOneWidget);
    _expectNoOverclaim(t);
  });

  testWidgets('a failure shows its message and allows another try', (t) async {
    final calls = _Calls();
    await _openEmergency(t, _available(calls));
    await _tap(t, '通知附近協助者');
    await _tap(t, '確認通知');
    calls.pending!.complete(const NearbyBroadcastNotSent('測試：操作太頻繁'));
    await _settle(t);
    await _show(t, _t('沒有送出'));
    expect(_tc('測試：操作太頻繁'), findsOneWidget);
    await _tap(t, '再試一次');
    await _show(t, _t('確認通知'));
    expect(calls.count, 1);
    _expectNoOverclaim(t);
  });

  testWidgets('an exception becomes a generic failure, not a crash', (t) async {
    final calls = _Calls();
    await _openEmergency(
      t,
      _available(calls, run: (_) async => throw StateError('SECRET')),
    );
    await _tap(t, '通知附近協助者');
    await _tap(t, '確認通知');
    await _show(t, _t('沒有送出'));
    expect(_tc('SECRET'), findsNothing);
    expect(_tc('請改用電話求助'), findsOneWidget);
  });

  testWidgets('cancel while sending cancels the request', (t) async {
    final calls = _Calls();
    await _openEmergency(
      t,
      _available(
        calls,
        run: (c) async {
          await c.whenCancelled;
          return const NearbyBroadcastNotSent('已取消', cancelled: true);
        },
      ),
    );
    await _tap(t, '通知附近協助者');
    await _tap(t, '確認通知');
    expect(calls.token!.isCancelled, isFalse);
    await _tap(t, '取消');
    expect(calls.token!.isCancelled, isTrue);
    await _show(t, _t('沒有送出'));
    expect(calls.count, 1);
  });

  testWidgets('leaving the page cancels an in-flight request safely', (
    t,
  ) async {
    final calls = _Calls();
    await _openEmergency(t, _available(calls));
    await _tap(t, '通知附近協助者');
    await _tap(t, '確認通知');
    expect(calls.token!.isCancelled, isFalse);
    await _tap(t, '我現在安全，關閉');
    expect(calls.token!.isCancelled, isTrue);
    // A late answer after leaving must not touch the disposed card.
    calls.pending!.complete(const NearbyBroadcastSent(5));
    await _settle(t);
    expect(_t('已通知 5 位附近協助者'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('the card meets tap-target, label and contrast guidelines', (
    t,
  ) async {
    final handle = t.ensureSemantics();
    final calls = _Calls();
    await _openEmergency(t, _available(calls));
    await _show(t, _t('通知附近協助者'));
    await expectLater(t, meetsGuideline(androidTapTargetGuideline));
    await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(t, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });
}
