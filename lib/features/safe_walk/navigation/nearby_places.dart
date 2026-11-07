import 'package:town_pass/features/safe_walk/navigation/cancellable.dart';
import 'package:town_pass/features/safe_walk/navigation/coordinate_math.dart';
import 'package:town_pass/features/safe_walk/navigation/nearest_store_planner.dart';
import 'package:town_pass/features/safe_walk/navigation/route_service.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/semantics.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// One nearby real place with the provenance needed to trace it back.
final class NearbyPlace {
  const NearbyPlace({required this.point, required this.straightLineMeters});

  final sw.AssistancePoint point;

  /// Great-circle distance, not walking distance.
  final double straightLineMeters;

  String get name => point.name;

  /// WGS84.
  sw.Coordinates get coordinates => point.coordinates;

  /// Source record id, e.g. `osm-node-123`.
  String get sourceRecordId => point.id;

  String get datasetId => point.source.datasetId;
  String? get license => point.source.license;

  /// ISO-8601 time the record was retrieved from the source.
  String get retrievedAt => point.source.retrievedAt;

  /// Opening status as recorded. `unknown` is never treated as open.
  sw.OpeningStatus get hours => point.availability;

  /// Fixed text for the UI. Unknown hours are shown as unknown, never as 24h.
  String get hoursLabel => switch (point.availability) {
    sw.OpeningStatus.open => '資料標示營業中（未經店家確認）',
    sw.OpeningStatus.closed => '資料標示未營業',
    sw.OpeningStatus.unknown => '營業時間未知',
  };
}

/// Lists real places near a position (traceable source, WGS84) and builds the
/// walking-route request to one of them. It reads no GPS and calls no Google
/// service; routing goes through [RouteService] (OSRM in the live app).
final class NearbyPlacesService {
  NearbyPlacesService({
    required this.find,
    this.routeService,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// For example `OsmConvenienceStoreSource(only24Hours: false).findNear`.
  final NearbyPointFinder find;
  final RouteService? routeService;
  final DateTime Function() _clock;

  /// Places sorted by straight-line distance, then id. Points failing the
  /// shared semantic checks are skipped. Places with unknown opening hours are
  /// kept and labelled unknown. Lookup errors (consent, transport,
  /// cancellation) propagate; no place is ever invented.
  Future<List<NearbyPlace>> nearby(
    sw.Coordinates origin, {
    double? maxDistanceMeters,
    int? limit,
    SafeWalkCancellation? cancellation,
  }) async {
    final points = await raceCancellation(
      find(origin, cancellation: cancellation),
      cancellation,
    );
    final places = <NearbyPlace>[];
    for (final point in points) {
      if (pointProblems(point).isNotEmpty) continue;
      final meters = distanceMeters(origin, point.coordinates);
      if (maxDistanceMeters != null && meters > maxDistanceMeters) continue;
      places.add(NearbyPlace(point: point, straightLineMeters: meters));
    }
    places.sort((a, b) {
      final byDistance = a.straightLineMeters.compareTo(b.straightLineMeters);
      return byDistance != 0
          ? byDistance
          : a.sourceRecordId.compareTo(b.sourceRecordId);
    });
    if (limit == null || limit >= places.length) {
      return List.unmodifiable(places);
    }
    return List.unmodifiable(places.take(limit < 0 ? 0 : limit));
  }

  sw.RouteRequest routeRequestFor(
    NearbyPlace place,
    sw.Position origin, {
    required String requestId,
    required sw.DataMode mode,
  }) => sw.RouteRequest(
    requestId: requestId,
    mode: mode,
    origin: origin,
    destination: place.coordinates,
    departAt: _clock().toUtc().toIso8601String(),
    preference: sw.RouteKind.direct,
    maxExtraDistanceMeters: 0,
    assistancePointIds: const [],
  );

  /// Walking route to [place] through [routeService]. Throws [StateError]
  /// when no route service was given.
  Future<sw.RouteResult> routeTo(
    NearbyPlace place,
    sw.Position origin, {
    required String requestId,
    required sw.DataMode mode,
    SafeWalkCancellation? cancellation,
  }) {
    final service = routeService;
    if (service == null) throw StateError('routeService is not configured');
    return service.planRoute(
      routeRequestFor(place, origin, requestId: requestId, mode: mode),
      cancellation: cancellation,
    );
  }
}
