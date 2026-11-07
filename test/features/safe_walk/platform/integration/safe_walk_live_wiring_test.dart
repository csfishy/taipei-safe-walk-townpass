import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/navigation/json_transport.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_composition_root.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_route_speaker.dart';
import 'package:town_pass/features/safe_walk/platform/platform_service.dart';
import 'package:town_pass/features/safe_walk/presentation/demo_map.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_flow.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_ui.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/safe_walk_navigation_scope.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

import '../../../../support/fake_map_tile_provider.dart';

// Real composition, DefaultRouteService and OSRM parser; only native location
// and HTTP are fakes. All coordinates are synthetic, with no GPS or network use.
final _origin = sw.Coordinates(lat: 25, lng: 121.5);
final _destination = sw.Coordinates(lat: 25.001, lng: 121.501);
final _otherDestination = sw.Coordinates(lat: 25.002, lng: 121.502);

void main() {
  testWidgets(
    'UI destination and consent controls render the real provider geometry',
    (tester) async {
      final platform = _Platform();
      final transport = _Transport();
      await _mount(tester, platform, transport);
      await tester.tap(find.text('安心行').first);
      await tester.pumpAndSettle();
      final before = tester.widget<DemoMap>(find.byType(DemoMap));
      expect(before.liveRendering, isTrue);
      expect(before.hasStart, isFalse);
      expect(before.path, isEmpty);
      expect(
        tester.widget<TileLayer>(find.byType(TileLayer)).tileProvider,
        isA<FakeMapTileProvider>(),
      );

      await _showControl(
        tester,
        find.byKey(const Key('safe-walk-destination-lat')),
      );
      await tester.enterText(
        find.byKey(const Key('safe-walk-destination-lat')),
        '${_destination.lat}',
      );
      await _showControl(
        tester,
        find.byKey(const Key('safe-walk-destination-lng')),
      );
      await tester.enterText(
        find.byKey(const Key('safe-walk-destination-lng')),
        '${_destination.lng}',
      );
      await _showControl(tester, find.widgetWithText(SwPrimaryButton, '設定目的地'));
      tester
          .widget<SwPrimaryButton>(
            find.widgetWithText(SwPrimaryButton, '設定目的地'),
          )
          .onTap!();
      await tester.pump();
      for (final key in [
        'safe-walk-location-consent',
        'safe-walk-routing-consent',
      ]) {
        await _showControl(tester, find.byKey(Key(key)));
        tester.widget<CheckboxListTile>(find.byKey(Key(key))).onChanged!(true);
        await tester.pump();
      }
      expect(platform.calls, isEmpty);
      expect(transport.calls, isEmpty);
      await _showControl(tester, find.byKey(const Key('safe-walk-live-start')));
      tester
          .widget<SwPrimaryButton>(
            find.byKey(const Key('safe-walk-live-start')),
          )
          .onTap!();
      await tester.pump();
      expect(platform.calls, hasLength(1));
      expect(transport.calls, hasLength(1));
      transport.calls.single.result.complete(_response(_destination));
      await tester.pumpAndSettle();
      await _showControl(tester, find.byType(DemoMap), backwards: true);
      final map = tester.widget<DemoMap>(find.byType(DemoMap));
      final expected = [
        for (final c in _geometry(_destination)) [c.longitude, c.latitude],
      ];
      expect(map.liveRendering, isTrue);
      expect(map.hasStart, isTrue);
      expect([map.start.lng, map.start.lat], [_origin.lng, _origin.lat]);
      expect([
        for (final at in map.path) [at.lng, at.lat],
      ], expected);
      final polyline = tester.widget<PolylineLayer>(
        find.byWidgetPredicate((widget) => widget is PolylineLayer),
      );
      expect([
        for (final at in polyline.polylines.single.points)
          [at.longitude, at.latitude],
      ], expected);
      expect(platform.emergencies, 0);
      await _unmount(tester);
    },
    skip: kIsWeb,
  );

  testWidgets(
    'Live composition needs both consents and an explicit plan action',
    (tester) async {
      final platform = _Platform();
      final transport = _Transport();
      await _mount(tester, platform, transport);
      expect(_scope(tester).mode, sw.DataMode.live);
      expect(platform.calls, isEmpty);
      expect(transport.calls, isEmpty);
      expect(
        tester.widget<SafeWalkFlow>(find.byType(SafeWalkFlow)).points,
        isEmpty,
      );

      _scope(tester).onNavigationOpened();
      await _scope(tester).onPlanDestination!(_destination);
      expect(platform.calls, isEmpty);
      _scope(tester).onLocationConsentChanged!(true);
      await _scope(tester).onPlanDestination!(_destination);
      expect(platform.calls, isEmpty);
      _scope(tester).onLocationConsentChanged!(false);
      _scope(tester).onRoutingConsentChanged(true);
      await _scope(tester).onPlanDestination!(_destination);
      expect(platform.calls, isEmpty);
      _scope(tester).onLocationConsentChanged!(true);
      await tester.pump();
      expect(transport.calls, isEmpty);

      // Revocation above deactivated the old intent. Explicitly start a new one.
      _scope(tester).onNavigationOpened();
      final planned = _scope(tester).onPlanDestination!(_destination);
      await tester.pump();
      expect(platform.calls, hasLength(1));
      expect(platform.calls.single.mode, sw.DataMode.live);
      expect(platform.calls.single.userInitiated, isTrue);
      expect(transport.calls, hasLength(1));
      expect(transport.calls.single.url.host, 'routing.openstreetmap.de');
      expect(
        transport.calls.single.url.path,
        '/routed-foot/route/v1/driving/121.500000,25.000000;121.501000,25.001000',
      );
      transport.calls.single.result.complete(_response(_destination));
      await planned;
      await tester.pump();

      final result = _scope(tester).routeResult! as sw.RouteSuccess;
      expect(result.mode, sw.DataMode.live);
      expect(sw.RouteResult.fromJson(result.toJson()), isA<sw.RouteSuccess>());
      expect(
        result.routes.single.geometry.coordinates,
        _geometry(_destination),
      );
      expect(result.routes.single.distanceMeters, 720);
      expect(result.routes.single.durationSeconds, 600);
      expect(result.routes.single.walkingNetworkVerified, isTrue);
      expect(result.routes.single.provider, startsWith('osrm-foot'));
      expect(result.routes.single.warnings, isNotEmpty);
      final flow = tester.widget<SafeWalkFlow>(find.byType(SafeWalkFlow));
      expect(flow.route, same(result));
      expect(flow.allowRealCalls, isFalse);
      expect(platform.emergencies, 0);
      await _unmount(tester);
    },
    skip: kIsWeb,
  );

  testWidgets(
    'Live cannot bypass the coordinator with a caller-supplied origin',
    (tester) async {
      final platform = _Platform();
      final transport = _Transport();
      await _mount(tester, platform, transport);
      await _openConsented(tester);
      final request = _scope(tester)
          .createRouteRequest(origin: _gps(), destination: _destination);
      await expectLater(_scope(tester).onPlanRoute(request), throwsStateError);
      expect(platform.calls, isEmpty);
      expect(transport.calls, isEmpty);
      await _unmount(tester);
    },
    skip: kIsWeb,
  );

  testWidgets(
    'destination changes reject late GPS and preserve the new selection',
    (tester) async {
      final platform = _Platform()..holdLocation = true;
      final transport = _Transport();
      await _mount(tester, platform, transport);
      await _openConsented(tester);
      final first = _scope(tester).onPlanDestination!(_destination);
      await tester.pump();
      _scope(tester).onDestinationChanged();
      final latest = _scope(tester).onPlanDestination!(_otherDestination);
      await tester.pump();
      expect(platform.calls, hasLength(2));
      expect(platform.calls.first.cancellation.isCancelled, isTrue);
      platform.calls.first.result.complete(
        sw.LocationSuccess(position: _gps()),
      );
      await tester.pump();
      expect(transport.calls, isEmpty);
      platform.calls.last.result.complete(sw.LocationSuccess(position: _gps()));
      await tester.pump();
      expect(transport.calls, hasLength(1));
      expect(
        transport.calls.single.url.path,
        endsWith(';121.502000,25.002000'),
      );
      transport.calls.single.result.complete(_response(_otherDestination));
      await Future.wait([first, latest]);
      await tester.pump();
      expect(
        (_scope(tester).routeResult! as sw.RouteSuccess)
            .routes
            .single
            .geometry
            .coordinates
            .last,
        (longitude: _otherDestination.lng, latitude: _otherDestination.lat),
      );
      await _unmount(tester);
    },
    skip: kIsWeb,
  );

  testWidgets('an old HTTP route cannot replace the new destination result', (
    tester,
  ) async {
    final platform = _Platform();
    final transport = _Transport();
    await _mount(tester, platform, transport);
    await _openConsented(tester);
    final old = _scope(tester).onPlanDestination!(_destination);
    await tester.pump();
    _scope(tester).onDestinationChanged();
    final latest = _scope(tester).onPlanDestination!(_otherDestination);
    await tester.pump();
    expect(transport.calls, hasLength(2));
    expect(transport.calls.first.cancellation!.isCancelled, isTrue);
    transport.calls.last.result.complete(_response(_otherDestination));
    await latest;
    await tester.pump();
    final result = _scope(tester).routeResult;
    transport.calls.first.result.complete(_response(_destination));
    await old;
    await tester.pump();
    expect(_scope(tester).routeResult, same(result));
    expect(
      (result! as sw.RouteSuccess).routes.single.geometry.coordinates.last,
      (longitude: _otherDestination.lng, latitude: _otherDestination.lat),
    );
    await _unmount(tester);
  }, skip: kIsWeb);

  for (final interruption in [
    'location consent',
    'routing consent',
    'background',
    'SOS',
    'close',
  ]) {
    for (final phase in ['GPS', 'HTTP']) {
      testWidgets(
        '$interruption during $phase drops late work and does not auto-resume',
        (tester) async {
          final platform = _Platform()..holdLocation = phase == 'GPS';
          final transport = _Transport();
          final speaker = _Speaker();
          await _mount(tester, platform, transport, speaker: speaker);
          await _openConsented(tester);
          final pending = _scope(tester).onPlanDestination!(_destination);
          await tester.pump();
          expect(platform.calls, hasLength(1));
          expect(transport.calls.length, phase == 'HTTP' ? 1 : 0);
          switch (interruption) {
            case 'location consent':
              _scope(tester).onLocationConsentChanged!(false);
            case 'routing consent':
              _scope(tester).onRoutingConsentChanged(false);
            case 'background':
              tester.binding.handleAppLifecycleStateChanged(
                AppLifecycleState.paused,
              );
              // Paused apps do not rebuild their inherited widget snapshot.
              // Verify synchronous cancellation, then resume to inspect the
              // rebuilt Scope. Resuming must not reactivate the old intent.
              expect(platform.calls.single.cancellation.isCancelled, isTrue);
              if (phase == 'HTTP') {
                expect(
                  transport.calls.single.cancellation!.isCancelled,
                  isTrue,
                );
              }
              tester.binding.handleAppLifecycleStateChanged(
                AppLifecycleState.resumed,
              );
            case 'SOS':
              _scope(tester).onEmergencyOpened();
            case 'close':
              _scope(tester).onNavigationClosed();
          }
          await tester.pump();
          expect(_scope(tester).position, isNull);
          expect(_scope(tester).routeResult, isNull);
          expect(_scope(tester).locationLoading, isFalse);
          expect(_scope(tester).routeLoading, isFalse);
          if (phase == 'GPS') {
            expect(platform.calls.single.cancellation.isCancelled, isTrue);
            platform.calls.single.result.complete(
              sw.LocationSuccess(position: _gps()),
            );
          } else {
            expect(transport.calls.single.cancellation!.isCancelled, isTrue);
            transport.calls.single.result.complete(_response(_destination));
          }
          await pending;
          await tester.pump();
          _scope(tester).onLocationConsentChanged!(true);
          _scope(tester).onRoutingConsentChanged(true);
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pump();
          await _scope(tester).onPlanDestination!(_destination);
          await tester.pump();
          expect(
            platform.calls,
            hasLength(1),
            reason: 'another explicit start is required',
          );
          expect(transport.calls.length, phase == 'HTTP' ? 1 : 0);
          expect(_scope(tester).routeResult, isNull);
          expect(platform.emergencies, 0);
          if (interruption == 'SOS') expect(speaker.emergencyStops, 1);
          await _unmount(tester);
        },
        skip: kIsWeb,
      );
    }
  }

  testWidgets(
    'provider failure remains Live failure and explicit retry can succeed',
    (tester) async {
      final platform = _Platform();
      final transport = _Transport();
      await _mount(tester, platform, transport);
      await _openConsented(tester);
      final failed = _scope(tester).onPlanDestination!(_destination);
      await tester.pump();
      transport.calls.single.result.completeError(
        const JsonTransportException(TransportFailure.timeout),
      );
      await failed;
      await tester.pump();
      final failure = _scope(tester).routeResult! as sw.RouteFailure;
      expect(failure.mode, sw.DataMode.live);
      expect(failure.status, sw.RouteFailureStatus.providerUnavailable);
      expect(failure.routes, isEmpty);
      expect(_scope(tester).routeError, isNotEmpty);
      final retried = _scope(tester).onPlanDestination!(_destination);
      await tester.pump();
      expect(platform.calls, hasLength(2));
      transport.calls.last.result.complete(_response(_destination));
      await retried;
      await tester.pump();
      expect(_scope(tester).routeResult, isA<sw.RouteSuccess>());
      expect(_scope(tester).routeError, isNull);
      await _unmount(tester);
    },
    skip: kIsWeb,
  );

  testWidgets('disposing a route ignores a late provider response', (
    tester,
  ) async {
    final platform = _Platform();
    final transport = _Transport();
    await _mount(tester, platform, transport);
    await _openConsented(tester);
    final pending = _scope(tester).onPlanDestination!(_destination);
    await tester.pump();
    await _unmount(tester);
    expect(transport.calls.single.cancellation!.isCancelled, isTrue);
    transport.calls.single.result.complete(_response(_destination));
    await pending;
    await tester.pump();
    expect(find.byType(SafeWalkFlow), findsNothing);
    expect(tester.takeException(), isNull);
  }, skip: kIsWeb);

  testWidgets('Web Live composition stays unavailable without GPS or OSRM', (
    tester,
  ) async {
    final platform = _Platform();
    final transport = _Transport();
    await _mount(tester, platform, transport);
    await _openConsented(tester);
    expect(_scope(tester).mode, sw.DataMode.live);
    expect(_scope(tester).liveNavigationAvailable, isFalse);
    await _scope(tester).onPlanDestination!(_destination);
    await tester.pump();
    expect(platform.calls, isEmpty);
    expect(transport.calls, isEmpty);
    expect(_scope(tester).locationError, isNotEmpty);
    expect(_scope(tester).routeResult, isNull);
    await _unmount(tester);
  }, skip: !kIsWeb);
}

