import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/navigation/avoid_area.dart';
import 'package:town_pass/features/safe_walk/navigation/json_transport.dart';
import 'package:town_pass/features/safe_walk/navigation/valhalla_avoiding_route_planner.dart';
import 'package:town_pass/features/safe_walk/navigation/walking_route_provider.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart' as sw;

// Straight east-west street at lat 25.0; the detour goes 300 m north.
final _origin = sw.Coordinates(lat: 25.0, lng: 121.500);
final _dest = sw.Coordinates(lat: 25.0, lng: 121.510);
const _direct = [
  [121.500, 25.0],
  [121.505, 25.0],
  [121.510, 25.0],
];
const _detour = [
  [121.500, 25.0],
  [121.500, 25.003],
  [121.510, 25.003],
  [121.510, 25.0],
];

AvoidArea _area(String id, double lat, double lng) => AvoidArea(id: id, center: sw.Coordinates(lat: lat, lng: lng), radiusMeters: 50, source: 'report');

void main() {
  test('decodes Valhalla polyline6', () {
    expect(decodePolyline6(_encode(_detour)), _detour.map((p) => [closeTo(p[0], 1e-6), closeTo(p[1], 1e-6)]).toList());
  });

  test('no areas: one request, only the best route', () async {
    final t = _Fake((_) => _direct);
    final plan = await _planner(t).plan(origin: _origin, destination: _dest, areas: const []);
    expect(t.bodies, hasLength(1));
    expect(t.bodies.single.containsKey('exclude_polygons'), isFalse);
    expect(t.bodies.single['costing'], 'pedestrian');
    expect(plan.options.single.level, AvoidLevel.none);
    expect(plan.options.single.route.walkingNetworkVerified, isTrue);
  });

  test('area on the street: best passes it, full avoidance detours and stays clear', () async {
    final t = _Fake((body) => body.containsKey('exclude_polygons') ? _detour : _direct);
    final plan = await _planner(t).plan(origin: _origin, destination: _dest, areas: [_area('a', 25.0, 121.505)]);
    expect(t.bodies, hasLength(3));
    // center and full detour identically, so the duplicate is dropped.
    expect(plan.options.map((o) => o.level), [AvoidLevel.none, AvoidLevel.center]);
    expect(plan[AvoidLevel.none]!.passedAreaIds, ['a']);
    expect(plan[AvoidLevel.center]!.passedAreaIds, isEmpty);
    final polygon = (t.bodies[2]['exclude_polygons'] as List).single as List;
    expect(polygon.first, polygon.last, reason: 'closed ring');
  });

  test('a circle holding the origin is not excluded and is reported', () async {
    final t = _Fake((_) => _direct);
    final plan = await _planner(t).plan(origin: _origin, destination: _dest, areas: [_area('home', 25.0, 121.5001)]);
    expect(plan.originInsideAreaIds, ['home']);
    expect(t.bodies.every((b) => !b.containsKey('exclude_polygons')), isTrue);
    expect(t.bodies, hasLength(1), reason: 'same exclusions are not re-requested');
  });

  test('no path for full avoidance (HTTP 400) leaves the level out', () async {
    final t = _Fake((body) => (body['exclude_polygons'] as List?)?.isNotEmpty == true ? null : _direct);
    final plan = await _planner(t).plan(origin: _origin, destination: _dest, areas: [_area('a', 25.0, 121.505)]);
    expect(plan.options.map((o) => o.level), [AvoidLevel.none]);
  });

  test('without consent nothing is sent', () async {
    final t = _Fake((_) => _direct);
    final planner = ValhallaAvoidingRoutePlanner(transport: t, hasConsent: () => false, wait: (_) async {});
    await expectLater(planner.plan(origin: _origin, destination: _dest, areas: const []), throwsA(isA<WalkingRouteProviderUnavailable>()));
    expect(t.bodies, isEmpty);
  });

  test('network failure is reported as unavailable', () async {
    final t = _Fake((_) => throw const JsonTransportException(TransportFailure.network));
    await expectLater(_planner(t).plan(origin: _origin, destination: _dest, areas: const []), throwsA(isA<WalkingRouteProviderUnavailable>()));
  });

  test('requests are spaced at least the minimum interval apart', () async {
    final waits = <Duration>[];
    final t = _Fake((body) => body.containsKey('exclude_polygons') ? _detour : _direct);
    final planner = ValhallaAvoidingRoutePlanner(transport: t, hasConsent: () => true, wait: (d) async => waits.add(d));
    await planner.plan(origin: _origin, destination: _dest, areas: [_area('a', 25.0, 121.505)]);
    expect(waits, hasLength(2));
    expect(waits.every((d) => d > const Duration(milliseconds: 900)), isTrue);
  });
}

ValhallaAvoidingRoutePlanner _planner(_Fake t) => ValhallaAvoidingRoutePlanner(transport: t, hasConsent: () => true, wait: (_) async {});

final class _Fake implements JsonTransport {
  _Fake(this.answer);
  final List<List<double>>? Function(Map<String, Object?> body) answer;
  final bodies = <Map<String, Object?>>[];

  @override
  Future<Object?> getJson(Uri url, {SafeWalkCancellation? cancellation}) async {
    final body = jsonDecode(url.queryParameters['json']!) as Map<String, Object?>;
    bodies.add(body);
    final line = answer(body);
    if (line == null) throw const JsonTransportException(TransportFailure.httpStatus);
    return {
      'trip': {
        'status': 0,
        'summary': {'time': 600, 'length': 1.0},
        'legs': [
          {'shape': _encode(line)},
        ],
      },
    };
  }

  @override
  Future<Object?> postFormJson(Uri url, Map<String, String> form, {SafeWalkCancellation? cancellation}) => throw UnimplementedError();
}

String _encode(List<List<double>> lngLat) {
  final out = StringBuffer();
  var pLat = 0, pLng = 0;
  void put(int v) {
    var n = v < 0 ? ~(v << 1) : v << 1;
    while (n >= 0x20) {
      out.writeCharCode((0x20 | (n & 0x1f)) + 63);
      n >>= 5;
    }
    out.writeCharCode(n + 63);
  }

  for (final p in lngLat) {
    final lat = (p[1] * 1e6).round(), lng = (p[0] * 1e6).round();
    put(lat - pLat);
    put(lng - pLng);
    pLat = lat;
    pLng = lng;
  }
  return out.toString();
}
