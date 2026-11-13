import 'package:flutter/foundation.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

/// Missing/out-of-coverage tiles are normal. A corrupt/failed local reader is
/// surfaced to the shared UI, without exposing database paths or exceptions.
class OfflineTileProvider extends VectorTileProvider {
  OfflineTileProvider(this.delegate, {required this.onUnavailable});
  final VectorTileProvider delegate;
  final VoidCallback onUnavailable;
  bool _closed = false;
  bool _failed = false;

  void close() => _closed = true;
  @override
  int get minimumZoom => delegate.minimumZoom;
  @override
  int get maximumZoom => delegate.maximumZoom;
  @override
  TileOffset get tileOffset => delegate.tileOffset;
  @override
  Future<Uint8List> provide(TileIdentity tile) async {
    if (_closed || _failed) throw _missing();
    try {
      return await delegate.provide(tile);
    } on ProviderException catch (error) {
      if (error.statusCode == 404 || error.statusCode == 204) rethrow;
      _fail();
    } catch (_) {
      _fail();
    }
    // The renderer handles 404 as an empty tile while UI switches to online.
    throw _missing();
  }

  void _fail() {
    if (!_closed && !_failed) {
      _failed = true;
      onUnavailable();
    }
  }

  ProviderException _missing() => ProviderException(
    message: 'Offline tile unavailable',
    retryable: Retryable.none,
    statusCode: 404,
  );
}
