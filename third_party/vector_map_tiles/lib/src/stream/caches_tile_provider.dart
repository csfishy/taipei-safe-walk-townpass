import 'dart:async';

import 'package:vector_tile_renderer/vector_tile_renderer.dart';

import '../cache/caches.dart';
import 'tile_processor.dart';
import 'tile_supplier.dart';
import 'tileset_executor_preprocessor.dart';
import 'tileset_ui_preprocessor.dart';

class CachesTileProvider extends TileProvider {
  final Caches _caches;
  final TileProcessor _tileProcessor;
  final TilesetExecutorPreprocessor _preprocessor;
  final TilesetUiPreprocessor _uiPreprocessor;

  CachesTileProvider(this._caches, this._tileProcessor, this._preprocessor,
      this._uiPreprocessor);

  @override
  int get maximumZoom => _caches.vectorTileCache.maximumZoom;

  @override
  Future<TileResponse> provide(TileRequest request) =>
      _provide(request, localOnly: false);

  @override
  Future<TileResponse> provideLocalCopy(TileRequest request) =>
      _provide(request, localOnly: true);

  Future<TileResponse> _provide(TileRequest request,
      {required bool localOnly}) async {
    Map<String, TileData?> tileDataBySource =
        await _retrieve(request, localOnly: localOnly);
    if (tileDataBySource.values.any((t) => t == null)) {
      return TileResponse(identity: request.tileId, tileset: null);
    }
    Map<String, TileData> loadedDataBySource =
        tileDataBySource.map((key, value) => MapEntry(key, value!));
    Map<String, Tile> tileBySource =
        await _createTiles(request, loadedDataBySource);
    var tileset = await _preprocessor.preprocess(
        request.tileId,
        Tileset(tileBySource),
        request.clip,
        request.zoom.truncate(),
        request.cancelled);
    tileset = await _uiPreprocessor.preprocess(request.tileId, tileset,
        request.clip, request.zoom.truncate(), request.cancelled);
    return TileResponse(identity: request.tileId, tileset: tileset);
  }

  Future<Map<String, TileData?>> _retrieve(TileRequest request,
      {required bool localOnly}) async {
    request.testCancelled();
    final sources = request.tileSources.toList(growable: false);
    final data = await Future.wait(sources.map((source) =>
        _caches.vectorTileCache.retrieve(source, request.tileId,
            cachedOnly: localOnly, cancelled: request.cancelled)));
    request.testCancelled();
    return Map.fromIterables(sources, data);
  }

  Future<Map<String, Tile>> _createTiles(
      TileRequest request, Map<String, TileData> tileDataBySource) async {
    request.testCancelled();
    final sources = tileDataBySource.keys.toList(growable: false);
    final tiles = await Future.wait(sources.map((source) =>
        _tileProcessor.process(request, source, tileDataBySource[source]!, request.cancelled)));
    request.testCancelled();
    return Map.fromIterables(sources, tiles);
  }
}