SafeWalkNavigationScope _scope(WidgetTester tester) => tester
    .element(find.byType(SafeWalkFlow))
    .getInheritedWidgetOfExactType<SafeWalkNavigationScope>()!;

Future<void> _mount(
  WidgetTester tester,
  _Platform platform,
  _Transport transport, {
  _Speaker? speaker,
}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(
    MaterialApp(
      home: SafeWalkCompositionRoot(
        platform: platform,
        routeTransport: transport,
        speaker: speaker ?? _Speaker(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openConsented(WidgetTester tester) async {
  _scope(tester).onLocationConsentChanged!(true);
  _scope(tester).onRoutingConsentChanged(true);
  _scope(tester).onNavigationOpened();
  await tester.pump();
}

Future<void> _showControl(
  WidgetTester tester,
  Finder finder, {
  bool backwards = false,
}) async {
  final scrollable = find
      .descendant(
        of: find.byKey(const Key('safe-walk-live-map-list')),
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(
    finder,
    backwards ? -160 : 160,
    scrollable: scrollable,
  );
  await tester.pumpAndSettle();
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  expect(tester.takeException(), isNull);
}

sw.Position _gps() => sw.Position(
  coordinates: _origin,
  source: sw.PositionSource.gps,
  accuracyMeters: 5,
  observedAt: DateTime.now().toUtc().toIso8601String(),
);

List<sw.GeoJsonCoordinate> _geometry(sw.Coordinates destination) => [
  (longitude: _origin.lng, latitude: _origin.lat),
  (longitude: 121.5003, latitude: 25.0002),
  (longitude: destination.lng, latitude: destination.lat),
];

Map<String, Object?> _response(sw.Coordinates destination) => {
  'code': 'Ok',
  'routes': [
    {
      'distance': 720,
      'duration': 600,
      'geometry': {
        'type': 'LineString',
        'coordinates': [
          for (final coordinate in _geometry(destination))
            [coordinate.longitude, coordinate.latitude],
        ],
      },
    },
  ],
};

final class _Platform implements PlatformService {
  bool holdLocation = false;
  int emergencies = 0;
  final calls =
      <
        ({
          sw.DataMode mode,
          bool userInitiated,
          SafeWalkCancellation cancellation,
          Completer<sw.LocationResult> result,
        })
      >[];

  @override
  Future<sw.LocationResult> getCurrentPosition({
    required sw.DataMode mode,
    required bool userInitiated,
    SafeWalkCancellation? cancellation,
  }) {
    final result = Completer<sw.LocationResult>();
    calls.add((
      mode: mode,
      userInitiated: userInitiated,
      cancellation: cancellation!,
      result: result,
    ));
    if (!holdLocation) result.complete(sw.LocationSuccess(position: _gps()));
    return result.future;
  }

  @override
  Future<sw.EmergencyActionResult> requestEmergency({
    required sw.DataMode mode,
    required sw.EmergencyChannel channel,
    required bool userInitiated,
    required bool allowRealCalls,
    sw.IncidentSummary? summary,
  }) async {
    emergencies++;
    throw StateError('This test must never request a real emergency handoff');
  }
}

final class _Transport implements JsonTransport {
  final calls =
      <
        ({
          Uri url,
          SafeWalkCancellation? cancellation,
          Completer<Object?> result,
        })
      >[];
  @override
  Future<Object?> getJson(Uri url, {SafeWalkCancellation? cancellation}) {
    final result = Completer<Object?>();
    calls.add((url: url, cancellation: cancellation, result: result));
    return result.future;
  }

  @override
  Future<Object?> postFormJson(
    Uri url,
    Map<String, String> form, {
    SafeWalkCancellation? cancellation,
  }) => throw StateError('OSRM direct routes use GET only');
}

final class _Speaker implements SafeWalkRouteSpeaker {
  int emergencyStops = 0;
  @override
  bool get available => false;
  @override
  void speak(String text, {void Function()? onDone}) =>
      throw StateError('No TTS is used by wiring tests');
  @override
  void stop() {}
  @override
  void setLifecycleActive(bool active) {}
  @override
  Future<void> stopForEmergency() async {
    emergencyStops++;
  }

  @override
  Future<void> dispose() async {}
}
