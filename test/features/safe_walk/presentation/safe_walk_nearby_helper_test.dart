// 附近協助者：首頁的加入卡片（兩段式同意）與「附近有人求助」橫幅。
// 只測呈現；沒有後端、沒有位置。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_flow.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_nearby_helper.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

const _forbidden = ['已報警', '已通報', '已派遣', '馬上有人', '有人正在趕來', '警方已', '已查證'];

class _Helper extends ChangeNotifier implements SafeWalkNearbyHelper {
  @override
  String? unavailableReason;
  @override
  bool isOn = false;
  @override
  bool isBusy = false;
  @override
  String? message;
  @override
  bool messageIsError = false;
  List<SafeWalkNearbyAlert> alerts = [];
  int enables = 0, disables = 0;
  final dismissed = <String>[];

  @override
  List<SafeWalkNearbyAlert> get incoming => alerts;

  @override
  bool guardAreasSupported = false;
  @override
  List<SafeWalkGuardArea> guardAreas = [];
  final addedRadii = <int>[];
  final removedIndexes = <int>[];

  @override
  Future<void> addGuardAreaHere(int radiusMeters) async {
    addedRadii.add(radiusMeters);
    change(
      () => guardAreas = [
        ...guardAreas,
        SafeWalkGuardArea(
          center: sw.Coordinates(lat: 25.033, lng: 121.566),
          radiusMeters: radiusMeters,
        ),
      ],
    );
  }

  @override
  Future<void> removeGuardArea(int index) async {
    removedIndexes.add(index);
    change(
      () => guardAreas = [
        for (var i = 0; i < guardAreas.length; i++)
          if (i != index) guardAreas[i],
      ],
    );
  }

  void change(void Function() f) {
    f();
    notifyListeners();
  }

  @override
  Future<void> enable() async {
    enables++;
    change(() => isOn = true);
  }

  @override
  Future<void> disable() async {
    disables++;
    change(() => isOn = false);
  }

  @override
  void dismiss(String alertId) {
    dismissed.add(alertId);
    change(
      () => alerts = [
        for (final a in alerts)
          if (a.alertId != alertId) a,
      ],
    );
  }
}

SafeWalkNearbyAlert _alert(String id) => SafeWalkNearbyAlert(
  alertId: id,
  location: sw.Coordinates(lat: 25.034, lng: 121.566),
  createdAt: DateTime.utc(2026, 11, 8, 1, 2, 3),
);

Future<void> _open(WidgetTester t, SafeWalkNearbyHelper? helper) async {
  t.view.physicalSize = const Size(390 * 3, 844 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      home: SafeWalkFlow(key: UniqueKey(), nearbyHelper: helper),
    ),
  );
  // A busy spinner never stops animating, so pumpAndSettle would time out.
  await t.pump();
  await t.pump(const Duration(milliseconds: 500));
  // 附近協助者放在「安心行設定」，有依賴時先從首頁齒輪進入設定頁。
  if (helper != null) {
    await t.tap(find.byTooltip('安心行設定'));
    await t.pump(const Duration(milliseconds: 500));
  }
}

Finder _t(String s) => find.text(s, skipOffstage: false);
Finder _tc(String s) => find.textContaining(s, skipOffstage: false);

