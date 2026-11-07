import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/presentation/demo_map.dart';
import 'package:town_pass/features/safe_walk/presentation/mock/safe_walk_demo_data.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_call_view.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_emergency_view.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_flow.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_live_map_view.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_ui.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/safe_walk_navigation_scope.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

// Synthetic positions and provider responses; tiles use the global fake provider.
sw.Position _position() => sw.Position(
  coordinates: sw.Coordinates(lat: 25.0478, lng: 121.517),
  source: sw.PositionSource.gps,
  accuracyMeters: 12,
  observedAt: DateTime.now().toUtc().toIso8601String(),
);

sw.RouteSuccess _route({String id = 'synthetic-live-route'}) => sw.RouteSuccess(
  requestId: id,
  mode: sw.DataMode.live,
  generatedAt: DateTime.now().toUtc().toIso8601String(),
  warnings: const ['測試限制'],
  routes: [
    sw.RouteCandidate(
      id: 'walking',
      kind: sw.RouteKind.direct,
      geometry: sw.LineString(
        coordinates: const [
          (longitude: 121.517, latitude: 25.0478),
          (longitude: 121.519, latitude: 25.05),
        ],
      ),
      distanceMeters: 326,
      durationSeconds: null,
      viaPointIds: const [],
      provider: 'synthetic-foot-provider',
      walkingNetworkVerified: true,
      explanations: const ['人工測試步行資料'],
      warnings: const ['測試限制'],
    ),
  ],
);

class _Harness extends StatefulWidget {
  const _Harness({super.key, this.flow = false, this.onLocate});
  final bool flow;
  final Future<sw.LocationResult> Function()? onLocate;
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  bool locationConsent = false, routingConsent = false;
  bool locationLoading = false, routeLoading = false;
  sw.Position? position;
  sw.RouteResult? result;
  String? locationError, routeError;
  final events = <String>[];
  final planned = <sw.Coordinates>[];

  void publish({sw.Position? at, sw.RouteResult? route, String? error}) {
    setState(() {
      position = at;
      result = route;
      locationError = error;
      locationLoading = routeLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) => SafeWalkNavigationScope(
    mode: sw.DataMode.live,
    liveNavigationAvailable: true,
    hasLocationConsent: locationConsent,
    hasRoutingConsent: routingConsent,
    position: position,
    locationLoading: locationLoading,
    locationError: locationError,
    routeResult: result,
    routeLoading: routeLoading,
    routeError: routeError,
    createRouteRequest: ({
      required origin,
      required destination,
      preference,
      maxExtraDistanceMeters,
      assistancePointIds,
    }) => throw StateError('Presentation must not construct a route request'),
    onPlanRoute: (_) => throw StateError('Use the destination coordinator'),
    onPlanDestination: (destination) async {
      events.add('plan');
      planned.add(destination);
    },
    onLocationConsentChanged: (value) => setState(() {
      events.add('location:$value');
      locationConsent = value;
      if (!value) {
        position = null;
        result = null;
      }
    }),
    onRoutingConsentChanged: (value) => setState(() {
      events.add('routing:$value');
      routingConsent = value;
      if (!value) result = null;
    }),
    onDestinationChanged: () => setState(() {
      events.add('destination');
      result = null;
    }),
    onCancelRoute: () => setState(() {
      events.add('cancel');
      result = null;
      locationLoading = routeLoading = false;
    }),
    onNavigationOpened: () => events.add('opened'),
    // Record synchronously; these can run during child teardown.
    onNavigationClosed: () => events.add('closed'),
    onEmergencyOpened: () => events.add('emergency'),
    child: widget.flow
        ? SafeWalkFlow(mode: sw.DataMode.live, onLocate: widget.onLocate)
        : SafeWalkLiveMapView(
            onBack: () => events.add('back'),
            onCall: () => events.add('call'),
            onEmergency: () => events.add('sos'),
          ),
  );
}

Future<GlobalKey<_HarnessState>> _mount(
  WidgetTester t, {
  bool flow = false,
  double width = 390,
  double height = 844,
  double scale = 1,
  Future<sw.LocationResult> Function()? onLocate,
}) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final key = GlobalKey<_HarnessState>();
  await t.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: _Harness(key: key, flow: flow, onLocate: onLocate),
    ),
  );
  await t.pumpAndSettle();
  addTearDown(() async {
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 2));
  });
  return key;
}

