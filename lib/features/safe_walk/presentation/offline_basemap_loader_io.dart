import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:mbtiles/mbtiles.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_map_tiles_mbtiles/vector_map_tiles_mbtiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vector;

import 'offline_basemap_resource.dart';
import 'offline_map_file_io.dart';

Future<OfflineBasemap> loadOfflineBasemap() async {
  final path = await prepareOfflineMapFile();
  final style = jsonDecode(
    await rootBundle.loadString('assets/safe_walk/map/style.json'),
  ) as Map<String, dynamic>;
  final theme = vector.ThemeReader().read(style);
  final database = MbTiles(path: path);
  try {
    final provider = MbTilesVectorTileProvider(mbtiles: database);
    return OfflineBasemap(
      layer: VectorTileLayer(
        tileProviders: TileProviders({'protomaps': provider}),
        theme: theme,
        layerMode: VectorTileLayerMode.vector,
        maximumZoom: 19,
        concurrency: 2,
        fileCacheMaximumSizeInBytes: 0,
      ),
      close: () async => database.close(),
    );
  } catch (_) {
    database.close();
    rethrow;
  }
}