Future<void> _show(WidgetTester t, Finder f) async {
  await t.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> _tap(WidgetTester t, String text) async {
  await _show(t, _t(text));
  await t.tap(_t(text));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

String _allText(WidgetTester t) => t
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
    .join('\n');

void main() {
  group('join card in 安心行設定', () {
    testWidgets('without a dependency nothing is shown', (t) async {
      await _open(t, null);
      expect(_t('附近協助者'), findsNothing);
      expect(_t('加入附近協助者'), findsNothing);
    });

    testWidgets('unavailable: the reason, no button', (t) async {
      final helper = _Helper()..unavailableReason = '測試：尚未登入';
      await _open(t, helper);
      await _show(t, _t('附近協助者：目前無法使用'));
      expect(_tc('測試：尚未登入'), findsOneWidget);
      expect(_t('加入附近協助者'), findsNothing);
      expect(helper.enables, 0);
    });

    testWidgets('joining shows the consent text first and joins only on '
        'agreement', (t) async {
      final helper = _Helper();
      await _open(t, helper);
      await _tap(t, '加入附近協助者');
      await _show(t, _t('同意並加入'));
      expect(_tc('每 4 分鐘左右'), findsOneWidget);
      expect(_tc('最多 10 分鐘內自動刪除'), findsOneWidget);
      expect(_tc('App 關閉時不會收到通知'), findsOneWidget);
      expect(_tc('你沒有義務前往'), findsOneWidget);
      expect(_tc('對方看不到你是誰'), findsOneWidget);
      expect(_tc('匿名帳號代表這支手機'), findsOneWidget);
      expect(_tc('不含姓名、電話或任何個人資料'), findsOneWidget);
      expect(helper.enables, 0);

      await _tap(t, '取消');
      expect(_t('加入附近協助者'), findsOneWidget);
      expect(helper.enables, 0);

      await _tap(t, '加入附近協助者');
      await _tap(t, '同意並加入');
      expect(helper.enables, 1);
      expect(_t('停止協助並刪除我的位置'), findsOneWidget);
    });

    testWidgets('busy shows progress, not buttons', (t) async {
      final helper = _Helper()..isBusy = true;
      await _open(t, helper);
      await _show(t, _t('處理中…'));
      expect(_t('加入附近協助者'), findsNothing);
      expect(_t('停止協助並刪除我的位置'), findsNothing);
    });

    testWidgets('joined: shows status and can stop', (t) async {
      final helper = _Helper()
        ..isOn = true
        ..message = '已加入。測試狀態';
      await _open(t, helper);
      await _show(t, _t('停止協助並刪除我的位置'));
      expect(_tc('已加入。測試狀態'), findsOneWidget);
      expect(_tc('協助中'), findsOneWidget);
      await _tap(t, '停止協助並刪除我的位置');
      expect(helper.disables, 1);
      expect(_t('加入附近協助者'), findsOneWidget);
    });

    testWidgets('a failure is shown as an error', (t) async {
      final helper = _Helper()
        ..message = '測試：定位權限未允許'
        ..messageIsError = true;
      await _open(t, helper);
      await _show(t, _t('沒有成功'));
      expect(_tc('定位權限未允許'), findsOneWidget);
    });
  });

  group('incoming alert banner', () {
    testWidgets('nothing is shown without an alert', (t) async {
      await _open(t, _Helper());
      expect(_t('附近有人求助'), findsNothing);
    });

    testWidgets('shows position, time and caution without overclaiming', (
      t,
    ) async {
      final helper = _Helper()..alerts = [_alert('a1')];
      await _open(t, helper);
      expect(_t('附近有人求助'), findsOneWidget);
      expect(_tc('25.03400, 121.56600'), findsOneWidget);
      expect(_tc('未經查證'), findsOneWidget);
      expect(_tc('不要獨自涉險'), findsOneWidget);
      expect(_tc('110／119'), findsWidgets);
      final text = _allText(t);
      for (final phrase in _forbidden) {
        expect(text, isNot(contains(phrase)), reason: phrase);
      }
    });

    testWidgets('「知道了」 dismisses just that alert', (t) async {
      final helper = _Helper()..alerts = [_alert('a1'), _alert('a2')];
      await _open(t, helper);
      expect(_t('附近有人求助（共 2 則）'), findsOneWidget);
      await t.tap(_t('知道了'));
      await t.pump();
      expect(helper.dismissed, ['a1']);
      expect(_t('附近有人求助'), findsOneWidget);
      await t.tap(_t('知道了'));
      await t.pump();
      expect(helper.dismissed, ['a1', 'a2']);
      expect(_t('附近有人求助'), findsNothing);
    });

    testWidgets('「110／119」 dismisses it and opens the emergency page', (
      t,
    ) async {
      final helper = _Helper()..alerts = [_alert('a1')];
      await _open(t, helper);
      await t.tap(find.widgetWithText(InkWell, '110／119').first);
      await t.pumpAndSettle();
      expect(helper.dismissed, ['a1']);
      expect(_t('撥打 110 報警'), findsOneWidget);
      expect(_t('附近有人求助'), findsNothing);
    });

    testWidgets('appears over any screen, including the emergency page', (
      t,
    ) async {
      final helper = _Helper();
      await _open(t, helper);
      await t.tap(find.byTooltip('返回'));
      await t.pump(const Duration(milliseconds: 500));
      await t.tap(_t('緊急求助').first);
      await t.pumpAndSettle();
      expect(_t('撥打 110 報警'), findsOneWidget);
      helper.change(() => helper.alerts = [_alert('a1')]);
      await t.pump();
      expect(_t('附近有人求助'), findsOneWidget);
      expect(_t('撥打 110 報警'), findsOneWidget);
    });

    testWidgets('the join card and the banner meet accessibility guidelines', (
      t,
    ) async {
      final handle = t.ensureSemantics();
      final helper = _Helper();
      // 先進「安心行設定」，再出現警示：警示會蓋住右上角齒輪，不能在那之後點它。
      await _open(t, helper);
      helper.change(() => helper.alerts = [_alert('a1')]);
      await t.pump();
      await _show(t, _t('加入附近協助者'));
      await expectLater(t, meetsGuideline(androidTapTargetGuideline));
      await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(t, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  });

  group('guard areas on the joined card', () {
    SafeWalkGuardArea area(double lat, int radius) => SafeWalkGuardArea(
      center: sw.Coordinates(lat: lat, lng: 121.566),
      radiusMeters: radius,
    );

    _Helper joined({bool supported = true}) => _Helper()
      ..isOn = true
      ..guardAreasSupported = supported;

    testWidgets('not shown when the backend has no guard areas', (t) async {
      await _open(t, joined(supported: false));
      await _show(t, _t('停止協助並刪除我的位置'));
      expect(_t('守護區'), findsNothing);
      expect(_t('把目前位置設為守護區'), findsNothing);
    });

    testWidgets('empty: explains itself honestly, including that there is no '
        'push', (t) async {
      await _open(t, joined());
      await _show(t, _t('守護區'));
      expect(_t('還沒有守護區。'), findsOneWidget);
      expect(_tc('30 分鐘內開啟 App 就會看到'), findsOneWidget);
      expect(_tc('目前沒有推播，不會主動提醒你'), findsOneWidget);
      expect(_t('把目前位置設為守護區'), findsOneWidget);
    });

    testWidgets('adding is two-step: radius and consent first, position '
        'only after confirming', (t) async {
      final helper = joined();
      await _open(t, helper);
      await _tap(t, '把目前位置設為守護區');
      await _show(t, _t('確認設定'));
      expect(_tc('四捨五入到約 100 公尺'), findsOneWidget);
      expect(_tc('住家或公司'), findsOneWidget);
      expect(_t('1 公里'), findsOneWidget);
      // 2 km is no longer offered.
      expect(_t('2 公里'), findsNothing);
      expect(helper.addedRadii, isEmpty);

      await _tap(t, '1 公里');
      await _tap(t, '確認設定');
      expect(helper.addedRadii, [1000]);
      await _show(t, _tc('25.033, 121.566・半徑 1 公里'));
      expect(_t('把目前位置設為守護區'), findsOneWidget);
    });

    testWidgets('cancelling the add changes nothing', (t) async {
      final helper = joined();
      await _open(t, helper);
      await _tap(t, '把目前位置設為守護區');
      await _tap(t, '取消');
      expect(helper.addedRadii, isEmpty);
      expect(_t('把目前位置設為守護區'), findsOneWidget);
      expect(_t('確認設定'), findsNothing);
    });

    testWidgets('areas are listed and can be removed', (t) async {
      final helper = joined()
        ..guardAreas = [area(25.033, 500), area(25.05, 1000)];
      await _open(t, helper);
      await _show(t, _tc('25.033, 121.566・半徑 500 公尺'));
      expect(_tc('25.050, 121.566・半徑 1 公里'), findsOneWidget);
      // Each area has its own 「移除」; take the first row.
      await _show(t, _t('移除').first);
      await t.tap(_t('移除').first);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(helper.removedIndexes, [0]);
      expect(_tc('25.033, 121.566・半徑 500 公尺'), findsNothing);
      expect(_tc('25.050, 121.566・半徑 1 公里'), findsOneWidget);
    });

    testWidgets('at the limit of three there is no add button', (t) async {
      final helper = joined()
        ..guardAreas = [area(25.03, 500), area(25.04, 500), area(25.05, 500)];
      await _open(t, helper);
      await _show(t, _t('最多 3 個守護區。'));
      expect(_t('把目前位置設為守護區'), findsNothing);
    });

    testWidgets('the guard-area section meets accessibility guidelines', (
      t,
    ) async {
      final handle = t.ensureSemantics();
      final helper = joined()..guardAreas = [area(25.033, 500)];
      await _open(t, helper);
      await _show(t, _t('把目前位置設為守護區'));
      await expectLater(t, meetsGuideline(androidTapTargetGuideline));
      await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(t, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  });
}
