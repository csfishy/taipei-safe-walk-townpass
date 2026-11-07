import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/navigation/route_reference_area_check.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

// Artificial geometry on a round-number grid; not a real place or route.
sw.RouteCandidate route(String id, List<List<double>> lngLat) =>
    sw.RouteCandidate(
      id: id,
      kind: sw.RouteKind.direct,
      geometry: sw.LineString(
        coordinates: [
          for (final p in lngLat) (longitude: p[0], latitude: p[1]),
        ],
      ),
      distanceMeters: 300,
      durationSeconds: 240,
      viaPointIds: const [],
      provider: 'osrm-foot (test)',
      walkingNetworkVerified: true,
      explanations: const ['依 OpenStreetMap 步行路網計算'],
      warnings: const ['僅反映路網，不保證路段安全'],
    );

RouteReferenceArea square({
  String id = 'area-1',
  double lng = 121.5,
  double lat = 25.0,
  double size = 0.001,
}) => RouteReferenceArea(
  id: id,
  label: '人工範圍',
  evidence: '人工測試邊界',
  ring: [
    (longitude: lng, latitude: lat),
    (longitude: lng + size, latitude: lat),
    (longitude: lng + size, latitude: lat + size),
    (longitude: lng, latitude: lat + size),
  ],
);

void main() {
  // Passes straight through the square's middle (no vertex inside it).
  final through = route('through', [
    [121.4990, 25.0005],
    [121.5020, 25.0005],
  ]);
  // Stays south of the square.
  final around = route('around', [
    [121.4990, 24.9990],
    [121.5020, 24.9990],
  ]);

  test('no reviewed area means nothing is compared', () {
    final result = compareRoutesWithReferenceAreas([through], const []);
    expect(result.status, RouteAreaComparisonStatus.noReliableArea);
    expect(result.candidates.single.crossesArea, isFalse);
  });

  test('segment crossing without a vertex inside is detected', () {
    expect(
      lineCrossesRing(through.geometry.coordinates, square().ring),
      isTrue,
    );
    expect(
      lineCrossesRing(around.geometry.coordinates, square().ring),
      isFalse,
    );
  });

  test('vertex inside the area is detected', () {
    final inside = route('inside', [
      [121.5005, 25.0005],
      [121.5005, 25.0005],
    ]);
    expect(lineCrossesRing(inside.geometry.coordinates, square().ring), isTrue);
  });

  test('single crossing candidate has no alternative', () {
    final result = compareRoutesWithReferenceAreas([through], [square()]);
    expect(result.status, RouteAreaComparisonStatus.noAlternativeRoute);
    expect(result.candidates.single.crossedAreaIds, ['area-1']);
  });

  test('a real non-crossing candidate is reported as an alternative', () {
    final result = compareRoutesWithReferenceAreas(
      [through, around],
      [square()],
    );
    expect(result.status, RouteAreaComparisonStatus.alternativeAvailable);
    expect(result.candidates.map((c) => c.crossesArea), [true, false]);
  });

  test('no candidate crossing is its own state', () {
    final result = compareRoutesWithReferenceAreas([around], [square()]);
    expect(result.status, RouteAreaComparisonStatus.noCandidateCrosses);
  });

  test('candidate geometry is never modified', () {
    final before = through.toJson().toString();
    compareRoutesWithReferenceAreas([through, around], [square()]);
    expect(through.toJson().toString(), before);
  });

  test('an area needs a ring and evidence; a point cannot become one', () {
    expect(
      () => RouteReferenceArea(
        id: 'p',
        label: '點',
        evidence: '參考座標',
        ring: const [(longitude: 121.5, latitude: 25.0)],
      ),
      throwsArgumentError,
    );
    expect(
      () => square().ring.add(square().ring.first),
      throwsUnsupportedError,
    );
    expect(
      () => RouteReferenceArea(
        id: 'x',
        label: 'x',
        evidence: '',
        ring: square().ring,
      ),
      throwsArgumentError,
    );
  });
}
