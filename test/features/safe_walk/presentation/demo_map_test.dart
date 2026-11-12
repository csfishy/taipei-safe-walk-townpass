import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:town_pass/features/safe_walk/presentation/safe_walk_map.dart';
import '../../../support/safe_walk_fixtures.dart';

import '../../../support/fake_map_tile_provider.dart';

Future<void> showMap(
  WidgetTester tester, {
  Size size = const Size(320, 400),
  bool compact = false,
  List<LatLng>? path,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox.fromSize(
            size: size,
            child: SafeWalkMap(
              start: DemoGeo.start,
              points: const [],
              anomalies: const [],
              path: path ?? DemoGeo.homeRoute,
              compact: compact,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(
    tester.widget<TileLayer>(find.byType(TileLayer)).tileProvider,
    isA<FakeMapTileProvider>(),
  );
}

void main() {
  const launcher = MethodChannel('plugins.flutter.io/url_launcher');
  test('production tiles retain the built-in HTTP cache', () async {
    final previous = SafeWalkMap.tileProviderFactoryForTesting;
    SafeWalkMap.tileProviderFactoryForTesting = null;
    final provider = SafeWalkMap.createTileProvider();
    try {
      expect(provider, isA<NetworkTileProvider>());
      expect((provider as NetworkTileProvider).cachingProvider, isNull);
    } finally {
      provider.dispose();
      SafeWalkMap.tileProviderFactoryForTesting = previous;
    }
  });

  for (final compact in [false, true]) {
    testWidgets('map attribution stays actionable (compact=$compact)', (
      tester,
    ) async {
      await showMap(
        tester,
        compact: compact,
        size: compact ? const Size(84, 84) : const Size(320, 400),
      );

      expect(find.text('© OpenStreetMap contributors · Protomaps'), findsOneWidget);
      expect(find.bySemanticsLabel('OpenStreetMap 地圖來源與授權'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('short map viewport still shows the local area', (tester) async {
    await showMap(tester, size: const Size(320, 140));
    final camera = MapCamera.of(tester.element(find.byType(MarkerLayer)));

    expect(camera.zoom, greaterThan(10));
    expect(
      camera.visibleBounds.contains(
        ll.LatLng(DemoGeo.start.lat, DemoGeo.start.lng),
      ),
      isTrue,
    );
    final start = tester.getRect(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_StartMark',
      ),
    );
    final attribution = tester.getRect(
      find.bySemanticsLabel('OpenStreetMap 地圖來源與授權'),
    );
    expect(start.bottom, lessThanOrEqualTo(attribution.top));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('changing a saved destination fits both route endpoints', (
    tester,
  ) async {
    await showMap(tester);
    const destination = LatLng(25.08, 121.56);
    await showMap(tester, path: DemoGeo.lRoute(DemoGeo.start, destination));
    final camera = MapCamera.of(tester.element(find.byType(MarkerLayer)));

    expect(
      camera.visibleBounds.contains(
        ll.LatLng(destination.lat, destination.lng),
      ),
      isTrue,
    );
    expect(
      camera.visibleBounds.contains(
        ll.LatLng(DemoGeo.start.lat, DemoGeo.start.lng),
      ),
      isTrue,
    );
    await showMap(tester);
    final homeCamera = MapCamera.of(tester.element(find.byType(MarkerLayer)));
    expect(homeCamera.zoom, greaterThan(10));
    expect(
      homeCamera.visibleBounds.contains(
        ll.LatLng(DemoGeo.home.lat, DemoGeo.home.lng),
      ),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('same route values preserve the user camera', (tester) async {
    await showMap(tester);
    final controller = MapController.of(
      tester.element(find.byType(MarkerLayer)),
    );
    const center = ll.LatLng(25.0008, 121.5004);
    controller.move(center, 16);
    await tester.pump();
    await showMap(tester, path: [...DemoGeo.homeRoute]);
    final camera = MapCamera.of(tester.element(find.byType(MarkerLayer)));

    expect(camera.zoom, 16);
    expect(camera.center.latitude, closeTo(center.latitude, 1e-9));
    expect(camera.center.longitude, closeTo(center.longitude, 1e-9));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final failure in <Object?>[
    null,
    false,
    PlatformException(code: 'unavailable'),
  ]) {
    testWidgets('attribution launcher handles $failure', (tester) async {
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(launcher, (call) async {
        calls.add(call);
        if (failure is PlatformException) throw failure;
        return failure ?? true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(launcher, null));
      await showMap(tester);

      await tester.tap(find.bySemanticsLabel('OpenStreetMap 地圖來源與授權'));
      await tester.pumpAndSettle();

      expect(calls.single.method, 'launch');
      expect(
        (calls.single.arguments as Map)['url'],
        'https://www.openstreetmap.org/copyright',
      );
      if (failure != null) {
        expect(find.textContaining('無法開啟授權說明'), findsOneWidget);
      } else {
        expect(find.textContaining('無法開啟授權說明'), findsNothing);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
