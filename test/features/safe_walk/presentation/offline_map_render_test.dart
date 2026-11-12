import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mbtiles/mbtiles.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_map_tiles_mbtiles/vector_map_tiles_mbtiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vector;
import 'package:town_pass/features/safe_walk/presentation/offline_map_file_io.dart';
import 'package:town_pass/features/safe_walk/presentation/offline_basemap_loader_io.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_basemap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real native builder displays z17 overzoom without online tiles',
    (tester) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('safe-walk-native-map'),
      ))!;
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => directory.path,
      );
      SafeWalkBasemap.isWebForTesting = false;
      var onlineCalls = 0;
      final boundary = GlobalKey();
      try {
        await tester.runAsync(() async {
          final font = FontLoader('SafeWalkNotoTC')
            ..addFont(
              File('assets/safe_walk/map/NotoSansCJKtc-Regular.otf')
                  .readAsBytes()
                  .then(ByteData.sublistView),
            );
          await font.load();
        });
        final data = await tester.runAsync(loadOfflineBasemap);
        SafeWalkBasemap.offlineLoaderForTesting = () async => data!;
        await tester.pumpWidget(
          MaterialApp(
            home: RepaintBoundary(
              key: boundary,
              child: FlutterMap(
                options: const MapOptions(
                  initialCenter: LatLng(25.047, 121.517),
                  initialZoom: 17,
                ),
                children: [
                  SafeWalkBasemap(
                    onlineProvider: () {
                      onlineCalls++;
                      throw StateError('unexpected network');
                    },
                  ),
                ],
              ),
            ),
          ),
        );
        for (var i = 0; i < 60; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.byType(VectorTileLayer), findsOneWidget);
        expect(find.byType(TileLayer), findsNothing);
        expect(onlineCalls, 0);
        expect(tester.takeException(), isNull);
        if (Platform.environment['SAVE_BASEMAP_PREVIEW'] == '1') {
          final image = (await tester.runAsync(
            () =>
                (boundary.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage(),
          ))!;
          final png = await tester.runAsync(
            () => image.toByteData(format: ui.ImageByteFormat.png),
          );
          await tester.runAsync(() async {
            await Directory('artifacts/offline_map').create(recursive: true);
            await File('artifacts/offline_map/native-z17.png')
                .writeAsBytes(png!.buffer.asUint8List());
          });
          image.dispose();
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      } finally {
        SafeWalkBasemap.offlineLoaderForTesting = null;
        SafeWalkBasemap.isWebForTesting = null;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
        await tester.runAsync(() => directory.delete(recursive: true));
      }
    },
  );
  test('real bundled asset installs and validates its warm copy', () async {
    final directory = await Directory.systemTemp.createTemp(
      'safe-walk-real-map',
    );
    try {
      final timer = Stopwatch()..start();
      final path = await installOfflineMapFile(
        supportDirectory: () async => directory,
      );
      final cold = timer.elapsedMicroseconds / 1000;
      timer.reset();
      expect(
        await installOfflineMapFile(supportDirectory: () async => directory),
        path,
      );
      final warm = timer.elapsedMicroseconds / 1000;
      expect(await File(path).length(), 26607616);
      // ignore: avoid_print
      print(
        'Real 26.6 MB asset SHA/copy/rename: $cold ms; warm SHA: $warm ms (Windows)',
      );
    } finally {
      await directory.delete(recursive: true);
    }
  });
  test('real Taipei archive decodes and renders Traditional Chinese streets offline', () async {
    final watch = Stopwatch()..start();
    final database = MbTiles(path: 'assets/safe_walk/map/taipei.mbtiles');
    try {
      final provider = MbTilesVectorTileProvider(mbtiles: database);
      final style = jsonDecode(
        await File('assets/safe_walk/map/style.json').readAsString(),
      ) as Map<String, dynamic>;
      final theme = vector.ThemeReader().read(style);
      final font = FontLoader('SafeWalkNotoTC')
        ..addFont(
          File('assets/safe_walk/map/NotoSansCJKtc-Regular.otf')
              .readAsBytes()
              .then(ByteData.sublistView),
        );
      await font.load();
      final layers = <String>{};
      final names = StringBuffer();
      for (final zoom in [12, 15]) {
        final x = ((121.517 / 360 + .5) * (1 << zoom)).floor();
        final radians = 25.047 * math.pi / 180;
        final y =
            ((1 -
                        math.log(math.tan(radians) + 1 / math.cos(radians)) /
                            math.pi) /
                    2 *
                    (1 << zoom))
                .floor();
        final bytes = await provider.provide(TileIdentity(zoom, x, y));
        final raw = vector.VectorTile.fromBytes(bytes: bytes);
        layers.addAll(raw.layers.map((layer) => layer.name));
        names.write(utf8.decode(bytes, allowMalformed: true));
        final tile = vector.TileFactory(
          theme,
          const vector.Logger.noop(),
        ).create(raw);
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder)..scale(2);
        vector.Renderer(theme: theme).render(
          canvas,
          vector.TileSource(tileset: vector.Tileset({'protomaps': tile})),
          zoomScaleFactor: 1,
          zoom: zoom.toDouble(),
          rotation: 0,
        );
        final image = await recorder.endRecording().toImage(512, 512);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        expect(png!.lengthInBytes, greaterThan(10000));
        if (Platform.environment['SAVE_BASEMAP_PREVIEW'] == '1') {
          await Directory('artifacts/offline_map').create(recursive: true);
          await File('artifacts/offline_map/taipei-z$zoom.png')
              .writeAsBytes(png.buffer.asUint8List());
        }
        image.dispose();
      }
      expect(
        layers,
        containsAll(['roads', 'buildings', 'water', 'landuse', 'pois']),
      );
      expect(RegExp(r'[\u4e00-\u9fff]{2,}').hasMatch(names.toString()), isTrue);
      // This is a Windows renderer check, not an iPhone/Android acceptance claim.
      // ignore: avoid_print
      print(
        'Real archive open + z12/z15 decode/render: ${watch.elapsedMilliseconds} ms (Windows test engine)',
      );
    } finally {
      database.close();
    }
  });
}
