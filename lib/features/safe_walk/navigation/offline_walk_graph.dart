import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:town_pass/features/safe_walk/navigation/coordinate_math.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// Immutable CSR view. No Flutter, GPS, filesystem or sensitive-area storage.
final class OfflineWalkGraph {
  OfflineWalkGraph._(
    this._data,
    this.nodeCount,
    this.edgeCount,
    this.names,
    this.snapshotDate,
  );
  final ByteData _data;
  final int nodeCount, edgeCount;
  final List<String> names;
  final String snapshotDate;
  int get _offsets => 24 + nodeCount * 8;
  int get _edges => _offsets + (nodeCount + 1) * 4;

  factory OfflineWalkGraph.parse(Uint8List bytes, Map<String, dynamic> meta) {
    void require(bool ok) {
      if (!ok) throw const FormatException('Invalid offline walking graph');
    }

    require(bytes.length >= 28 && bytes.length <= 50000000);
    require(ascii.decode(bytes.sublist(0, 8)) == 'SWWALK01');
    require(meta['format'] == 'SWWALK01' && meta['license'] == 'ODbL-1.0');
    require(sha256.convert(bytes).toString() == meta['sha256']);
    final data = ByteData.sublistView(bytes);
    int u32(int p) => data.getUint32(p, Endian.little);
    final n = u32(8), e = u32(12), count = u32(16), size = u32(20);
    require(
      n > 0 &&
          e > 0 &&
          count > 0 &&
          meta['nodes'] == n &&
          meta['edges'] == e &&
          meta['bytes'] == bytes.length,
    );
    final stringsAt = 24 + n * 8 + (n + 1) * 4 + e * 16;
    require(stringsAt + size == bytes.length);
    final decoded = jsonDecode(utf8.decode(bytes.sublist(stringsAt)));
    require(
      decoded is List &&
          decoded.length == count &&
          decoded.every((s) => s is String),
    );
    final date = meta['sourceDate'];
    require(date is String && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date));
    final bbox = meta['bbox'];
    require(
      bbox is List &&
          bbox.length == 4 &&
          bbox.every((v) => v is num && v.isFinite),
    );
    require(bbox[0] < bbox[2] && bbox[1] < bbox[3]);
    final graph = OfflineWalkGraph._(
      data,
      n,
      e,
      List<String>.unmodifiable(decoded as List),
      date as String,
    );
    for (var i = 0; i < n; i++) {
      final c = graph.geoCoordinate(i);
      require(
        isValidLatLng(c.latitude, c.longitude) &&
            c.latitude >= bbox[0] &&
            c.latitude <= bbox[2] &&
            c.longitude >= bbox[1] &&
            c.longitude <= bbox[3],
      );
      require(graph.begin(i) <= graph.begin(i + 1) && graph.begin(i + 1) <= e);
    }
    require(graph.begin(0) == 0 && graph.begin(n) == e);
    for (var i = 0; i < e; i++) {
      require(
        graph.target(i) < n &&
            graph.length(i) > 0 &&
            graph.nameIndex(i) < count &&
            graph.flags(i) <= 1,
      );
    }
    return graph;
  }

  sw.Coordinates coordinate(int n) => fromGeoJson(geoCoordinate(n));
  sw.GeoJsonCoordinate geoCoordinate(int n) => (
    latitude: _data.getInt32(24 + n * 8, Endian.little) / 1e7,
    longitude: _data.getInt32(28 + n * 8, Endian.little) / 1e7,
  );
  int begin(int n) => _data.getUint32(_offsets + n * 4, Endian.little);
  int target(int e) => _data.getUint32(_edges + e * 16, Endian.little);
  double length(int e) =>
      _data.getUint32(_edges + e * 16 + 4, Endian.little) / 1000;
  int nameIndex(int e) => _data.getUint32(_edges + e * 16 + 8, Endian.little);
  int flags(int e) => _data.getUint8(_edges + e * 16 + 12);
  String? street(int e) {
    final name = names[nameIndex(e)];
    return name.isEmpty ? null : name;
  }

  /// Snap to a segment, never a nearby vertex on an unrelated road. Only
  /// existing OSM edges are used; projected endpoints become virtual vertices.
  GraphSnap nearestSegment(sw.Coordinates p) {
    var best = double.infinity;
    GraphSnap? snap;
    final position = toGeoJson(p);
    for (var u = 0; u < nodeCount; u++) {
      final a = geoCoordinate(u);
      for (var e = begin(u); e < begin(u + 1); e++) {
        final v = target(e), b = geoCoordinate(v);
        final projection = projectToGeoJsonSegment(position, a, b);
        if (projection.distance < best) {
          best = projection.distance;
          snap = GraphSnap(
            u,
            v,
            e,
            projection.fraction,
            fromGeoJson(projection.point),
            best,
          );
        }
      }
    }
    if (snap == null) throw const FormatException('Empty offline graph');
    return snap;
  }
}

final class GraphSnap {
  const GraphSnap(
    this.from,
    this.to,
    this.edge,
    this.fraction,
    this.point,
    this.distance,
  );
  final int from, to, edge;
  final double fraction, distance;
  final sw.Coordinates point;
}
