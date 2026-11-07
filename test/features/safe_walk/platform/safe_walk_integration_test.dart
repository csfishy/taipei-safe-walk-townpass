import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show TileLayer;
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:town_pass/features/safe_walk/companion/companion_service.dart';
import 'package:town_pass/features/safe_walk/platform/integration/companion_speaker_adapter.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_composition_root.dart';
import 'package:town_pass/features/safe_walk/platform/platform_service.dart';
import 'package:town_pass/features/safe_walk/presentation/mock/safe_walk_demo_data.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_flow.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_home_view.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_speaker.dart';
import 'package:town_pass/features/safe_walk/safety_data/safety_data_service.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;
import 'package:town_pass/page/city_service/city_service_view.dart';
import 'package:town_pass/page/city_service/widget/pinned_service_widget_controller.dart';
import 'package:town_pass/util/tp_route.dart';

void phoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> cityApp(WidgetTester tester, Widget Function()? root) async {
  phoneSize(tester);
  Get.put(PinnedServiceWidgetController());
  await tester.pumpWidget(
    GetMaterialApp(
      home: const CityServiceView(),
      getPages: [
        root == null
            ? TPRoute.page.singleWhere((page) => page.name == TPRoute.safeWalk)
            : GetPage(name: TPRoute.safeWalk, page: root),
      ],
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byType(CityServiceView), findsOneWidget);
  expect(find.text('臺北安心行'), findsOneWidget);
}

Future<void> enter(WidgetTester tester) async {
  await tester.tap(find.text('臺北安心行'));
  await tester.pumpAndSettle();
  expect(find.byType(SafeWalkFlow), findsOneWidget);
}

Future<void> back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

class _Platform implements PlatformService {
  _Platform(this.trace);
  final List<String> trace;
  int locations = 0, emergencies = 0;
  Future<sw.LocationResult> Function()? result;
  SafeWalkCancellation? locationCancellation;

  @override
  Future<sw.LocationResult> getCurrentPosition({
    required sw.DataMode mode,
    required bool userInitiated,
    SafeWalkCancellation? cancellation,
  }) async {
    expect(mode, sw.DataMode.mock);
    expect(userInitiated, isTrue);
    locationCancellation = cancellation;
    locations++;
    return result?.call() ??
        sw.LocationFailure(
          status: sw.LocationFailureStatus.denied,
          message: '測試：定位權限未允許',
        );
  }

  @override
  Future<sw.EmergencyActionResult> requestEmergency({
    required sw.DataMode mode,
    required sw.EmergencyChannel channel,
    required bool userInitiated,
    required bool allowRealCalls,
    sw.IncidentSummary? summary,
  }) async {
    expect(mode, sw.DataMode.mock);
    expect(userInitiated, isTrue);
    expect(allowRealCalls, isFalse);
    expect(summary, isNull);
    emergencies++;
    trace.add('emergency');
    return sw.EmergencyActionResult.fromJson({
      'schemaVersion': '1.0.0',
      'channel': channel.wireValue,
      'action': 'not_configured',
      'officialReceipt': null,
      'message': '示範：未撥號、未通知任何人。',
    });
  }
}

class _Data implements SafetyDataRepository {
  Future<List<sw.AssistancePoint>> Function(int)? load;
  final cancellations = <SafeWalkCancellation?>[];
  int calls = 0;

  @override
  Future<List<sw.AssistancePoint>> getAssistancePoints({
    required sw.DataMode mode,
    SafeWalkCancellation? cancellation,
  }) {
    expect(mode, sw.DataMode.mock);
    cancellations.add(cancellation);
    final call = calls++;
    return load?.call(call) ?? Future.value(demoAssistancePoints());
  }

  @override
  Future<List<sw.AreaStatistics>> getAreaStatistics({
    required sw.DataMode mode,
    SafeWalkCancellation? cancellation,
  }) async => [];
}

class _Companion implements CompanionController {
  _Companion(this.trace);
  final List<String> trace;
  int starts = 0, disposals = 0;
  @override
  Stream<sw.CompanionEvent> get events => const Stream.empty();
  @override
  Future<void> start(
    sw.CompanionScenario scenario, {
    SafeWalkCancellation? cancellation,
  }) async {
    starts++;
  }

  @override
  Future<void> pause() async {}
  @override
  Future<void> stop(sw.CompanionStopReason reason) async {
    trace.add('stop:${reason.name}');
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }
}

class _Speaker implements SafeWalkSpeaker {
  final spoken = <String>[];
  @override
  bool get available => true;
  @override
  void speak(String text, {void Function()? onDone}) => spoken.add(text);
  @override
  void stop() {}
}

void main() {
  setUp(() => Get.testMode = true);
  tearDown(() => Get.reset());

  testWidgets(
    'real city service and registered route open the Live M3 flow without demo destinations',
    (t) async {
      await cityApp(t, null);
      await enter(t);
      final flow = t.widget<SafeWalkFlow>(find.byType(SafeWalkFlow));
      expect(flow.mode, sw.DataMode.live);
      expect(flow.allowRealCalls, isFalse);
      expect(flow.speaker.available, isFalse);
      // Live entry shows no demo help points (real nearby places come later).
      expect(flow.points, isEmpty);
      expect(flow.onPlanRoute, isNotNull);
      expect(flow.homeLocation, isNull);
      expect(flow.route, isNull);
      await t.tap(find.text('安心行'));
      await t.pumpAndSettle();
      expect(find.text('地圖載入設定'), findsNothing);
      expect(find.byType(TileLayer), findsOneWidget);
      expect(find.text('家在哪裡？'), findsOneWidget);
      expect(find.text('規劃路線需要你的位置'), findsNothing);
      await back(t);
      await back(t);
      expect(find.byType(CityServiceView), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'A-G demo connects route, points, text companion, SOS and return',
    (t) async {
      final trace = <String>[];
      final platform = _Platform(trace);
      final data = _Data();
      final companion = _Companion(trace);
      await cityApp(
        t,
        () => SafeWalkCompositionRoot(
          platform: platform,
          safetyData: data,
          speaker: CompanionSpeakerAdapter(controller: companion),
        ),
      );
      await enter(t);
      expect(platform.locations, 0);
      expect(platform.emergencies, 0);
      await t.tap(find.text('安心行'));
      await t.pumpAndSettle();
      expect(find.text('路線僅供參考・請留意實際路況'), findsNothing);
      // 文字路線暫時隱藏（程式保留）。
      expect(find.text('文字路線'), findsNothing);
      await back(t);
      await _openNearby(t);
      await t.pumpAndSettle();
      expect(find.textContaining('派出所'), findsWidgets);
      await back(t);
      await t.tap(find.text('模擬來電'));
      await t.pumpAndSettle();
      await t.tap(find.text('接聽'));
      await t.pumpAndSettle();
      expect(companion.starts, 0);
      await t.tap(find.text('緊急求助').first);
      await t.pumpAndSettle();
      await t.tap(find.text('撥打 110 報警'));
      await t.pumpAndSettle();
      expect(
        trace.indexOf('stop:emergency'),
        lessThan(trace.indexOf('emergency')),
      );
      expect(platform.emergencies, 1);
      await t.scrollUntilVisible(
        find.text('示範：未撥號、未通知任何人。'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      expect(find.text('示範：未撥號、未通知任何人。'), findsOneWidget);
      await t.scrollUntilVisible(
        find.text('我現在安全，關閉'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.tap(find.text('我現在安全，關閉'));
      await t.pumpAndSettle();
      expect(find.text('安心行'), findsOneWidget);
      await back(t);
      expect(find.byType(CityServiceView), findsOneWidget);
      expect(companion.disposals, 1);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'points distinguish error, retry loading and a valid empty result',
    (t) async {
      final retried = Completer<List<sw.AssistancePoint>>();
      final data = _Data()
        ..load = (n) => n == 0
            ? Future.error(StateError('synthetic source failure'))
            : retried.future;
      await cityApp(t, () => SafeWalkCompositionRoot(safetyData: data));
      await enter(t);
      await _openNearby(t);
      await t.pumpAndSettle();
      expect(find.text('求助地點暫時載入失敗'), findsOneWidget);
      await t.tap(find.text('再試一次'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.bySemanticsLabel('載入中'), findsOneWidget);
      expect(data.cancellations.first!.isCancelled, isTrue);
      retried.complete([]);
      await t.pumpAndSettle();
      expect(find.text('附近還沒有求助地點資料'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump();
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('late data after route exit cannot update or revive the flow', (
    t,
  ) async {
    final pending = Completer<List<sw.AssistancePoint>>();
    final data = _Data()..load = (_) => pending.future;
    await cityApp(t, () => SafeWalkCompositionRoot(safetyData: data));
    await enter(t);
    await back(t);
    expect(data.cancellations.single!.isCancelled, isTrue);
    pending.complete(demoAssistancePoints());
    await t.pumpAndSettle();
    expect(find.byType(SafeWalkFlow), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'location is requested only on tap and denial/timeout are readable',
    (t) async {
      final platform = _Platform([]);
      await cityApp(t, () => SafeWalkCompositionRoot(platform: platform));
      await enter(t);
      expect(platform.locations, 0);
      await t.tap(find.text('緊急求助').first);
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('取得目前位置'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.tap(find.text('取得目前位置'));
      await t.pumpAndSettle();
      expect(find.text('測試：定位權限未允許'), findsOneWidget);
      platform.result = () =>
          Future.error(TimeoutException('synthetic timeout'));
      await t.scrollUntilVisible(
        find.text('再試一次'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.tap(find.text('再試一次'));
      await t.pumpAndSettle();
      expect(find.text('定位逾時，請重試或說出附近地標。'), findsOneWidget);
      expect(platform.locations, 2);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump();
    },
  );

  testWidgets(
    'a live-data repository cannot silently populate the mock route',
    (t) async {
      final json = demoAssistancePoints().first.toJson();
      final source = (json['source']! as Map).cast<String, Object?>();
      source['dataMode'] = 'live';
      source['sourceUrl'] = 'https://example.invalid/source';
      json['source'] = source;
      final data = _Data()
        ..load = (_) async => [sw.AssistancePoint.fromJson(json)];
      await cityApp(t, () => SafeWalkCompositionRoot(safetyData: data));
      await enter(t);
      final flow = t.widget<SafeWalkFlow>(find.byType(SafeWalkFlow));
      expect(flow.points, isEmpty);
      expect(flow.pointsError, isNotNull);
      await back(t);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('H repeated entry creates and releases one companion per route', (
    t,
  ) async {
    final instances = <_Companion>[];
    final data = _Data();
    await cityApp(t, () {
      final companion = _Companion([]);
      instances.add(companion);
      return SafeWalkCompositionRoot(
        safetyData: data,
        speaker: CompanionSpeakerAdapter(controller: companion),
      );
    });
    for (var i = 0; i < 3; i++) {
      await enter(t);
      await t.tap(find.text('模擬來電'));
      await t.pumpAndSettle();
      await t.tap(find.text('接聽'));
      await t.pumpAndSettle();
      await t.tap(find.text('結束通話'));
      await t.pumpAndSettle();
      await back(t);
      expect(find.byType(CityServiceView), findsOneWidget);
    }
    expect(instances, hasLength(3));
    expect(
      instances.every(
        (instance) => instance.disposals == 1 && instance.starts == 0,
      ),
      isTrue,
    );
    expect(data.cancellations.every((token) => token!.isCancelled), isTrue);
    expect(t.takeException(), isNull);
  });

  testWidgets('Mock SMS never invokes an injected sender and says not sent', (
    t,
  ) async {
    var sent = 0;
    phoneSize(t);
    await t.pumpWidget(
      MaterialApp(
        home: SafeWalkFlow(
          onSendSms: (_) async {
            sent++;
            return true;
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('緊急求助').first);
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.text('傳送簡訊'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.pumpAndSettle();
    await t.tap(find.text('傳送簡訊'));
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
    expect(sent, 0);
    expect(find.text('簡訊內容已準備好'), findsOneWidget);
  });

  testWidgets('SOS cancels a reply before the outgoing call animation ends', (
    t,
  ) async {
    final speaker = _Speaker();
    phoneSize(t);
    await t.pumpWidget(MaterialApp(home: SafeWalkFlow(speaker: speaker)));
    await t.pumpAndSettle();
    await t.tap(find.text('模擬來電'));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('接聽'));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('我快到了，但我後面好像有人一直跟著我。'));
    await t.pump(const Duration(milliseconds: 800));
    final before = speaker.spoken.length;
    await t.tap(find.text('緊急求助').first);
    await t.pump(const Duration(milliseconds: 150));
    expect(speaker.spoken, hasLength(before));
    await t.pumpAndSettle();
    expect(find.text('撥打 119'), findsOneWidget);
  });
}

/// 首頁不再有「附近求助地點」入口（主要入口是地圖面板的「最近求助地點」）；
/// 清單畫面的程式碼仍保留，測試直接開啟它。
Future<void> _openNearby(WidgetTester t) async {
  t
      .widget<SafeWalkHomeView>(find.byType(SafeWalkHomeView))
      .onOpen(SafeWalkEntry.points);
  await t.pump();
}
