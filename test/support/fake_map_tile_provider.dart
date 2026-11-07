import 'dart:convert';

import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';

// A plain white 256px PNG. No HTTP, filesystem cache, timers or native plugins.
final _image = MemoryImage(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAQAAAAEAAQMAAABmvDolAAAAAXNSR0IB2cksfwAAAAlwSFlzAAALEwAACxMBAJqcGAAAAANQTFRF////p8QbyAAAAB9JREFUeJztwQENAAAAwqD3T20ON6AAAAAAAAAAAL4NIQAAAfFnIe4AAAAASUVORK5CYII=',
  ),
);

final class FakeMapTileProvider extends TileProvider {
  @override
  ImageProvider<Object> getImage(
    TileCoordinates coordinates,
    TileLayer options,
  ) => _image;
}
