import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_call_view.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_emergency_view.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_flow.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_home_view.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_map_view.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_speaker.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart' as sw;

class _SpySpeaker implements SafeWalkSpeaker {
  final spoken = <String>[];
  int stops = 0;
  @override
  bool get available => true;
  @override
  void speak(String text, {void Function()? onDone}) => spoken.add(text);
  @override
  void stop() => stops++;
}

Future<void> _pump(WidgetTester t, Widget w) async {
  t.view.physicalSize = const Size(390 * 3, 844 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: w));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('首頁只有四個入口與緊急求助', (t) async {
    await _pump(t, const SafeWalkFlow());
    for (final name in ['安心行', '點擊開始', '模擬來電', '附近求助地點', '回報狀況', '緊急求助']) {
      expect(find.text(name), findsWidgets, reason: name);
    }
  });

  testWidgets('緊急求助是單獨一頁；mock 不撥號，選 110 只回報示範訊息', (t) async {
    final calls = <sw.EmergencyChannel>[];
    await _pump(
      t,
      SafeWalkFlow(
        onEmergency: (c) async {
          calls.add(c);
          throw UnimplementedError('mock 測試不應真的取得結果');
        },
      ),
    );
    await t.tap(find.text('緊急求助').first);
    await t.pumpAndSettle();
    expect(find.text('撥打 110 報警'), findsOneWidget);
    expect(find.text('目前沒有撥號設定'), findsOneWidget);
    expect(find.text('未實際串接警方'), findsOneWidget);
    await t.tap(find.text('我現在安全，關閉'));
    await t.pumpAndSettle();
    expect(find.text('安心行'), findsOneWidget);
    expect(calls, isEmpty);
  });

  testWidgets('地圖預設回家路線並顯示已繞開的異常回報；可展開文字路線', (t) async {
    await _pump(t, const SafeWalkFlow());
    await t.tap(find.text('安心行'));
    await t.pumpAndSettle();
    expect(find.textContaining('已繞開'), findsOneWidget);
    expect(find.text('路線僅供參考・請留意實際路況'), findsNothing, reason: '上方提示已拿掉，資訊框內已有說明');
    await t.tap(find.text('文字路線'));
    await t.pumpAndSettle();
    expect(find.text('抵達家'), findsOneWidget);
  });

  testWidgets('最近求助地點是中性目的地，可切換下一個；資訊框可收合', (t) async {
    await _pump(t, const SafeWalkFlow());
    await t.tap(find.text('安心行'));
    await t.pumpAndSettle();
    expect(find.textContaining('7-ELEVEN'), findsNothing);
    await t.tap(find.text('最近求助地點'));
    await t.pumpAndSettle();
    expect(find.bySemanticsLabel('換下一個求助地點'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('收合資訊框'));
    await t.pumpAndSettle();
    expect(find.bySemanticsLabel('換下一個求助地點'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('展開資訊框')), findsOneWidget);
  });

  testWidgets('求助地點：載入中、錯誤可重試、空資料都有明確狀態', (t) async {
    await _pump(t, const SafeWalkFlow(pointsLoading: true));
    await t.tap(find.text('附近求助地點'));
    await t.pumpAndSettle();
    expect(find.bySemanticsLabel('載入中'), findsOneWidget);

    var retried = 0;
    await _pump(t, SafeWalkFlow(pointsError: '網路連線中斷', onRetryPoints: () => retried++));
    await t.tap(find.text('附近求助地點'));
    await t.pumpAndSettle();
    expect(find.text('求助地點暫時載入失敗'), findsOneWidget);
    await t.tap(find.text('再試一次'));
    expect(retried, 1);

    await _pump(t, const SafeWalkFlow(points: []));
    await t.tap(find.text('附近求助地點'));
    await t.pumpAndSettle();
    expect(find.text('附近還沒有求助地點資料'), findsOneWidget);
  });

  testWidgets('模擬來電：英文由 TTS 朗讀，繁中只顯示供使用者照讀', (t) async {
    final speaker = _SpySpeaker();
    await _pump(t, SafeWalkFlow(speaker: speaker));
    await t.tap(find.text('模擬來電'));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('接聽'));
    await t.pump(const Duration(milliseconds: 300));
    expect(speaker.spoken.single, startsWith('Damn it, babe'));
    await t.tap(find.text('我快到了，但我後面好像有人一直跟著我。'));
    await t.pump(const Duration(milliseconds: 100));
    expect(speaker.spoken.length, 1, reason: '自己的回應不朗讀');
    await t.pump(const Duration(seconds: 1));
    expect(speaker.spoken.length, 2);
    expect(speaker.spoken.last, startsWith("What? Don't turn around"));
    await t.tap(find.text('好，我看到你了，我現在直接走過去。電話先不要掛。'));
    await t.pump(const Duration(seconds: 1));
    expect(speaker.spoken.length, 3);
    expect(speaker.spoken.last, startsWith('I see you.'));
    expect(find.textContaining('已到劇本最後一句'), findsOneWidget);
    expect(find.textContaining('已播放完畢'), findsNothing);
    await t.tap(find.text('緊急求助').first);
    await t.pump(const Duration(milliseconds: 300));
    expect(speaker.stops, greaterThan(0));
    expect(find.text('撥打 119'), findsOneWidget);
  });

  testWidgets('簡訊報警：選情況、預覽含 GPS 欄位、示範傳送顯示成功且不呼叫真實傳送', (t) async {
    await _pump(t, const SafeWalkFlow());
    await t.tap(find.text('緊急求助').first);
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('傳送簡訊'), 200, scrollable: find.byType(Scrollable).first);
    await t.tap(find.text('有人打架'));
    await t.pumpAndSettle();
    expect(find.textContaining('情況：有人打架'), findsOneWidget);
    expect(find.textContaining('GPS 座標'), findsOneWidget);
    expect(find.textContaining('IP'), findsNothing);
    await t.tap(find.text('傳送簡訊'));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('傳送中…'), findsOneWidget);
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
    expect(find.text('簡訊內容已準備好'), findsOneWidget);
  });

  testWidgets('[P2] Mock 模式即使注入 sender 也不呼叫外部簡訊', (t) async {
    var sent = 0;
    await _pump(
      t,
      SafeWalkFlow(
        onSendSms: (body) async {
          sent++;
          return true;
        },
      ),
    );
    await t.tap(find.text('緊急求助').first);
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('傳送簡訊'), 200, scrollable: find.byType(Scrollable).first);
    await t.drag(find.byType(Scrollable).first, const Offset(0, -200));
    await t.pumpAndSettle();
    await t.tap(find.text('傳送簡訊'));
    await t.pump(const Duration(milliseconds: 100));
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
    expect(sent, 0);
    expect(find.text('簡訊內容已準備好'), findsOneWidget);
  });

  testWidgets('[P2] 回覆倒數中按 SOS，不會在求助畫面重新朗讀', (t) async {
    final speaker = _SpySpeaker();
    await _pump(t, SafeWalkFlow(speaker: speaker));
    await t.tap(find.text('模擬來電'));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('接聽'));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('我快到了，但我後面好像有人一直跟著我。'));
    await t.pump(const Duration(milliseconds: 800));
    await t.tap(find.text('緊急求助').first);
    await t.pump(const Duration(milliseconds: 100));
    await t.pump(const Duration(seconds: 2));
    expect(speaker.spoken.length, 1, reason: '倒數被取消，不應再朗讀下一句');
    expect(find.text('撥打 110 報警'), findsOneWidget);
  });

  for (final (label, width, scale) in [('320px', 320.0, 1.0), ('390px＋200% 文字', 390.0, 2.0), ('320px＋200% 文字', 320.0, 2.0)]) {
    testWidgets('[P2] $label：首頁、地圖、來電、緊急求助都不溢出', (t) async {
      t.view.physicalSize = Size(width * 3, 844 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      Future<void> open(String entry) async {
        await t.pumpWidget(
          MaterialApp(
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: SafeWalkFlow(key: UniqueKey()),
          ),
        );
        await t.pumpAndSettle();
        if (entry.isNotEmpty) {
          if (find.text(entry).evaluate().isEmpty) await t.scrollUntilVisible(find.text(entry), 200, scrollable: find.byType(Scrollable).first);
          await t.ensureVisible(find.text(entry).first);
          await t.pumpAndSettle();
          await t.tap(find.text(entry).first);
          await t.pump(const Duration(milliseconds: 400));
        }
        final pageType = switch (entry) {
          '' => SafeWalkHomeView,
          '安心行' => SafeWalkMapView,
          '模擬來電' => SafeWalkCallView,
          '緊急求助' => SafeWalkEmergencyView,
          _ => throw ArgumentError.value(entry, 'entry'),
        };
        expect(find.byType(pageType), findsOneWidget, reason: '$label $entry opened the expected page');
        expect(t.takeException(), isNull, reason: '$label $entry');
      }

      await open('');
      await open('安心行');
      expect(find.text('緊急求助'), findsWidgets);
      await open('模擬來電');
      await open('緊急求助');
    });
  }

  testWidgets('資訊框三段：往上滑變滿版、往下滑縮回、點把手收合', (t) async {
    await _pump(t, const SafeWalkFlow());
    await t.tap(find.text('安心行'));
    await t.pumpAndSettle();
    await t.fling(find.bySemanticsLabel('收合資訊框'), const Offset(0, -200), 1000);
    await t.pumpAndSettle();
    expect(find.bySemanticsLabel('資訊框縮回一般大小'), findsOneWidget);
    await t.fling(find.bySemanticsLabel('資訊框縮回一般大小'), const Offset(0, 200), 1000);
    await t.pumpAndSettle();
    await t.tap(find.bySemanticsLabel('收合資訊框'));
    await t.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('展開資訊框')), findsOneWidget);
  });

  testWidgets('右上「回報」工具進入選位置模式', (t) async {
    await _pump(t, const SafeWalkFlow());
    await t.tap(find.text('安心行'));
    await t.pumpAndSettle();
    await t.tap(find.bySemanticsLabel('回報狀況，在地圖上標出異常'));
    await t.pumpAndSettle();
    expect(find.text('要回報哪裡？'), findsOneWidget);
  });

  testWidgets('目的地：可切換到公司、新增地點（在地圖上點位置）', (t) async {
    await _pump(t, const SafeWalkFlow());
    await t.tap(find.text('安心行'));
    await t.pumpAndSettle();
    await t.tap(find.textContaining('→ 家'));
    await t.pumpAndSettle();
    expect(find.text('要去哪裡？'), findsOneWidget);
    await t.tap(find.text('公司'));
    await t.pumpAndSettle();
    expect(find.textContaining('→ 公司'), findsOneWidget);
    expect(find.text('目的地'), findsOneWidget);

    await t.tap(find.textContaining('→ 公司'));
    await t.pumpAndSettle();
    await t.tap(find.text('新增地點'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '學校');
    await t.pump();
    await t.tap(find.text('在地圖上選位置'));
    await t.pumpAndSettle();
    expect(find.text('新增「學校」'), findsOneWidget);
    // 點地圖上沒有標記的空白處（家與公司在天母，示範標記在南邊）。
    await t.tapAt(const Offset(40, 330));
    await t.pumpAndSettle();
    expect(find.textContaining('→ 學校'), findsOneWidget);
  });

  testWidgets('圖例與回報一次只開一個', (t) async {
    await _pump(t, const SafeWalkFlow());
    await t.tap(find.text('安心行'));
    await t.pumpAndSettle();
    await t.tap(find.bySemanticsLabel('顯示圖例'));
    await t.pumpAndSettle();
    expect(find.text('圖例'), findsWidgets);
    await t.tap(find.bySemanticsLabel('回報狀況，在地圖上標出異常'));
    await t.pumpAndSettle();
    expect(find.bySemanticsLabel('關閉圖例'), findsNothing, reason: '開回報時圖例自動關閉');
    await t.tap(find.bySemanticsLabel('顯示圖例'));
    await t.pumpAndSettle();
    expect(find.text('要回報哪裡？'), findsNothing, reason: '開圖例時回報模式自動關閉');
  });

  group('路線接口（M2 → M1 → M3）', () {
    sw.RouteSuccess ok({sw.DataMode mode = sw.DataMode.live}) => sw.RouteSuccess(
      requestId: 'r1',
      mode: mode,
      generatedAt: '2026-11-07T18:00:00+08:00',
      warnings: const ['測試資料'],
      routes: [
        sw.RouteCandidate(
          id: 'c1',
          kind: sw.RouteKind.direct,
          geometry: sw.LineString(coordinates: const [(longitude: 121.5, latitude: 25.0), (longitude: 121.502, latitude: 25.0), (longitude: 121.502, latitude: 25.002)]),
          distanceMeters: 420,
          durationSeconds: 360,
          viaPointIds: const [],
          provider: 'test',
          walkingNetworkVerified: true,
          explanations: const ['沿大路走，避開 2 個回報點'],
          warnings: const ['測試資料'],
        ),
      ],
    );

    testWidgets('打開地圖與換目的地時才請 M1 規劃；一進安心行不自動送出', (t) async {
      final asked = <sw.Coordinates>[];
      await _pump(t, SafeWalkFlow(onPlanRoute: asked.add));
      expect(asked, isEmpty, reason: '還在首頁，使用者沒操作前不規劃');
      await t.tap(find.text('安心行'));
      await t.pumpAndSettle();
      expect(asked, hasLength(1), reason: '點主卡打開地圖才規劃');
      await t.tap(find.textContaining('→ 家'));
      await t.pumpAndSettle();
      await t.tap(find.text('公司'));
      await t.pumpAndSettle();
      expect(asked, hasLength(2));
      expect(asked.last.lat, closeTo(25.114604, 1e-6), reason: '公司＝北市大天母校區');
    });

    testWidgets('計算中：不畫示範路線，資訊框寫「路線計算中」', (t) async {
      await _pump(t, const SafeWalkFlow(routeLoading: true));
      await t.tap(find.text('安心行'));
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('正在計算避開異常回報的路線…'), findsOneWidget);
      expect(find.textContaining('已繞開'), findsNothing);
    });

    testWidgets('失敗：顯示原因、再試一次會重新要求，也能改去求助地點', (t) async {
      final asked = <sw.Coordinates>[];
      await _pump(
        t,
        SafeWalkFlow(
          onPlanRoute: asked.add,
          route: sw.RouteFailure(
            requestId: 'r1',
            mode: sw.DataMode.live,
            generatedAt: '2026-11-07T18:00:00+08:00',
            status: sw.RouteFailureStatus.noRoute,
            reason: '附近道路資料不足。',
            warnings: const ['測試資料'],
          ),
        ),
      );
      await t.tap(find.text('安心行'));
      await t.pumpAndSettle();
      expect(find.text('找不到回家路線'), findsWidgets);
      expect(find.text('附近道路資料不足。'), findsOneWidget);
      await t.tap(find.text('再試一次'));
      await t.pumpAndSettle();
      expect(asked, hasLength(2));
      await t.tap(find.text('改去最近求助地點'));
      await t.pumpAndSettle();
      expect(find.text('找不到回家路線'), findsNothing);
    });

    testWidgets('成功：用 M2 的距離與時間，標示「僅供參考」而非示範', (t) async {
      await _pump(t, SafeWalkFlow(route: ok()));
      await t.tap(find.text('安心行'));
      await t.pumpAndSettle();
      expect(find.textContaining('示範'), findsNothing);
      expect(find.textContaining('約 420 公尺'), findsOneWidget);
      expect(find.text('沿大路走，避開 2 個回報點'), findsOneWidget);
      expect(find.textContaining('6 分鐘'), findsWidgets);
    });
  });
}
