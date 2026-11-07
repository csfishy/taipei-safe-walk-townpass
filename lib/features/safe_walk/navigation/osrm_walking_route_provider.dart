import 'package:town_pass/features/safe_walk/navigation/consent.dart';
import 'package:town_pass/features/safe_walk/navigation/coordinate_math.dart';
import 'package:town_pass/features/safe_walk/navigation/json_transport.dart';
import 'package:town_pass/features/safe_walk/navigation/walking_route_provider.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// Real walking routes from an OSRM server running the OpenStreetMap foot
/// profile (default: the public routing.openstreetmap.de instance).
///
/// * Nothing is sent unless [hasConsent] returns true; the exact origin and
///   destination go to that third-party server, which is why.
/// * Candidates are marked `walkingNetworkVerified` only because the server
///   routed on the OSM foot network. That says nothing about safety, lighting,
///   accessibility or whether a path is open right now.
/// * The public instance is a fair-use demo server with no availability
///   guarantee; production use needs a self-hosted or contracted server.
final class OsrmWalkingRouteProvider implements WalkingRouteProvider {
  OsrmWalkingRouteProvider({
    required this.transport,
    required this.hasConsent,
    this.pointLookup,
    Uri? endpoint,
  }) : endpoint = endpoint ?? Uri.parse(defaultEndpoint);

  static const providerId = 'osrm-foot (routing.openstreetmap.de)';

  /// The profile segment is ignored by this host; `routed-foot` selects it.
  static const defaultEndpoint =
      'https://routing.openstreetmap.de/routed-foot/route/v1/driving';

  final JsonTransport transport;
  final bool Function() hasConsent;
  final AssistancePointLookup? pointLookup;
  final Uri endpoint;

  @override
  Future<List<sw.RouteCandidate>> findRoutes(
    sw.RouteRequest request, {
    SafeWalkCancellation? cancellation,
  }) async {
    if (!hasConsent()) throw const ConsentRequiredException();
    cancellation?.throwIfCancelled();

    final origin = request.origin.coordinates;
    final destination = request.destination;
    final viaIds = request.preference == sw.RouteKind.viaAssistance
        ? request.assistancePointIds
        : const <String>[];
    final via = await _viaCoordinates(viaIds, cancellation);

    final directFuture = _fetch([origin, destination], cancellation);
    if (via.isEmpty) {
      final direct = await directFuture;
      return [_candidate('osrm-direct', sw.RouteKind.direct, direct, const [])];
    }

    final viaFuture = _fetch([origin, ...via, destination], cancellation);
    final direct = await directFuture;
    final _Leg viaLeg;
    try {
      viaLeg = await viaFuture;
    } on WalkingRouteNotFound {
      return [
        _candidate(
          'osrm-direct',
          sw.RouteKind.direct,
          direct,
          const [],
          note: '途經據點沒有可步行的路線，改回直接路線',
        ),
      ];
    }

    final extra = viaLeg.distanceMeters - direct.distanceMeters;
    if (extra > request.maxExtraDistanceMeters) {
      return [
        _candidate(
          'osrm-direct',
          sw.RouteKind.direct,
          direct,
          const [],
          note:
              '途經據點會多繞約 ${extra.round()} 公尺，超過上限 '
              '${request.maxExtraDistanceMeters} 公尺，改回直接路線',
        ),
      ];
    }
    return [
      _candidate(
        'osrm-via',
        sw.RouteKind.viaAssistance,
        viaLeg,
        viaIds,
        note: '途經據點多繞約 ${extra.round()} 公尺',
      ),
      _candidate('osrm-direct', sw.RouteKind.direct, direct, const []),
    ];
  }

  Future<List<sw.Coordinates>> _viaCoordinates(
    List<String> ids,
    SafeWalkCancellation? cancellation,
  ) async {
    if (ids.isEmpty) return const [];
    final lookup = pointLookup;
    if (lookup == null) throw const WalkingRouteProviderUnavailable();
    final points = await lookup(ids, cancellation: cancellation);
    return [
      for (final id in ids)
        points
            .firstWhere(
              (point) => point.id == id,
              orElse: () => throw const WalkingRouteProviderUnavailable(),
            )
            .coordinates,
    ];
  }

  Future<_Leg> _fetch(
    List<sw.Coordinates> waypoints,
    SafeWalkCancellation? cancellation,
  ) async {
    final path = waypoints
        .map((c) => '${c.lng.toStringAsFixed(6)},${c.lat.toStringAsFixed(6)}')
        .join(';');
    final url = Uri.parse('$endpoint/$path').replace(
      queryParameters: const {
        'overview': 'full',
        'geometries': 'geojson',
        'alternatives': 'false',
        'steps': 'false',
      },
    );
    return _parse(await transport.getJson(url, cancellation: cancellation));
  }

  _Leg _parse(Object? json) {
    if (json is! Map) throw const WalkingRouteProviderUnavailable();
    final code = json['code'];
    if (code == 'NoRoute' || code == 'NoSegment') {
      throw const WalkingRouteNotFound();
    }
    if (code != 'Ok') throw const WalkingRouteProviderUnavailable();
    final routes = json['routes'];
    if (routes is! List || routes.isEmpty || routes.first is! Map) {
      throw const WalkingRouteProviderUnavailable();
    }
    final route = routes.first as Map;
    final distance = route['distance'];
    final duration = route['duration'];
    final geometry = route['geometry'];
    if (distance is! num ||
        duration is! num ||
        !distance.isFinite ||
        !duration.isFinite ||
        distance < 0 ||
        duration < 0 ||
        geometry is! Map ||
        geometry['coordinates'] is! List) {
      throw const WalkingRouteProviderUnavailable();
    }
    final line = <sw.GeoJsonCoordinate>[];
    for (final raw in geometry['coordinates'] as List) {
      if (raw is! List || raw.length < 2 || raw[0] is! num || raw[1] is! num) {
        throw const WalkingRouteProviderUnavailable();
      }
      final lng = (raw[0] as num).toDouble();
      final lat = (raw[1] as num).toDouble();
      if (!isValidLatLng(lat, lng)) {
        throw const WalkingRouteProviderUnavailable();
      }
      line.add((longitude: lng, latitude: lat));
    }
    if (line.length < 2) throw const WalkingRouteNotFound();
    return _Leg(
      distanceMeters: distance.toDouble(),
      durationSeconds: duration.toDouble(),
      line: line,
    );
  }

  sw.RouteCandidate _candidate(
    String id,
    sw.RouteKind kind,
    _Leg leg,
    List<String> viaPointIds, {
    String? note,
  }) => sw.RouteCandidate(
    id: id,
    kind: kind,
    geometry: sw.LineString(coordinates: leg.line),
    distanceMeters: leg.distanceMeters,
    durationSeconds: leg.durationSeconds,
    viaPointIds: viaPointIds,
    provider: providerId,
    walkingNetworkVerified: true,
    explanations: [?note, '依 OpenStreetMap 步行路網計算'],
    warnings: const [
      '僅反映路網，不保證路段安全、照明、無障礙或目前可通行',
      '路網資料 © OpenStreetMap contributors（ODbL）；公共伺服器不保證可用性',
    ],
  );
}

final class _Leg {
  const _Leg({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.line,
  });

  final double distanceMeters;
  final double durationSeconds;
  final List<sw.GeoJsonCoordinate> line;
}
