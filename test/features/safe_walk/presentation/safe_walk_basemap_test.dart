import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_basemap.dart';

import '../../../support/fake_map_tile_provider.dart';

void main() {
  tearDown(() {
    SafeWalkBasemap.offlineLoaderForTesting = null;
    SafeWalkBasemap.isWebForTesting = null;
  });

  Future<void> showMap(
    WidgetTester tester, {
    LatLng center = const LatLng(25.04, 121.53),
    TileProvider Function()? online,
  }) => tester.pumpWidget(
    MaterialApp(
      home: FlutterMap(
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
    expect(find.text('local tiles'), findsNothing);
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
