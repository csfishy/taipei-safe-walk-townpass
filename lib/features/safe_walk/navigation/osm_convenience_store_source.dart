import 'dart:async';

import 'package:town_pass/features/safe_walk/navigation/cancellable.dart';
import 'package:town_pass/features/safe_walk/navigation/consent.dart';
import 'package:town_pass/features/safe_walk/navigation/coordinate_math.dart';
import 'package:town_pass/features/safe_walk/navigation/json_transport.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

const List<String> defaultOverpassEndpoints = [
  'https://overpass-api.de/api/interpreter',
  'https://overpass.private.coffee/api/interpreter',
  'https://overpass.kumi.systems/api/interpreter',
];

/// Convenience stores of every chain from OpenStreetMap through the Overpass
/// API, as shared [sw.AssistancePoint]s. Pass the result to `nearestPoints()`.
///
/// * By default only stores tagged `opening_hours=24/7` are returned, and they
///   are recorded as `open`. The tag is community data nobody has verified
///   with the store, and OSM tagging in Taiwan is incomplete, so the list is a
///   lower bound: a missing store is not proof that it is closed. An empty
///   list means "none known", not "none nearby".
/// * Nothing is sent unless [hasConsent] returns true. The exact position is
///   never sent: the query is centred on a [gridDegrees] grid cell and the
///   radius widened to still cover the real position.
/// * The mirrors are asked at once and the first answer wins. Raw results are
///   cached per grid cell and radius; failures are not cached.
final class OsmConvenienceStoreSource {
  OsmConvenienceStoreSource({
    required this.transport,
    required this.hasConsent,
    this.endpoints = defaultOverpassEndpoints,
    this.radiiMeters = const [1500, 8000],
    this.only24Hours = true,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// About 1.1 km of latitude: coarse enough not to identify a street.
  static const double gridDegrees = 0.01;

  final JsonTransport transport;
  final bool Function() hasConsent;
  final List<String> endpoints;
  final List<double> radiiMeters;
  final bool only24Hours;
  final DateTime Function() _clock;
  final Map<String, Future<List<Map<String, Object?>>>> _cache = {};

  /// Throws [ConsentRequiredException], [JsonTransportException] or
  /// [SafeWalkCancelledException]; it never returns invented stores.
  Future<List<sw.AssistancePoint>> findNear(
    sw.Coordinates origin, {
    SafeWalkCancellation? cancellation,
  }) async {
    if (!hasConsent()) throw const ConsentRequiredException();
    cancellation?.throwIfCancelled();

    final radii = [...radiiMeters]..sort();
    final jobs = [for (final r in radii) _elements(origin, r)];
    for (final job in jobs) {
      job.then<void>((_) {}, onError: (Object _) {}); // never unhandled
    }
    Object? lastError;
    for (final job in jobs) {
      try {
        final elements = await raceCancellation(job, cancellation);
        if (elements.isEmpty) continue;
        final retrievedAt = _clock().toUtc().toIso8601String();
        return [
          for (final element in elements)
            ?_toPoint(element, retrievedAt, only24Hours),
        ];
      } on SafeWalkCancelledException {
        rethrow;
      } catch (error) {
        lastError = error;
      }
    }
    if (lastError != null) throw lastError;
    return const [];
  }

  Future<List<Map<String, Object?>>> _elements(
    sw.Coordinates origin,
    double radius,
  ) {
    final row = (origin.lat / gridDegrees).floor();
    final col = (origin.lng / gridDegrees).floor();
    final center = sw.Coordinates(
      lat: (row + 0.5) * gridDegrees,
      lng: (col + 0.5) * gridDegrees,
    );
    // Ball(origin, r) lies inside Ball(center, r + distance to a cell corner).
    final margin = distanceMeters(
      center,
      sw.Coordinates(
        lat: center.lat + gridDegrees / 2,
        lng: center.lng + gridDegrees / 2,
      ),
    );
    final key = '$row:$col:$radius:$only24Hours';
    final cached = _cache[key];
    if (cached != null) return cached;
    final request = _request(center, (radius + margin).ceil());
    _cache[key] = request;
    // A block body: returning remove()'s value would hand back the failed
    // future itself and re-raise its error as unhandled.
    request.then<void>(
      (_) {},
      onError: (Object _) {
        _cache.remove(key);
      },
    );
    return request;
  }

  Future<List<Map<String, Object?>>> _request(
    sw.Coordinates center,
    int radius,
  ) {
    final hours = only24Hours ? '["opening_hours"="24/7"]' : '';
    final query =
        '[out:json][timeout:10];'
        'nwr["shop"="convenience"]$hours'
        '(around:$radius,${center.lat.toStringAsFixed(5)},${center.lng.toStringAsFixed(5)});'
        'out center tags;';
    final stop = ManualCancellation();
    final attempts = [
      for (final endpoint in endpoints)
        transport
            .postFormJson(Uri.parse(endpoint), {
              'data': query,
            }, cancellation: stop)
            .then(_elementList),
    ];
    return firstSuccess(attempts).whenComplete(stop.cancel);
  }

  List<Map<String, Object?>> _elementList(Object? json) {
    if (json is! Map || json['elements'] is! List) {
      throw const JsonTransportException(TransportFailure.malformed);
    }
    return [
      for (final element in json['elements'] as List)
        if (element is Map) element.cast<String, Object?>(),
    ];
  }

  /// Null for an element that is unusable; one bad record never drops the rest.
  sw.AssistancePoint? _toPoint(
    Map<String, Object?> element,
    String retrievedAt,
    bool onlyOpenAllDay,
  ) {
    try {
      final type = element['type'];
      final id = element['id'];
      if (type is! String || id is! int) return null;
      final center = element['center'];
      final lat = element['lat'] ?? (center is Map ? center['lat'] : null);
      final lon = element['lon'] ?? (center is Map ? center['lon'] : null);
      if (lat is! num || lon is! num) return null;
      if (!isValidLatLng(lat.toDouble(), lon.toDouble())) return null;

      final tags = element['tags'];
      final tagMap = tags is Map ? tags : const {};
      final rawName = tagMap['name'] ?? tagMap['brand'];
      final name = rawName is String && rawName.trim().isNotEmpty
          ? rawName.trim()
          : '便利商店（無名稱）';
      final allDay = tagMap['opening_hours'] == '24/7';
      final open = allDay;

      return sw.AssistancePoint(
        id: 'osm-$type-$id',
        name: name.length > 100 ? name.substring(0, 100) : name,
        kind: sw.AssistancePointKind.convenienceStore,
        coordinates: sw.Coordinates(lat: lat.toDouble(), lng: lon.toDouble()),
        address: null,
        publicPhone: null,
        recognition: sw.UnconfirmedRecognition(
          status: sw.UnconfirmedRecognitionStatus.unconfirmed,
          checkedAt: null,
        ),
        availability: open ? sw.OpeningStatus.open : sw.OpeningStatus.unknown,
        availabilityCheckedAt: open ? retrievedAt : null,
        capabilities: const [sw.AssistanceCapability.unknown],
        source: sw.SourceMetadata(
          datasetId: 'osm-overpass-convenience-stores',
          title: 'OpenStreetMap 便利商店（Overpass API，社群資料）',
          dataMode: sw.DataMode.live,
          sourceUrl: 'https://www.openstreetmap.org/',
          retrievedAt: retrievedAt,
          dataUpdatedAt: null,
          license: 'ODbL 1.0 — © OpenStreetMap contributors',
          coverage: onlyOpenAllDay
              ? '查詢範圍內 OSM 標示 shop=convenience 且 opening_hours=24/7 的店'
              : '查詢範圍內 OSM 標示 shop=convenience 的店',
          limitations: const [
            '社群編輯資料，非官方店家清單，也不是警方認可的求助據點',
            '營業時間來自 opening_hours 標籤，未經店家確認，不代表現在一定營業',
            '未標示營業時間的店不會出現在 24 小時結果中，清單不完整',
          ],
        ),
      );
    } on FormatException {
      return null;
    }
  }
}
