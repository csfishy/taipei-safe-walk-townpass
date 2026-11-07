import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/safe_walk_contracts.dart';

Map<String, Object?> fixture(String name) => (jsonDecode(
  File('test/fixtures/safe_walk/valid/$name').readAsStringSync(),
) as Map).cast<String, Object?>();

void main() {
  final now = DateTime.parse('2026-11-07T11:30:00+08:00');
  Position position([Map<String, Object?> changes = const {}]) =>
      Position.fromJson({...fixture('01-Position.json'), ...changes});
  AssistancePoint point([Map<String, Object?> changes = const {}]) =>
      AssistancePoint.fromJson({
        ...fixture('03-AssistancePoint.json'),
        ...changes,
      });
  AreaStatistics statistics([Map<String, Object?> changes = const {}]) =>
      AreaStatistics.fromJson({
        ...fixture('04-AreaStatistics.json'),
        ...changes,
      });
  RouteResult route([Map<String, Object?> changes = const {}]) =>
      RouteResult.fromJson({...fixture('06-RouteResult.json'), ...changes});
  IncidentSummary summary([Map<String, Object?> changes = const {}]) =>
      IncidentSummary.fromJson({
        ...fixture('08-IncidentSummary.json'),
        ...changes,
      });

  test('mock position does not fabricate GPS accuracy', () {
    expect(positionProblems(position(), now: now), isEmpty);
  });
  test('GPS requires accuracy and observed time, independent of structural validity', () {
    expect(positionProblems(position({'source': 'gps'}), now: now), isNotEmpty);
  });
  test('GPS freshness and future tolerance preserve exact boundaries', () {
    Position gps(String time) =>
        position({'source': 'gps', 'accuracyMeters': 12, 'observedAt': time});
    expect(
      positionProblems(gps('2026-11-07T11:29:00+08:00'), now: now),
      isEmpty,
    );
    expect(
      positionProblems(gps('2026-11-07T11:28:59+08:00'), now: now),
      isNotEmpty,
    );
    expect(
      positionProblems(gps('2026-11-07T11:30:30+08:00'), now: now),
      isEmpty,
    );
    expect(
      positionProblems(gps('2026-11-07T11:30:31+08:00'), now: now),
      isNotEmpty,
    );
  });
  test('manual position is not treated as stale GPS but future observations are flagged', () {
    expect(
      positionProblems(
        position({
          'source': 'manual',
          'observedAt': '2026-11-06T11:30:00+08:00',
        }),
        now: now,
      ),
      isEmpty,
    );
    expect(
      positionProblems(
        position({'observedAt': '2026-11-08T11:30:00+08:00'}),
        now: now,
      ),
      isNotEmpty,
    );
  });
  test('live source needs a documented URL', () {
    final source = point().source.toJson()..['dataMode'] = 'live';
    expect(sourceProblems(SourceMetadata.fromJson(source)), isNotEmpty);
    source['sourceUrl'] = 'https://example.org/dataset';
    expect(sourceProblems(SourceMetadata.fromJson(source)), isEmpty);
  });
  test(
    'ordinary unknown facilities stay unknown without fabricated recognition',
    () {
      expect(pointProblems(point()), isEmpty);
    },
  );
  test(
    'partner stores need recognition and opening state needs a checked time',
    () {
      expect(pointProblems(point({'kind': 'partner_store'})), isNotEmpty);
      expect(pointProblems(point({'availability': 'open'})), isNotEmpty);
    },
  );
  test('mock cannot claim recognition even with structurally complete evidence fields', () {
    expect(
      pointProblems(
        point({
          'recognition': {
            'status': 'confirmed',
            'evidenceUrl': 'https://example.org/evidence',
            'checkedAt': '2026-11-07T11:30:00+08:00',
          },
        }),
      ),
      contains('Mock data cannot claim official recognition'),
    );
  });
  test('historical statistics require ordered periods and a documented denominator', () {
    expect(
      statisticsProblems(statistics({'periodEnd': '2025-01-01'})),
      isNotEmpty,
    );
    expect(statisticsProblems(statistics({'ratePer100k': 20})), isNotEmpty);
    expect(statisticsProblems(statistics()), isEmpty);
  });
  test('mock route references resolve against the same shared point IDs', () {
    expect(routeProblems(route(), points: [point()]), isEmpty);
    expect(
      routeProblems(route()),
      contains('Unknown point reference: demo-point-1'),
    );
  });
  test('live route cannot use mock geometry, provider or point data', () {
    final problems = routeProblems(route({'mode': 'live'}), points: [point()]);
    expect(
      problems,
      contains('Live geometry must come from a verified walking provider'),
    );
    expect(problems, contains('Mock provider cannot return live routes'));
    expect(problems, contains('Live route cannot reference demo points'));
  });
  test('live routes cannot recommend a known closed point', () {
    final source = point().source.toJson()
      ..['dataMode'] = 'live'
      ..['sourceUrl'] = 'https://example.org/points';
    final closed = point({
      'source': source,
      'availability': 'closed',
      'availabilityCheckedAt': '2026-11-07T11:30:00+08:00',
    });
    final candidate =
        ((fixture('06-RouteResult.json')['routes'] as List).first as Map)
            .cast<String, Object?>()
          ..['provider'] = 'verified-provider'
          ..['walkingNetworkVerified'] = true;
    expect(
      routeProblems(
        route({
          'mode': 'live',
          'routes': [candidate],
        }),
        points: [closed],
      ),
      contains('Do not recommend a closed point'),
    );
  });
  test(
    'via-assistance routes require a referenced point even in mock mode',
    () {
      final candidate =
          ((fixture('06-RouteResult.json')['routes'] as List).first as Map)
              .cast<String, Object?>()
            ..['viaPointIds'] = <String>[];
      expect(
        routeProblems(
          route({
            'routes': [candidate],
          }),
        ),
        contains('Via-assistance route needs a referenced point'),
      );
    },
  );
  test('route failures do not pretend successful route semantics', () {
    expect(
      routeProblems(RouteResult.fromJson(fixture('07-RouteResult.json'))),
      isEmpty,
    );
  });
  test('mock reports must never be shared with public services', () {
    expect(shareProblems(summary()), isNotEmpty);
  });
  test('precise location requires consent before an external share', () {
    final input = {'mode': 'live', 'location': position().toJson()};
    expect(shareProblems(summary(input)), isNotEmpty);
    expect(
      shareProblems(summary({...input, 'consentToShareLocation': true})),
      isEmpty,
    );
    expect(shareProblems(summary({'mode': 'live'})), isEmpty);
  });
}
