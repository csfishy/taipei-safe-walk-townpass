import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/navigation/cancellable.dart';
import 'package:town_pass/features/safe_walk/navigation/consent.dart';
import 'package:town_pass/features/safe_walk/navigation/json_transport.dart';
import 'package:town_pass/features/safe_walk/navigation/nearest_point.dart';
import 'package:town_pass/features/safe_walk/navigation/osm_convenience_store_source.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/semantics.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

final now = DateTime.utc(2026, 11, 7, 3, 30);
final origin = sw.Coordinates(lat: 25.0478, lng: 121.5170);

Map<String, Object?> node(
  int id,
  double lat,
  double lon, {
  String? name,
  String? hours = '24/7',
}) => {
  'type': 'node',
  'id': id,
  'lat': lat,
  'lon': lon,
  'tags': {'shop': 'convenience', 'name': ?name, 'opening_hours': ?hours},
};

Map<String, Object?> reply(List<Object?> elements) => {
  'version': 0.6,
  'elements': elements,
};

final class Call {
  Call(this.url, this.query, this.cancellation);

  final Uri url;
  final String query;
  final SafeWalkCancellation? cancellation;
}

final class FakeTransport implements JsonTransport {
  FakeTransport(this.onPost);

  final Future<Object?> Function(Call call) onPost;
  final calls = <Call>[];

  @override
  Future<Object?> getJson(Uri url, {SafeWalkCancellation? cancellation}) =>
      throw UnimplementedError();

  @override
  Future<Object?> postFormJson(
    Uri url,
    Map<String, String> form, {
    SafeWalkCancellation? cancellation,
  }) {
    final call = Call(url, form['data']!, cancellation);
    calls.add(call);
    return onPost(call);
  }
}

OsmConvenienceStoreSource source(
  FakeTransport transport, {
  bool consent = true,
  bool only24Hours = true,
  List<String> endpoints = const ['https://a.test/x', 'https://b.test/x'],
  List<double> radii = const [1500, 8000],
}) => OsmConvenienceStoreSource(
  transport: transport,
  hasConsent: () => consent,
  endpoints: endpoints,
  radiiMeters: radii,
  only24Hours: only24Hours,
  clock: () => now,
);

int radiusOf(Call call) =>
    int.parse(RegExp(r'around:(\d+)').firstMatch(call.query)!.group(1)!);

