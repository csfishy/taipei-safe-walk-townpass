import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:town_pass/features/safe_walk/presentation/offline_tile_provider.dart';

class _Reader extends VectorTileProvider {
  _Reader(this.read);
  final Future<Uint8List> Function() read;
  int calls = 0;
  @override
  int get minimumZoom => 12;
  @override
  int get maximumZoom => 15;
  @override
  TileOffset get tileOffset => TileOffset.DEFAULT;
  @override
  Future<Uint8List> provide(TileIdentity tile) {
    calls++;
    return read();
  }
}

void main() {
  final tile = TileIdentity(15, 27444, 14027);
  test('missing coverage tiles do not trigger online fallback', () async {
    var failures = 0;
    final provider = OfflineTileProvider(
      _Reader(
        () async => throw ProviderException(
          message: 'outside',
          retryable: Retryable.none,
          statusCode: 404,
        ),
      ),
      onUnavailable: () => failures++,
    );
    await expectLater(
      provider.provide(tile),
      throwsA(isA<ProviderException>()),
    );
    expect(failures, 0);
  });
  test('decode/SQLite errors signal once without exposing details', () async {
    var failures = 0;
    final reader = _Reader(
      () async => throw const FormatException('private/path/coordinates'),
    );
    final provider = OfflineTileProvider(
      reader,
      onUnavailable: () => failures++,
    );
    for (var i = 0; i < 2; i++) {
      await expectLater(
        provider.provide(tile),
        throwsA(
          isA<ProviderException>().having(
            (e) => e.message,
            'sanitized message',
            'Offline tile unavailable',
          ),
        ),
      );
    }
    expect(failures, 1);
    expect(reader.calls, 1);
  });
  test('late reads after release never access the closed database', () async {
    final reader = _Reader(() async => Uint8List(0));
    var failures = 0;
    final provider = OfflineTileProvider(
      reader,
      onUnavailable: () => failures++,
    );
    provider.close();
    await expectLater(
      provider.provide(tile),
      throwsA(isA<ProviderException>()),
    );
    expect(reader.calls, 0);
    expect(failures, 0);
  });
}
