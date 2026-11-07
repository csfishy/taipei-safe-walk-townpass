import 'dart:async';

import 'package:town_pass/features/safe_walk/navigation/cancellable.dart';
import 'package:town_pass/features/safe_walk/navigation/consent.dart';
import 'package:town_pass/features/safe_walk/navigation/coordinate_math.dart';
import 'package:town_pass/features/safe_walk/navigation/json_transport.dart';
import 'package:town_pass/features/safe_walk/navigation/opening_hours.dart';
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
/// * The mirrors are asked at once and the first answer wins. Completed results
///   retain their retrieval time and are cached per grid cell and radius for
///   [cacheTtl]. Each lookup owns and cancels its unfinished requests.
final class OsmConvenienceStoreSource {
  OsmConvenienceStoreSource({
    required this.transport,
    required this.hasConsent,
    this.endpoints = defaultOverpassEndpoints,
    this.radiiMeters = const [1500, 8000],
    this.only24Hours = true,
    this.readOpeningHours = false,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// About 1.1 km of latitude: coarse enough not to identify a street.
  static const double gridDegrees = 0.01;

  static const Duration cacheTtl = Duration(minutes: 5);

  final JsonTransport transport;
  final bool Function() hasConsent;
  final List<String> endpoints;
  final List<double> radiiMeters;
  final bool only24Hours;

  /// Also read common `opening_hours` values (e.g. `Mo-Su 07:00-23:00`):
  /// a store counts as open only when it is open at retrieval time and stays
  /// open for [stayOpenMargin]; unreadable or missing hours stay unknown.
  final bool readOpeningHours;

  static const Duration stayOpenMargin = Duration(minutes: 30);
  final DateTime Function() _clock;
  final Map<String, _CachedElements> _cache = {};

  /// Throws [ConsentRequiredException], [JsonTransportException] or
  /// [SafeWalkCancelledException]; it never returns invented stores.
  Future<List<sw.AssistancePoint>> findNear(
    sw.Coordinates origin, {
    SafeWalkCancellation? cancellation,
  }) async {
    if (!hasConsent()) throw const ConsentRequiredException();
    cancellation?.throwIfCancelled();

    final stop = ManualCancellation();
    if (cancellation != null) {
      unawaited(cancellation.whenCancelled.then((_) => stop.cancel()));
    }
    try {
      final radii = [...radiiMeters]..sort();
      final jobs = [for (final r in radii) _elements(origin, r, stop)];
      for (final job in jobs) {
        job.then<void>((_) {}, onError: (Object _) {}); // never unhandled
      }
      Object? lastError;
      for (final job in jobs) {
        try {
          final result = await raceCancellation(job, stop);
          cancellation?.throwIfCancelled();
          stop.throwIfCancelled();
          if (result.elements.isEmpty) continue;
          return [
            for (final element in result.elements)
              ?_toPoint(
                element,
                result.retrievedAt,
                only24Hours,
              ),
          ];
        } on SafeWalkCancelledException {
          rethrow;
        } catch (error) {
          lastError = error;
        }
      }
      if (lastError != null) throw lastError;
      return const [];
    } finally {
      stop.cancel();
    }
  }

  Future<_CachedElements> _elements(
    sw.Coordinates origin,
    double radius,
    SafeWalkCancellation cancellation,
  ) async {
    cancellation.throwIfCancelled();
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
    if (cached != null) {
      final age = _clock().toUtc().difference(cached.retrievedAt);
      if (!age.isNegative && age < cacheTtl) return cached;
      _cache.remove(key);
    }
    // In-flight requests belong only to this lookup, so cancelling another
    // lookup in the same cell cannot close this one's connections.
    final elements = await _request(
      center,
      (radius + margin).ceil(),
      cancellation,
    );
    cancellation.throwIfCancelled();
    final result = _CachedElements(elements, _clock().toUtc());
    _cache[key] = result;
    return result;
  }

  Future<List<Map<String, Object?>>> _request(
    sw.Coordinates center,
    int radius,
    SafeWalkCancellation cancellation,
  ) async {
    cancellation.throwIfCancelled();
    final hours = only24Hours ? '["opening_hours"="24/7"]' : '';
    final query =
        '[out:json][timeout:10];'
        'nwr["shop"="convenience"]$hours'
        '(around:$radius,${center.lat.toStringAsFixed(5)},${center.lng.toStringAsFixed(5)});'
        'out center tags;';
    final stop = ManualCancellation();
    unawaited(cancellation.whenCancelled.then((_) => stop.cancel()));
    try {
      final attempts = [
        for (final endpoint in endpoints)
          transport
              .postFormJson(Uri.parse(endpoint), {
                'data': query,
              }, cancellation: stop)
              .then(_elementList),
      ];
      return await raceCancellation(firstSuccess(attempts), cancellation);
    } finally {
      stop.cancel();
    }
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
    DateTime retrievedTime,
    bool onlyOpenAllDay,
  ) {
    final retrievedAt = retrievedTime.toIso8601String();
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
      final hours = tagMap['opening_hours'];
      final allDay = hours == '24/7';
      final bool? readOpen = readOpeningHours && hours is String
          ? openingHoursOpenFor(
              hours,
              taipeiTimeOf(retrievedTime),
              stayOpenMargin,
            )
          : null;
      final open = allDay || readOpen == true;
      final status = open
          ? sw.OpeningStatus.open
          : readOpen == false
          ? sw.OpeningStatus.closed
          : sw.OpeningStatus.unknown;

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
        availability: status,
        availabilityCheckedAt: status == sw.OpeningStatus.unknown
            ? null
            : retrievedAt,
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
          limitations: [
            '社群編輯資料，非官方店家清單，也不是警方認可的求助據點',
            '營業時間來自 opening_hours 標籤，未經店家確認，不代表現在一定營業',
            readOpeningHours
                ? '未標示或無法判讀營業時間的店不列為營業中，清單不完整'
                : '未標示營業時間的店不會出現在 24 小時結果中，清單不完整',
          ],
        ),
      );
    } on FormatException {
      return null;
    }
  }
}

final class _CachedElements {
  const _CachedElements(this.elements, this.retrievedAt);

  final List<Map<String, Object?>> elements;
  final DateTime retrievedAt;
}
