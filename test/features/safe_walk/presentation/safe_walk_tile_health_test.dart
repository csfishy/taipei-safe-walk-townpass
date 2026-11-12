import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:town_pass/features/safe_walk/presentation/safe_walk_map.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_map_models.dart';

class _PendingImage extends ImageProvider<Object> {
  final result = Completer<ImageInfo>();
  bool cancelled = false;
  @override
  Future<Object> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(Object key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(result.future);
}

class _Tiles extends TileProvider {
  final pending = <_PendingImage>[];
  @override
  bool get supportsCancelLoading => true;
  @override
  ImageProvider<Object> getImageWithCancelLoadingSupport(
    TileCoordinates coordinates,
    TileLayer options,
    Future<void> cancelLoading,
  ) {
    final image = _PendingImage();
    cancelLoading.then((_) => image.cancelled = true);
    pending.add(image);
    return image;
  }
}

void main() {
  testWidgets(
    'three tile failures warn; later success hides warning and preserves overlays',
    (t) async {
      final tiles = _Tiles();
      SafeWalkMap.tileProviderFactoryForTesting = () => tiles;
      await t.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 800,
              child: SafeWalkMap(
                start: LatLng(25, 121.5),
                points: [],
                anomalies: [],
                path: [LatLng(25, 121.5), LatLng(25.001, 121.501)],
              ),
            ),
          ),
        ),
      );
      await t.pump();
      final active = tiles.pending.where((p) => !p.cancelled).toList();
      expect(active.length, greaterThan(3));
      const warning = '目前無法載入地圖底圖，標示的位置仍正確';
      for (final pending in active.take(2)) {
        pending.result.completeError(StateError('artificial tile failure'));
        await t.pump();
        expect(t.takeException(), isNull);
      }
      await t.pumpAndSettle();
      expect(find.text(warning), findsNothing);
      active[2].result.completeError(StateError('artificial tile failure'));
      await t.pump();
      expect(t.takeException(), isNull);
      await t.pumpAndSettle();
      expect(find.text(warning), findsOneWidget);
      expect(
        t.widget<PolylineLayer>(find.byType(PolylineLayer)).polylines,
        isNotEmpty,
      );
      expect(
        t.widget<MarkerLayer>(find.byType(MarkerLayer)).markers,
        isNotEmpty,
      );
      // Rebuilding a tile that loaded before the failures is not recovery.
      final stale = TileImage(
        vsync: t,
        imageProvider: _PendingImage(),
        coordinates: const TileCoordinates(0, 0, 0),
        onLoadComplete: (_) {},
        onLoadError: (_, error, stack) {},
        tileDisplay: const TileDisplay.instantaneous(),
        errorImage: null,
        cancelLoading: Completer<void>(),
      )..loadFinishedAt = DateTime.utc(2000);
      t.widget<TileLayer>(find.byType(TileLayer)).tileBuilder!(
        t.element(find.byType(TileLayer)),
        const SizedBox.shrink(),
        stale,
      );
      await t.pump();
      expect(find.text(warning), findsOneWidget);
      stale.dispose();
      // The warning neither steals gestures nor claims recovery after a quiet period.
      await t.pump(const Duration(seconds: 11));
      expect(find.text(warning), findsOneWidget);
      final camera = MapController.of(t.element(find.byType(TileLayer)));
      camera.move(const ll.LatLng(25.003, 121.503), 16);
      await t.pumpAndSettle();
      final image = (await t.runAsync(
        () => createTestImage(width: 256, height: 256),
      ))!;
      for (final pending in tiles.pending.where(
        (p) => !p.cancelled && !p.result.isCompleted,
      )) {
        pending.result.complete(ImageInfo(image: image.clone()));
      }
      image.dispose();
      await t.pumpAndSettle();
      expect(find.text(warning), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
}
