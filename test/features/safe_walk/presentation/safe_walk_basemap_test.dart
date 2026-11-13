import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_basemap.dart';

import '../../../support/fake_map_tile_provider.dart';

class _TrackedLayer extends StatefulWidget {
  const _TrackedLayer(this.started, this.stopped);
  final VoidCallback started, stopped;
  @override
  State<_TrackedLayer> createState() => _TrackedLayerState();
}

class _TrackedLayerState extends State<_TrackedLayer> {
  @override
  void initState() {
    super.initState();
    widget.started();
  }

  @override
  void dispose() {
    widget.stopped();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.green);
}

void main() {
  tearDown(() {
    SafeWalkBasemap.offlineLoaderForTesting = null;
    SafeWalkBasemap.isWebForTesting = null;
  });

  Future<void> showMap(
    WidgetTester tester, {
    LatLng center = const LatLng(25.04, 121.53),
    TileProvider Function()? online,
    MapController? controller,
  }) => tester.pumpWidget(
    MaterialApp(
      home: FlutterMap(
        mapController: controller,
        options: MapOptions(initialCenter: center, initialZoom: 15),
        children: [
          SafeWalkBasemap(onlineProvider: online ?? FakeMapTileProvider.new),
        ],
      ),
    ),
  );

  test('inclusive bbox and outside coordinates', () {
    expect(isInOfflineMapBounds(24.95, 121.44), isTrue);
    expect(isInOfflineMapBounds(25.22, 121.68), isTrue);
    expect(isInOfflineMapBounds(24.949, 121.53), isFalse);
    expect(isInOfflineMapBounds(25.04, 121.681), isFalse);
  });

  test('resource release is idempotent', () async {
    var calls = 0;
    final resource = OfflineBasemap(
      layer: const SizedBox(),
      close: () async {
        calls++;
      },
    );
    final first = resource.close();
    expect(identical(first, resource.close()), isTrue);
    await first;
    expect(calls, 1);
  });

  testWidgets('cleanup errors after leaving do not escape', (tester) async {
    SafeWalkBasemap.isWebForTesting = false;
    SafeWalkBasemap.offlineLoaderForTesting = () async => OfflineBasemap(
      layer: const SizedBox(),
      close: () async => throw StateError('private file path'),
    );
    await showMap(tester);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('partial viewport coverage warns even with center inside', (
    tester,
  ) async {
    SafeWalkBasemap.isWebForTesting = false;
    SafeWalkBasemap.offlineLoaderForTesting = () async =>
        OfflineBasemap(layer: const Text('local tiles'), close: () async {});
    await showMap(tester, center: const LatLng(25.04, 121.679));
    await tester.pumpAndSettle();
    expect(find.text('部分畫面超出離線地圖範圍'), findsOneWidget);
  });

  testWidgets('online provider is reused across camera moves', (tester) async {
    SafeWalkBasemap.isWebForTesting = true;
    final controller = MapController();
    var created = 0;
    await showMap(
      tester,
      controller: controller,
      online: () {
        created++;
        return FakeMapTileProvider();
      },
    );
    await tester.pumpAndSettle();
    controller.move(const LatLng(25.05, 121.54), 15);
    await tester.pumpAndSettle();
    controller.move(const LatLng(25.06, 121.55), 15);
    await tester.pumpAndSettle();
    expect(created, 1);
  });

  testWidgets(
    'coverage clips rotated views and preserves layer across boundaries',
    (tester) async {
      SafeWalkBasemap.isWebForTesting = false;
      final controller = MapController();
      var started = 0, stopped = 0, network = 0;
      SafeWalkBasemap.offlineLoaderForTesting = () async => OfflineBasemap(
        layer: _TrackedLayer(() => started++, () => stopped++),
        close: () async {},
      );
      await showMap(
        tester,
        controller: controller,
        online: () {
          network++;
          return FakeMapTileProvider();
        },
      );
      await tester.pumpAndSettle();
      controller.move(const LatLng(25.04, 121.679), 15);
      controller.rotate(30);
      await tester.pumpAndSettle();
      final clipWidget = tester.widget<ClipPath>(
        find.byKey(const ValueKey('offline-map-coverage')),
      );
      final clipper = clipWidget.clipper! as OfflineMapBoundsClipper;
      final path = clipper.getClip(
        tester.getSize(find.byKey(const ValueKey('offline-map-coverage'))),
      );
      expect(
        path.contains(
          clipper.camera.latLngToScreenOffset(const LatLng(25.04, 121.679)),
        ),
        isTrue,
      );
      expect(
        path.contains(
          clipper.camera.latLngToScreenOffset(const LatLng(25.04, 121.681)),
        ),
        isFalse,
      );
      controller.move(const LatLng(25.04, 121.69), 15);
      await tester.pumpAndSettle();
      expect(find.text('離線地圖範圍外'), findsOneWidget);
      controller.move(const LatLng(25.04, 121.53), 15);
      await tester.pumpAndSettle();
      expect(started, 1);
      expect(stopped, 0);
      expect(network, 0);
      await tester.pumpWidget(const SizedBox());
      expect(stopped, 1);
    },
  );

  testWidgets('native loading and success never construct an online provider', (
    tester,
  ) async {
    SafeWalkBasemap.isWebForTesting = false;
    final pending = Completer<OfflineBasemap>();
    SafeWalkBasemap.offlineLoaderForTesting = () => pending.future;
    var requests = 0;
    var closed = false;
    await showMap(
      tester,
      online: () {
        requests++;
        return FakeMapTileProvider();
      },
    );
    expect(find.text('正在準備離線地圖…'), findsOneWidget);
    expect(find.byType(TileLayer), findsNothing);
    pending.complete(
      OfflineBasemap(
        layer: const Text('local tiles'),
        close: () async {
          closed = true;
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('local tiles'), findsOneWidget);
    expect(find.text('離線底圖：2026-11-11 快照'), findsOneWidget);
    expect(requests, 0);
    await tester.pumpWidget(const SizedBox());
    expect(closed, isTrue);
  });

  testWidgets('outside native coverage shows grey warning without network', (
    tester,
  ) async {
    SafeWalkBasemap.isWebForTesting = false;
    SafeWalkBasemap.offlineLoaderForTesting = () async =>
        OfflineBasemap(layer: const Text('local tiles'), close: () async {});
    await showMap(tester, center: const LatLng(24, 121));
    await tester.pumpAndSettle();
    expect(find.text('離線地圖範圍外'), findsOneWidget);
    final clip = tester.widget<ClipPath>(
      find.byKey(const ValueKey('offline-map-coverage')),
    );
    expect(
      clip.clipper!
          .getClip(const Size(800, 600))
          .contains(const Offset(400, 300)),
      isFalse,
    );
    expect(find.byType(TileLayer), findsNothing);
  });

  testWidgets('copy failure falls back to online with disclosure', (
    tester,
  ) async {
    SafeWalkBasemap.isWebForTesting = false;
    SafeWalkBasemap.offlineLoaderForTesting = () async =>
        throw StateError('copy failed');
    await showMap(tester);
    await tester.pumpAndSettle();
    expect(find.byType(TileLayer), findsOneWidget);
    expect(find.textContaining('離線地圖無法載入，已改用線上底圖'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed install can retry offline without reopening the screen', (
    tester,
  ) async {
    SafeWalkBasemap.isWebForTesting = false;
    var loads = 0;
    SafeWalkBasemap.offlineLoaderForTesting = () async {
      if (++loads == 1) throw StateError('copy failed');
      return OfflineBasemap(
        layer: const Text('recovered offline'),
        close: () async {},
      );
    };
    await showMap(tester);
    await tester.pumpAndSettle();
    expect(find.byType(TileLayer), findsOneWidget);
    await tester.tap(find.text('重試離線地圖'));
    await tester.pumpAndSettle();
    expect(find.text('recovered offline'), findsOneWidget);
    expect(find.byType(TileLayer), findsNothing);
    expect(loads, 2);
  });

  testWidgets('runtime reader error falls back, closes once and retries', (
    tester,
  ) async {
    SafeWalkBasemap.isWebForTesting = false;
    final failed = ValueNotifier(false);
    var loads = 0, closes = 0;
    SafeWalkBasemap.offlineLoaderForTesting = () async => OfflineBasemap(
      layer: Text('offline ${++loads}'),
      unavailable: loads == 1 ? failed : null,
      close: () async {
        closes++;
      },
    );
    await showMap(tester);
    await tester.pumpAndSettle();
    failed.value = true;
    await tester.pumpAndSettle();
    expect(find.byType(TileLayer), findsOneWidget);
    expect(closes, 1);
    await tester.tap(find.text('重試離線地圖'));
    await tester.pumpAndSettle();
    expect(find.text('offline 2'), findsOneWidget);
    expect(find.byType(TileLayer), findsNothing);
    await tester.pumpWidget(const SizedBox());
    expect(closes, 2);
    expect(tester.takeException(), isNull);
    failed.dispose();
  });

  testWidgets('Web remains online and never opens the offline file', (
    tester,
  ) async {
    SafeWalkBasemap.isWebForTesting = true;
    var opened = false;
    SafeWalkBasemap.offlineLoaderForTesting = () async {
      opened = true;
      throw StateError('must not open');
    };
    await showMap(tester);
    await tester.pumpAndSettle();
    expect(find.byType(TileLayer), findsOneWidget);
    expect(opened, isFalse);
  });

  testWidgets('late archive after leaving is closed', (tester) async {
    SafeWalkBasemap.isWebForTesting = false;
    final pending = Completer<OfflineBasemap>();
    SafeWalkBasemap.offlineLoaderForTesting = () => pending.future;
    await showMap(tester);
    await tester.pumpWidget(const SizedBox());
    var closed = false;
    pending.complete(
      OfflineBasemap(
        layer: const SizedBox(),
        close: () async {
          closed = true;
        },
      ),
    );
    await tester.pump();
    expect(closed, isTrue);
    expect(tester.takeException(), isNull);
  });
}