void main() {
  group('consent and privacy', () {
    test('without consent nothing is requested', () async {
      final transport = FakeTransport((_) async => reply([]));

      await expectLater(
        source(transport, consent: false).findNear(origin),
        throwsA(isA<ConsentRequiredException>()),
      );
      expect(transport.calls, isEmpty);
    });

    test('the exact position is never sent', () async {
      final transport = FakeTransport(
        (_) async => reply([node(1, 25.048, 121.518)]),
      );

      await source(transport).findNear(origin);

      for (final call in transport.calls) {
        expect(call.query, isNot(contains('25.0478')));
        expect(call.query, isNot(contains('121.517')));
        expect(call.url.scheme, 'https');
      }
    });

    test('the widened radius still covers a store at the limit', () async {
      final transport = FakeTransport((_) async => reply([]));

      await source(transport, radii: const [1500]).findNear(origin);

      expect(radiusOf(transport.calls.first), greaterThan(1500));
      expect(radiusOf(transport.calls.first), lessThan(1500 + 1000));
    });
  });

  group('query', () {
    test('asks for 24/7 convenience stores by default', () async {
      final transport = FakeTransport((_) async => reply([]));

      await source(transport, radii: const [1500]).findNear(origin);

      expect(transport.calls.first.query, contains('["shop"="convenience"]'));
      expect(transport.calls.first.query, contains('["opening_hours"="24/7"]'));
      expect(transport.calls.first.query, contains('out center tags'));
    });

    test('only24Hours false drops the hours filter', () async {
      final transport = FakeTransport((_) async => reply([]));

      await source(
        transport,
        only24Hours: false,
        radii: const [1500],
      ).findNear(origin);

      expect(transport.calls.first.query, isNot(contains('opening_hours')));
    });
  });

  group('parsing', () {
    test('builds live assistance points that pass the shared checks', () async {
      final transport = FakeTransport(
        (_) async => reply([
          node(11, 25.0485, 121.5175, name: '示範便利商店'),
          {
            'type': 'way',
            'id': 12,
            'center': {'lat': 25.049, 'lon': 121.518},
            'tags': {'shop': 'convenience', 'opening_hours': '24/7'},
          },
        ]),
      );

      final points = await source(transport).findNear(origin);

      expect(points, hasLength(2));
      final first = points.firstWhere((p) => p.id == 'osm-node-11');
      expect(first.name, '示範便利商店');
      expect(first.kind, sw.AssistancePointKind.convenienceStore);
      expect(first.coordinates.lat, 25.0485);
      expect(first.coordinates.lng, 121.5175);
      expect(first.availability, sw.OpeningStatus.open);
      expect(first.availabilityCheckedAt, '2026-11-07T03:30:00.000Z');
      expect(first.recognition, isA<sw.UnconfirmedRecognition>());
      expect(first.source.dataMode, sw.DataMode.live);
      expect(first.source.sourceUrl, startsWith('https://'));
      expect(first.source.license, contains('ODbL'));
      expect(first.source.limitations.join(), contains('未經店家確認'));
      expect(pointProblems(first), isEmpty);
      expect(points.firstWhere((p) => p.id == 'osm-way-12').name, '便利商店（無名稱）');
    });

    test('one bad record does not drop the others', () async {
      final transport = FakeTransport(
        (_) async => reply([
          {'type': 'node', 'id': 1},
          {'type': 'node', 'id': '2', 'lat': 25.0, 'lon': 121.5},
          {'type': 'node', 'id': 3, 'lat': 200.0, 'lon': 121.5},
          'junk',
          node(4, 25.0485, 121.5175, name: '好的'),
        ]),
      );

      final points = await source(transport).findNear(origin);

      expect(points.map((p) => p.id), ['osm-node-4']);
    });

    test('only an exact 24/7 tag counts as open', () async {
      final transport = FakeTransport(
        (_) async => reply([
          node(1, 25.0485, 121.5175, hours: '24/7'),
          node(2, 25.0486, 121.5176, hours: 'Mo-Su 07:00-23:00'),
          node(3, 25.0487, 121.5177, hours: null),
        ]),
      );

      final points = await source(
        transport,
        only24Hours: false,
      ).findNear(origin);

      expect(
        points
            .where((p) => p.availability == sw.OpeningStatus.open)
            .map((p) => p.id),
        ['osm-node-1'],
      );
      final others = points.where((p) => p.id != 'osm-node-1');
      expect(others, hasLength(2));
      for (final point in others) {
        expect(point.availability, sw.OpeningStatus.unknown);
        expect(point.availabilityCheckedAt, isNull);
        expect(pointProblems(point), isEmpty);
      }
    });

    test(
      'works with nearestPoints and never offers an unknown store as open',
      () async {
        final transport = FakeTransport(
          (_) async => reply([
            node(1, 25.0600, 121.5300, name: '遠'),
            node(2, 25.0485, 121.5175, name: '近'),
            node(3, 25.0479, 121.5171, hours: null, name: '更近但營業未知'),
          ]),
        );

        final points = await source(
          transport,
          only24Hours: false,
        ).findNear(origin);
        final nearest = nearestPoints(origin: origin, points: points, now: now);

        expect(nearest.map((n) => n.point.name), ['近', '遠']);
      },
    );
  });

  group('radii', () {
    test('both radii are requested at once', () async {
      final gate = Completer<Object?>();
      final transport = FakeTransport((_) => gate.future);

      final pending = source(
        transport,
        endpoints: const ['https://a.test/x'],
      ).findNear(origin);
      await Future<void>.delayed(Duration.zero);

      expect(transport.calls, hasLength(2));
      gate.complete(reply([node(1, 25.0485, 121.5175)]));
      expect(await pending, isNotEmpty);
    });

    test('a store in the small radius wins', () async {
      final transport = FakeTransport(
        (call) async => reply(
          radiusOf(call) < 5000
              ? [node(1, 25.0485, 121.5175, name: '近')]
              : [node(2, 25.1, 121.6, name: '遠')],
        ),
      );

      final points = await source(transport).findNear(origin);

      expect(points.map((p) => p.name), ['近']);
    });

    test(
      'falls back to the large radius when the small one is empty',
      () async {
        final transport = FakeTransport(
          (call) async => reply(
            radiusOf(call) < 5000 ? [] : [node(2, 25.1, 121.6, name: '遠')],
          ),
        );

        final points = await source(transport).findNear(origin);

        expect(points.map((p) => p.name), ['遠']);
      },
    );

    test('a failing small radius does not hide the large one', () async {
      final transport = FakeTransport(
        (call) => radiusOf(call) < 5000
            ? Future.error(
                const JsonTransportException(TransportFailure.network),
              )
            : Future.value(reply([node(2, 25.1, 121.6, name: '遠')])),
      );

      expect((await source(transport).findNear(origin)).single.name, '遠');
    });

    test('nothing anywhere is an empty list, not an error', () async {
      final transport = FakeTransport((_) async => reply([]));

      expect(await source(transport).findNear(origin), isEmpty);
    });
  });

  group('mirrors', () {
    test(
      'the first mirror to succeed wins and the others are cancelled',
      () async {
        final slow = Completer<Object?>();
        final transport = FakeTransport(
          (call) => call.url.host == 'a.test'
              ? slow.future
              : Future.value(reply([node(1, 25.0485, 121.5175)])),
        );

        final points = await source(
          transport,
          radii: const [1500],
        ).findNear(origin);

        expect(points, hasLength(1));
        final slowCall = transport.calls.firstWhere(
          (c) => c.url.host == 'a.test',
        );
        expect(slowCall.cancellation!.isCancelled, isTrue);
      },
    );

    test('a failing mirror does not fail the lookup', () async {
      final transport = FakeTransport(
        (call) => call.url.host == 'a.test'
            ? Future.error(
                const JsonTransportException(TransportFailure.network),
              )
            : Future.value(reply([node(1, 25.0485, 121.5175)])),
      );

      expect(
        await source(transport, radii: const [1500]).findNear(origin),
        hasLength(1),
      );
    });

    test('all mirrors failing throws and never invents stores', () async {
      final transport = FakeTransport(
        (_) => Future.error(
          const JsonTransportException(TransportFailure.httpStatus),
        ),
      );

      await expectLater(
        source(transport).findNear(origin),
        throwsA(isA<JsonTransportException>()),
      );
    });

    test('an answer without elements counts as malformed', () async {
      final transport = FakeTransport(
        (_) async => {'remark': 'runtime error: timeout'},
      );

      await expectLater(
        source(transport, radii: const [1500]).findNear(origin),
        throwsA(
          isA<JsonTransportException>().having(
            (e) => e.failure,
            'failure',
            TransportFailure.malformed,
          ),
        ),
      );
    });
  });

  group('cache', () {
    test('the same grid cell reuses the answer', () async {
      final transport = FakeTransport(
        (_) async => reply([node(1, 25.0485, 121.5175)]),
      );
      final s = source(transport, radii: const [1500]);

      await s.findNear(origin);
      final before = transport.calls.length;
      await s.findNear(sw.Coordinates(lat: 25.0481, lng: 121.5172));

      expect(transport.calls.length, before);
    });

    test('a different cell asks again', () async {
      final transport = FakeTransport(
        (_) async => reply([node(1, 25.0485, 121.5175)]),
      );
      final s = source(transport, radii: const [1500]);

      await s.findNear(origin);
      final before = transport.calls.length;
      await s.findNear(sw.Coordinates(lat: 25.1, lng: 121.6));

      expect(transport.calls.length, greaterThan(before));
    });

    test('a failure is not cached', () async {
      var fail = true;
      final transport = FakeTransport(
        (_) => fail
            ? Future.error(
                const JsonTransportException(TransportFailure.network),
              )
            : Future.value(reply([node(1, 25.0485, 121.5175)])),
      );
      final s = source(transport, radii: const [1500]);

      await expectLater(
        s.findNear(origin),
        throwsA(isA<JsonTransportException>()),
      );
      fail = false;

      expect(await s.findNear(origin), hasLength(1));
    });

    test('consent is checked even when the answer is cached', () async {
      var allowed = true;
      final transport = FakeTransport(
        (_) async => reply([node(1, 25.0485, 121.5175)]),
      );
      final s = OsmConvenienceStoreSource(
        transport: transport,
        hasConsent: () => allowed,
        endpoints: const ['https://a.test/x'],
        radiiMeters: const [1500],
        clock: () => now,
      );

      await s.findNear(origin);
      allowed = false;

      await expectLater(
        s.findNear(origin),
        throwsA(isA<ConsentRequiredException>()),
      );
    });
  });

  group('cancellation', () {
    test('cancelled before starting makes no request', () async {
      final transport = FakeTransport((_) async => reply([]));
      final cancellation = ManualCancellation()..cancel();

      await expectLater(
        source(transport).findNear(origin, cancellation: cancellation),
        throwsA(isA<SafeWalkCancelledException>()),
      );
      expect(transport.calls, isEmpty);
    });

    test('cancelling while waiting throws at once', () async {
      final transport = FakeTransport((_) => Completer<Object?>().future);
      final cancellation = ManualCancellation();

      final pending = source(transport)
          .findNear(origin, cancellation: cancellation);
      await Future<void>.delayed(Duration.zero);
      cancellation.cancel();

      await expectLater(pending, throwsA(isA<SafeWalkCancelledException>()));
    });
  });
}