Future<void> _tap(WidgetTester t, Finder target) async {
  await t.ensureVisible(target);
  await t.pumpAndSettle();
  await t.tap(target);
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> _prepare(WidgetTester t) async {
  t.widget<DemoMap>(find.byType(DemoMap)).onPick!(const LatLng(25.05, 121.519));
  await t.pumpAndSettle();
  await _tap(t, find.byKey(const Key('safe-walk-location-consent')));
  await _tap(t, find.byKey(const Key('safe-walk-routing-consent')));
}

Finder get _start => find.byKey(const Key('safe-walk-live-start'));

void main() {
  testWidgets(
    'Live starts neutral with no fabricated marker, route or request',
    (t) async {
      final key = await _mount(t);
      expect(find.textContaining('尚未定位'), findsOneWidget);
      final map = t.widget<DemoMap>(find.byType(DemoMap));
      expect(map.liveRendering, isTrue);
      expect(map.hasStart, isFalse);
      expect(map.path, isEmpty);
      expect(map.points, isEmpty);
      expect(map.anomalies, isEmpty);
      expect(t.widget<MarkerLayer>(find.byType(MarkerLayer)).markers, isEmpty);
      expect(key.currentState!.planned, isEmpty);
      expect(key.currentState!.events, isEmpty);
      expect(find.textContaining('已繞開'), findsNothing);
      expect(find.text('抵達家'), findsNothing);
      expect(t.widget<SwPrimaryButton>(_start).onTap, isNull);
    },
  );

  testWidgets(
    'destination and both independent consents precede explicit planning',
    (t) async {
      final key = await _mount(t);
      t.widget<DemoMap>(find.byType(DemoMap)).onPick!(
        const LatLng(25.05, 121.519),
      );
      await t.pumpAndSettle();
      await _tap(t, find.byKey(const Key('safe-walk-location-consent')));
      expect(t.widget<SwPrimaryButton>(_start).onTap, isNull);
      expect(key.currentState!.planned, isEmpty);
      await _tap(t, find.byKey(const Key('safe-walk-routing-consent')));
      expect(key.currentState!.planned, isEmpty);
      await _tap(t, _start);
      expect(key.currentState!.events.takeLast(2), ['opened', 'plan']);
      expect(key.currentState!.planned.single.lat, 25.05);
      expect(key.currentState!.planned.single.lng, 121.519);
    },
  );

  testWidgets(
    'coordinate input rejects nonfinite and range errors without planning',
    (t) async {
      final key = await _mount(t);
      final lat = find.byKey(const Key('safe-walk-destination-lat'));
      final lng = find.byKey(const Key('safe-walk-destination-lng'));
      await t.ensureVisible(lat);
      await t.enterText(lat, 'NaN');
      await t.enterText(lng, '121.519');
      await _tap(t, find.text('設定目的地'));
      expect(find.textContaining('請輸入有效座標'), findsOneWidget);
      await t.enterText(lat, '91');
      await _tap(t, find.text('設定目的地'));
      expect(find.textContaining('已選目的地'), findsNothing);
      await t.enterText(lat, '25.05');
      await _tap(t, find.text('設定目的地'));
      expect(find.text('已選目的地：25.050000, 121.519000'), findsOneWidget);
      expect(key.currentState!.planned, isEmpty);
    },
  );

  testWidgets(
    'Live renders the actual geometry, distance and unknown duration',
    (t) async {
      final key = await _mount(t);
      await _prepare(t);
      await _tap(t, _start);
      key.currentState!.publish(at: _position(), route: _route());
      await t.pumpAndSettle();
      final map = t.widget<DemoMap>(find.byType(DemoMap));
      expect(map.hasStart, isTrue);
      expect(map.path.map((p) => (p.lat, p.lng)), [
        (25.0478, 121.517),
        (25.05, 121.519),
      ]);
      expect(find.text('步行距離：326 公尺'), findsOneWidget);
      expect(find.text('預估時間：未知'), findsOneWidget);
      expect(find.text('路線來源：synthetic-foot-provider'), findsOneWidget);
      expect(find.text('限制：測試限制'), findsOneWidget);
      expect(find.textContaining('Google'), findsNothing);
    },
  );

  testWidgets(
    'failure and location error stay unavailable without Mock fallback',
    (t) async {
      final key = await _mount(t);
      await _prepare(t);
      await _tap(t, _start);
      key.currentState!.publish(error: '定位權限被拒絕');
      await t.pumpAndSettle();
      expect(find.text('定位權限被拒絕'), findsOneWidget);
      expect(t.widget<DemoMap>(find.byType(DemoMap)).hasStart, isFalse);
      expect(key.currentState!.planned, hasLength(1));
      await _tap(t, _start);
      key.currentState!.publish(
        route: sw.RouteFailure(
          requestId: 'failed-route',
          mode: sw.DataMode.live,
          generatedAt: DateTime.now().toUtc().toIso8601String(),
          status: sw.RouteFailureStatus.providerUnavailable,
          reason: '測試服務不可用',
          warnings: const ['測試失敗，不可導航'],
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('無法取得步行路線'), findsOneWidget);
      expect(find.text('測試服務不可用'), findsOneWidget);
      expect(t.widget<DemoMap>(find.byType(DemoMap)).path, isEmpty);
      expect(find.textContaining('示範路線'), findsNothing);
    },
  );

  testWidgets(
    'cancel, destination change and withdrawal hide late route results',
    (t) async {
      final key = await _mount(t);
      await _prepare(t);
      await _tap(t, _start);
      await _tap(t, find.byKey(const Key('safe-walk-live-cancel')));
      key.currentState!.publish(at: _position(), route: _route());
      await t.pumpAndSettle();
      expect(find.text('步行距離：326 公尺'), findsNothing);
      expect(t.widget<DemoMap>(find.byType(DemoMap)).path, isEmpty);
      t.widget<DemoMap>(find.byType(DemoMap)).onPick!(
        const LatLng(25.06, 121.53),
      );
      await t.pumpAndSettle();
      expect(key.currentState!.result, isNull);
      expect(key.currentState!.events.last, 'destination');
      await _tap(t, _start);
      key.currentState!.publish(
        at: _position(),
        route: _route(id: 'second-route'),
      );
      await t.pumpAndSettle();
      await _tap(t, find.byKey(const Key('safe-walk-routing-consent')));
      expect(find.text('步行距離：326 公尺'), findsNothing);
      expect(t.widget<SwPrimaryButton>(_start).onTap, isNull);
      expect(key.currentState!.planned, hasLength(2));
    },
  );

  testWidgets('background closes intent; resume never automatically plans', (
    t,
  ) async {
    final key = await _mount(t);
    await _prepare(t);
    await _tap(t, _start);
    key.currentState!.publish(at: _position(), route: _route());
    await t.pumpAndSettle();
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pumpAndSettle();
    expect(key.currentState!.events.last, 'closed');
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(key.currentState!.planned, hasLength(1));
    expect(find.textContaining('步行預覽已暫停'), findsOneWidget);
    expect(t.widget<DemoMap>(find.byType(DemoMap)).path, isEmpty);
  });

  testWidgets('Flow closes map before call and cancels immediately on SOS', (
    t,
  ) async {
    final key = await _mount(t, flow: true);
    await _tap(t, find.text('安心行'));
    expect(find.byType(SafeWalkLiveMapView), findsOneWidget);
    expect(key.currentState!.planned, isEmpty);
    await t.tap(find.text('模擬來電'));
    expect(key.currentState!.events.last, 'closed');
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(SafeWalkCallView), findsOneWidget);
    await t.tap(find.text('緊急求助').last);
    expect(key.currentState!.events.last, 'emergency');
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(SafeWalkEmergencyView), findsOneWidget);
  });

  testWidgets(
    'Live points/report and absent SMS sender explicitly stay unconfigured',
    (t) async {
      await _mount(t, flow: true);
      await _tap(t, find.text('附近求助地點'));
      expect(find.text('附近求助地點 尚未配置'), findsOneWidget);
      await _tap(t, find.bySemanticsLabel('返回'));
      await _tap(t, find.text('回報狀況'));
      expect(find.text('回報狀況 尚未配置'), findsOneWidget);
      await _tap(t, find.text('緊急求助').first);
      expect(find.text('簡訊求助尚未配置'), findsOneWidget);
      expect(find.text('傳送簡訊'), findsNothing);
      expect(find.textContaining('示範完成'), findsNothing);
    },
  );

  testWidgets(
    'SOS successful position and its status are cleared on background',
    (t) async {
      await _mount(
        t,
        flow: true,
        onLocate: () async => sw.LocationSuccess(position: _position()),
      );
      await _tap(t, find.text('緊急求助').first);
      await _tap(t, find.text('取得目前位置'));
      expect(find.text('已取得位置；尚未傳送給任何人。'), findsOneWidget);
      expect(find.textContaining('已取得位置：'), findsOneWidget);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      expect(find.text('已取得位置；尚未傳送給任何人。'), findsNothing);
      expect(find.textContaining('已取得位置：'), findsNothing);
      expect(find.text('還沒有位置。可以說出附近的路名、店名或明顯地標。'), findsOneWidget);
      expect(find.text('取得目前位置'), findsOneWidget);
    },
  );

  for (final background in [false, true]) {
    testWidgets(
      'SOS late location is discarded after ${background ? 'background' : 'leaving'}',
      (t) async {
        final pending = Completer<sw.LocationResult>();
        final key = await _mount(t, flow: true, onLocate: () => pending.future);
        await _tap(t, find.text('緊急求助').first);
        await _tap(t, find.text('取得目前位置'));
        if (background) {
          t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
          await t.pump();
        } else {
          await t.tap(find.text('我現在安全，關閉'));
          await t.pump(const Duration(milliseconds: 400));
        }
        expect(key.currentState!.events.last, 'closed');
        pending.complete(sw.LocationSuccess(position: _position()));
        await t.pump(const Duration(milliseconds: 400));
        if (background) {
          t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          await t.pumpAndSettle();
        } else {
          await _tap(t, find.text('緊急求助').first);
        }
        expect(find.textContaining('已取得位置：'), findsNothing);
        expect(find.textContaining('已取得位置；'), findsNothing);
        expect(t.takeException(), isNull);
      },
    );
  }

  for (final (width, height, scale) in [
    (320.0, 844.0, 1.0),
    (375.0, 844.0, 1.0),
    (390.0, 844.0, 1.0),
    (393.0, 844.0, 1.0),
    (430.0, 844.0, 1.0),
    (844.0, 390.0, 1.0),
    (1280.0, 800.0, 1.0),
    (390.0, 844.0, 2.0),
    (320.0, 844.0, 2.0),
  ]) {
    testWidgets(
      'Live form scrolls at $width px / ${scale * 100}% and keyboard',
      (t) async {
        await _mount(t, width: width, height: height, scale: scale);
        await _prepare(t);
        await t.ensureVisible(
          find.byKey(const Key('safe-walk-destination-lng')),
        );
        await t.tap(find.byKey(const Key('safe-walk-destination-lng')));
        t.view.viewInsets = const FakeViewPadding(bottom: 300);
        await t.pumpAndSettle();
        await t.ensureVisible(_start);
        await t.pumpAndSettle();
        expect(t.getRect(_start).bottom, lessThanOrEqualTo(height - 300));
        expect(find.text('緊急求助'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  }
}

extension<T> on Iterable<T> {
  Iterable<T> takeLast(int count) => skip(length - count);
}
