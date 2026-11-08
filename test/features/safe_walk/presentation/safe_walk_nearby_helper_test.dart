// 附近協助者：首頁的加入卡片（兩段式同意）與「附近有人求助」橫幅。
// 只測呈現；沒有後端、沒有位置。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  // ---- trusted contacts
  @override
  bool contactsSupported = false;
  @override
  bool contactsBusy = false;
  @override
  String? contactsMessage;
  @override
  bool contactsMessageIsError = false;
  @override
  List<SafeWalkContactLink> myContacts = [];
  @override
  List<SafeWalkFollowing> following = [];
  @override
  SafeWalkContactInvite? invite;
  final createdInvites = <String>[];
  final accepted = <String>[];
  final removedContacts = <String>[];
  final unfollowed = <String>[];
  int clearedInvites = 0;

  @override
  Future<void> createInvite(String displayName) async {
    createdInvites.add(displayName);
    change(
      () => invite = SafeWalkContactInvite(
        code: 'ABCDEFGH',
        expiresAt: DateTime(2026, 11, 8, 23, 30),
      ),
    );
  }

  @override
  void clearInvite() {
    clearedInvites++;
    change(() => invite = null);
  }

  @override
  Future<void> acceptInvite(String code) async {
    accepted.add(code);
  }

  @override
  Future<void> removeContact(String linkId) async {
    removedContacts.add(linkId);
    change(
      () => myContacts = [
        for (final c in myContacts)
          if (c.id != linkId) c,
      ],
    );
  }

  @override
  Future<void> unfollow(String linkId) async {
    unfollowed.add(linkId);
    change(
      () => following = [
        for (final f in following)
          if (f.id != linkId) f,
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
  group('join card on the home page', () {
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
      final helper = _Helper()..alerts = [_alert('a1')];
      await _open(t, helper);
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

  group('trusted contacts card', () {
    final since = DateTime(2026, 11, 8, 12);

    SafeWalkContactLink link(String id) =>
        SafeWalkContactLink(id: id, since: since);

    _Helper supported() => _Helper()..contactsSupported = true;

    Finder field(String label) =>
        find.widgetWithText(TextField, label, skipOffstage: false);

    // Clipboard writes are captured instead of reaching a platform.
    List<String> captureClipboard(WidgetTester t) {
      final copied = <String>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      return copied;
    }

    testWidgets('not shown when the backend cannot pair contacts', (t) async {
      await _open(t, _Helper());
      await _show(t, _t('加入附近協助者'));
      expect(_t('緊急聯絡人'), findsNothing);
      expect(_t('邀請緊急聯絡人'), findsNothing);
    });

    testWidgets('unavailable with no contacts: only the reason, no buttons', (
      t,
    ) async {
      final helper = supported()..unavailableReason = '測試：尚未登入';
      await _open(t, helper);
      await _show(t, _t('緊急聯絡人：目前無法使用'));
      expect(_t('邀請緊急聯絡人'), findsNothing);
      expect(_t('加入'), findsNothing);
      expect(helper.createdInvites, isEmpty);
      expect(helper.accepted, isEmpty);
    });

    testWidgets('empty state says there is nobody yet', (t) async {
      await _open(t, supported());
      await _show(t, _t('緊急聯絡人'));
      expect(_tc('按 SOS 時，你邀請的人會在他們的 App 內收到通知'), findsOneWidget);
      expect(_t('我的緊急聯絡人（0／5）'), findsOneWidget);
      expect(_t('還沒有緊急聯絡人。'), findsOneWidget);
      expect(_t('我是誰的緊急聯絡人'), findsOneWidget);
      expect(_t('目前沒有。'), findsOneWidget);
      expect(_t('邀請緊急聯絡人'), findsOneWidget);
    });

    testWidgets('inviting is two-step and nothing is made until confirmed', (
      t,
    ) async {
      final helper = supported();
      await _open(t, helper);
      await _tap(t, '邀請緊急聯絡人');
      await _show(t, field('對方會看到的名字（最多 20 字）'));
      expect(_tc('24 小時內有效、只能用一次'), findsOneWidget);
      expect(_tc('你可以隨時移除他'), findsOneWidget);
      expect(helper.createdInvites, isEmpty);

      // Cancelling goes back to the button and makes nothing.
      await _tap(t, '取消');
      expect(_t('邀請緊急聯絡人'), findsOneWidget);
      expect(helper.createdInvites, isEmpty);
    });

    testWidgets('an empty name makes no invite; a name is passed trimmed', (
      t,
    ) async {
      final helper = supported();
      await _open(t, helper);
      await _tap(t, '邀請緊急聯絡人');
      await _tap(t, '產生邀請碼');
      expect(helper.createdInvites, isEmpty);
      expect(_t('產生邀請碼'), findsOneWidget, reason: 'the form stays open');

      await _show(t, field('對方會看到的名字（最多 20 字）'));
      await t.enterText(field('對方會看到的名字（最多 20 字）'), '  小明  ');
      await t.pump();
      await _tap(t, '產生邀請碼');
      expect(helper.createdInvites, ['小明']);
    });

    testWidgets('the code is shown once, spaced, and is not sent by SMS', (
      t,
    ) async {
      final helper = supported()
        ..invite = SafeWalkContactInvite(
          code: 'ABCDEFGH',
          expiresAt: DateTime(2026, 11, 8, 23, 30),
        );
      await _open(t, helper);
      await _show(t, _t('ABCD EFGH'));
      expect(_tc('前有效，只能用一次'), findsOneWidget);
      expect(_tc('不會經過簡訊'), findsOneWidget);
      expect(_tc('只會顯示這一次'), findsOneWidget);
      // While a code is showing there is no second invite button.
      expect(_t('邀請緊急聯絡人'), findsNothing);
    });

    testWidgets('copying puts the plain code on the clipboard', (t) async {
      final copied = captureClipboard(t);
      final helper = supported()
        ..invite = SafeWalkContactInvite(
          code: 'ABCDEFGH',
          expiresAt: DateTime(2026, 11, 8, 23, 30),
        );
      await _open(t, helper);
      await _tap(t, '複製邀請碼');
      expect(copied, ['ABCDEFGH']);
      expect(_t('已複製'), findsOneWidget);
      expect(_t('複製邀請碼'), findsNothing);
    });

    testWidgets('「完成」 clears the code', (t) async {
      final helper = supported()
        ..invite = SafeWalkContactInvite(
          code: 'ABCDEFGH',
          expiresAt: DateTime(2026, 11, 8, 23, 30),
        );
      await _open(t, helper);
      await _tap(t, '完成');
      expect(helper.clearedInvites, 1);
      expect(_t('ABCD EFGH'), findsNothing);
      expect(_t('邀請緊急聯絡人'), findsOneWidget);
    });

    testWidgets('contacts are listed by number and can be removed', (t) async {
      final helper = supported()..myContacts = [link('c-1'), link('c-2')];
      await _open(t, helper);
      await _show(t, _t('我的緊急聯絡人（2／5）'));
      expect(_t('第 1 位・11/8 加入'), findsOneWidget);
      expect(_t('第 2 位・11/8 加入'), findsOneWidget);
      await _show(t, _t('移除').first);
      await t.tap(_t('移除').first);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(helper.removedContacts, ['c-1']);
      // The list is numbered by position, so the remaining contact is now 1st.
      expect(_t('第 1 位・11/8 加入'), findsOneWidget);
      expect(_t('第 2 位・11/8 加入'), findsNothing);
      expect(_t('我的緊急聯絡人（1／5）'), findsOneWidget);
    });

    testWidgets('at five contacts there is no invite button', (t) async {
      final helper = supported()
        ..myContacts = [for (var i = 1; i <= 5; i++) link('c-$i')];
      await _open(t, helper);
      await _show(t, _t('最多 5 位緊急聯絡人。'));
      expect(_t('我的緊急聯絡人（5／5）'), findsOneWidget);
      expect(_t('邀請緊急聯絡人'), findsNothing);
    });

    testWidgets('people you follow are listed and can be left', (t) async {
      final helper = supported()
        ..following = [
          SafeWalkFollowing(id: 'f-1', name: '小明', since: since),
          SafeWalkFollowing(id: 'f-2', name: '阿美', since: since),
        ];
      await _open(t, helper);
      await _show(t, _t('小明'));
      expect(_t('阿美'), findsOneWidget);
      expect(_t('目前沒有。'), findsNothing);
      await _show(t, _t('不再接收').first);
      await t.tap(_t('不再接收').first);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(helper.unfollowed, ['f-1']);
      expect(_t('小明'), findsNothing);
      expect(_t('阿美'), findsOneWidget);
    });

    testWidgets('entering a code and tapping 加入 uses it once and clears the '
        'field', (t) async {
      final helper = supported();
      await _open(t, helper);
      await _show(t, field('輸入對方給你的邀請碼'));
      await t.enterText(field('輸入對方給你的邀請碼'), 'abcd-efgh');
      await t.pump();
      await _tap(t, '加入');
      expect(helper.accepted, ['abcd-efgh']);
      expect(
        t.widget<TextField>(field('輸入對方給你的邀請碼')).controller!.text,
        isEmpty,
      );
      expect(_tc('只有 App 開啟時才收得到（目前沒有推播）'), findsOneWidget);
      expect(_tc('你沒有義務前往'), findsWidgets);
    });

    testWidgets('busy shows progress instead of controls', (t) async {
      final helper = supported()..contactsBusy = true;
      await _open(t, helper);
      await _show(t, _t('處理中…'));
      expect(_t('邀請緊急聯絡人'), findsNothing);
      expect(_t('加入'), findsNothing);
      expect(_t('還沒有緊急聯絡人。'), findsNothing);
    });

    testWidgets('an error is shown as an error, a note as a note', (t) async {
      final helper = supported()
        ..contactsMessage = '測試：邀請碼不正確'
        ..contactsMessageIsError = true;
      await _open(t, helper);
      await _show(t, _t('沒有成功'));
      expect(_tc('測試：邀請碼不正確'), findsOneWidget);

      helper.change(() {
        helper.contactsMessage = '測試：已移除';
        helper.contactsMessageIsError = false;
      });
      await t.pump();
      expect(_t('沒有成功'), findsNothing);
      expect(_t('目前狀態'), findsOneWidget);
      expect(_tc('測試：已移除'), findsOneWidget);
    });

    testWidgets('the populated card meets accessibility guidelines', (t) async {
      final handle = t.ensureSemantics();
      final helper = supported()
        ..myContacts = [link('c-1'), link('c-2')]
        ..following = [SafeWalkFollowing(id: 'f-1', name: '小明', since: since)];
      await _open(t, helper);
      await _show(t, _t('我的緊急聯絡人（2／5）'));
      await expectLater(t, meetsGuideline(androidTapTargetGuideline));
      await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(t, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  });

  group('banner for a trusted contact', () {
    SafeWalkNearbyAlert fromContact(String id, String? name) =>
        SafeWalkNearbyAlert(
          alertId: id,
          location: sw.Coordinates(lat: 25.034, lng: 121.566),
          createdAt: DateTime.utc(2026, 11, 8, 1, 2, 3),
          fromContact: true,
          senderName: name,
        );

    testWidgets('names the contact and says it came from them', (t) async {
      final helper = _Helper()..alerts = [fromContact('a1', '小明')];
      await _open(t, helper);
      expect(_t('小明 向你求助'), findsOneWidget);
      expect(_t('附近有人求助'), findsNothing);
      expect(_tc('25.03400, 121.56600'), findsOneWidget);
      expect(_tc('這是你的緊急聯絡人發出的求助'), findsOneWidget);
      expect(_tc('不要獨自涉險'), findsOneWidget);
      expect(_tc('110／119'), findsWidgets);
      // It is a contact's own alert, not an unverified stranger's.
      expect(_tc('未經查證'), findsNothing);
    });

    testWidgets('a blank name falls back to a generic one', (t) async {
      for (final name in [null, '', '   ']) {
        final helper = _Helper()..alerts = [fromContact('a1', name)];
        await _open(t, helper);
        expect(_t('你的緊急聯絡人 向你求助'), findsOneWidget, reason: '「$name」');
      }
    });

    testWidgets('several alerts say how many', (t) async {
      final helper = _Helper()
        ..alerts = [fromContact('a1', '小明'), fromContact('a2', '阿美')];
      await _open(t, helper);
      expect(_t('小明 向你求助（共 2 則）'), findsOneWidget);
    });

    testWidgets('a nearby helper alert is unchanged and stays anonymous', (
      t,
    ) async {
      final helper = _Helper()..alerts = [_alert('a1')];
      await _open(t, helper);
      expect(_t('附近有人求助'), findsOneWidget);
      expect(_tc('未經查證'), findsOneWidget);
      expect(_tc('向你求助'), findsNothing);
      expect(_tc('緊急聯絡人發出的求助'), findsNothing);
    });

    testWidgets('「知道了」 dismisses a contact alert', (t) async {
      final helper = _Helper()..alerts = [fromContact('a1', '小明')];
      await _open(t, helper);
      await t.tap(_t('知道了'));
      await t.pump();
      expect(helper.dismissed, ['a1']);
      expect(_t('小明 向你求助'), findsNothing);
    });

    testWidgets('nothing claims a report, dispatch, verification or arrival', (
      t,
    ) async {
      final helper = _Helper()..alerts = [fromContact('a1', '小明')];
      await _open(t, helper);
      final text = _allText(t);
      for (final phrase in _forbidden) {
        expect(text, isNot(contains(phrase)), reason: phrase);
      }
    });
  });
}
