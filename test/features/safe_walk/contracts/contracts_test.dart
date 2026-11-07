import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/safe_walk_contracts.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/schema_generated.dart';

const _fixtureRoot = 'test/fixtures/safe_walk';

Map<String, Object?> fixture(String name) =>
    (jsonDecode(File('$_fixtureRoot/valid/$name').readAsStringSync()) as Map)
        .cast<String, Object?>();

void main() {
  final manifest = (jsonDecode(
    File('$_fixtureRoot/manifest.json').readAsStringSync(),
  ) as List).cast<Map<String, Object?>>();

  group('cross-language canonical fixtures', () {
    for (final item in manifest) {
      final originalPath = item['file'] as String;
      final name = item['schema'] as String;
      final isValid = item['valid'] as bool;
      final path =
          '$_fixtureRoot/${originalPath.substring('fixtures/'.length)}';
      test('$originalPath is ${isValid ? 'accepted' : 'rejected'}', () {
        final value = jsonDecode(File(path).readAsStringSync());
        expect(validateContract(name, value).isEmpty, isValid);
        if (isValid) {
          final model = parseContractByName(name, value);
          expect(model.toJson(), value);
          expect(validateContract(name, model.toJson()), isEmpty);
        } else {
          expect(
            () => parseContractByName(name, value),
            throwsA(isA<ContractFormatException>()),
          );
        }
      });
    }
  });

  test('all sixteen schema entry points have generated typed parsers', () {
    expect(safeWalkContractNames, hasLength(16));
    expect(
      SafeWalkContracts.all.map((type) => type.name),
      unorderedEquals(safeWalkContractNames),
    );
    final canonical = File('schemas/safe_walk/v1/contracts.schema.json')
        .readAsStringSync();
    expect(safeWalkSchemaJson, canonical);
    final bundle = jsonDecode(canonical) as Map;
    for (final name in safeWalkContractNames) {
      final wrapper = jsonDecode(
        File('schemas/safe_walk/v1/$name.schema.json').readAsStringSync(),
      ) as Map;
      expect(wrapper[r'$ref'], '${bundle[r'$id']}#/\$defs/$name');
    }
  });

  test(
    'source provenance points to the frozen legacy main, not current checkout',
    () {
      final source = jsonDecode(
        File('schemas/safe_walk/v1/source-manifest.json').readAsStringSync(),
      ) as Map;
      expect(
        source['sourceCommit'],
        '2b13a9f5d18ad35ec0855dc3f9d8ea73c054b723',
      );
      expect(
        (source['sourceSha256'] as Map)['schemas/v1/contracts.schema.json'],
        '936beecdec368a917ddc042272ffdc94d9fd46d6c2116c4db8cff5278f0ff4d0',
      );
    },
  );

  test('typed constructors validate and supply only schema constants', () {
    final position = Position(
      coordinates: Coordinates(lat: 25, lng: 121.5),
      source: PositionSource.mock,
      accuracyMeters: null,
      observedAt: null,
    );
    expect(position.schemaVersion, '1.0.0');
    expect(position.toJson().containsKey('observedAt'), isTrue);
    expect(position.toJson()['observedAt'], isNull);
    expect(
      () => Coordinates(lat: 121, lng: 25),
      throwsA(isA<ContractFormatException>()),
    );
    expect(
      parseContract(SafeWalkContracts.position, position.toJson()),
      isA<Position>(),
    );
  });

  test(
    'required nullable fields must be present, and unknown nested fields fail',
    () {
      final missing = fixture('01-Position.json')..remove('accuracyMeters');
      expect(
        () => Position.fromJson(missing),
        throwsA(isA<ContractFormatException>()),
      );
      final extra = fixture('01-Position.json');
      (extra['coordinates'] as Map)['streetSafetyScore'] = 100;
      expect(
        () => Position.fromJson(extra),
        throwsA(isA<ContractFormatException>()),
      );
    },
  );

  test('models detach inputs and expose immutable collections', () {
    final input = fixture('06-RouteResult.json');
    final route = RouteResult.fromJson(input) as RouteSuccess;
    final encoded = route.toJson();
    (encoded['routes'] as List).clear();
    (input['routes'] as List).clear();
    expect(route.routes, hasLength(1));
    expect(() => route.routes.clear(), throwsUnsupportedError);
    expect(
      () => route.routes.first.viaPointIds.add('changed'),
      throwsUnsupportedError,
    );
  });

  test('location sealed union preserves all failure states and success', () {
    expect(
      LocationResult.fromJson({
        'status': 'ok',
        'position': fixture('01-Position.json'),
      }),
      isA<LocationSuccess>(),
    );
    for (final status in LocationFailureStatus.values) {
      final result = LocationResult.fromJson({
        'status': status.wireValue,
        'message': '沒有取得位置',
      });
      expect(result, isA<LocationFailure>());
      expect((result as LocationFailure).status, status);
    }
    expect(
      () => LocationResult.fromJson({'status': 'cancelled', 'message': '取消'}),
      throwsA(isA<ContractFormatException>()),
    );
  });

  test(
    'recognition union cannot claim evidence without its required fields',
    () {
      final confirmed = Recognition.fromJson({
        'status': 'confirmed',
        'evidenceUrl': 'https://example.org/evidence#source',
        'checkedAt': '2026-11-07T11:30:00+08:00',
      });
      expect(confirmed, isA<ConfirmedRecognition>());
      for (final status in UnconfirmedRecognitionStatus.values) {
        expect(
          Recognition.fromJson({
            'status': status.wireValue,
            'evidenceUrl': null,
            'checkedAt': null,
          }),
          isA<UnconfirmedRecognition>(),
        );
      }
      expect(
        () => Recognition.fromJson({
          'status': 'confirmed',
          'evidenceUrl': null,
          'checkedAt': null,
        }),
        throwsA(isA<ContractFormatException>()),
      );
    },
  );

  test(
    'route failures stay empty and cannot carry successful route geometry',
    () {
      expect(
        RouteResult.fromJson(fixture('06-RouteResult.json')),
        isA<RouteSuccess>(),
      );
      for (final status in RouteFailureStatus.values) {
        final input = fixture('07-RouteResult.json')
          ..['status'] = status.wireValue;
        final result = RouteResult.fromJson(input) as RouteFailure;
        expect(result.routes, isEmpty);
        expect(result.toJson()['routes'], isEmpty);
        input['routes'] = fixture('06-RouteResult.json')['routes'];
        expect(
          () => RouteResult.fromJson(input),
          throwsA(isA<ContractFormatException>()),
        );
      }
    },
  );

  test('all AppEvent union payloads remain typed and reject extra fields', () {
    final cases = <String, Object?>{
      'location.updated': fixture('01-Position.json'),
      'route.completed': fixture('06-RouteResult.json'),
      'emergency.opened': {'reason': 'threat'},
      'companion.changed': fixture('11-CompanionEvent.json'),
    };
    final expected = [
      isA<LocationUpdatedEvent>(),
      isA<RouteCompletedEvent>(),
      isA<EmergencyOpenedEvent>(),
      isA<CompanionChangedEvent>(),
    ];
    var index = 0;
    for (final entry in cases.entries) {
      final input = {'type': entry.key, 'payload': entry.value};
      expect(AppEvent.fromJson(input), expected[index++]);
      expect(
        () => AppEvent.fromJson({...input, 'officialAccepted': true}),
        throwsA(isA<ContractFormatException>()),
      );
    }
  });

  test('GeoJSON named tuple serializes longitude first and requires exactly two values', () {
    final line = LineString(
      coordinates: [
        (longitude: 121.5, latitude: 25.0),
        (longitude: 121.6, latitude: 25.1),
      ],
    );
    expect(line.toJson()['coordinates'], [
      [121.5, 25.0],
      [121.6, 25.1],
    ]);
    expect(line.coordinates.first.longitude, 121.5);
    for (final tuple in [
      [25.0, 121.5],
      [121.5, 25.0, 9],
      [121.5],
    ]) {
      expect(
        () => LineString.fromJson({
          'type': 'LineString',
          'coordinates': [tuple, tuple],
        }),
        throwsA(isA<ContractFormatException>()),
      );
    }
  });

  test('non-finite coordinates and fractional integer counts are rejected', () {
    for (final lat in [double.nan, double.infinity, double.negativeInfinity]) {
      expect(
        () => Coordinates.fromJson({'lat': lat, 'lng': 121.5}),
        throwsA(isA<ContractFormatException>()),
      );
    }
    final stats = fixture('04-AreaStatistics.json')..['caseCount'] = 1.5;
    expect(
      () => AreaStatistics.fromJson(stats),
      throwsA(isA<ContractFormatException>()),
    );
    stats['caseCount'] = 1.0; // JSON Schema integer permits mathematically integral JSON numbers.
    expect(AreaStatistics.fromJson(stats).caseCount, 1);
  });

  test(
    'datetime checks calendar dates and offsets without normalizing wire text',
    () {
      for (final value in [
        '2026-11-07T11:30:00',
        '2026-02-29T11:30:00Z',
        '2026-04-31T11:30:00Z',
        '2026-11-07T24:00:00Z',
        '2026-11-07T11:30:00+08:60',
      ]) {
        expect(
          () => Position.fromJson({
            ...fixture('01-Position.json'),
            'observedAt': value,
          }),
          throwsA(isA<ContractFormatException>()),
          reason: value,
        );
      }
      const valid = '2024-02-29T11:30:00.123+08:00';
      expect(
        Position.fromJson({...fixture('01-Position.json'), 'observedAt': valid})
            .observedAt,
        valid,
      );
      // Preserve the frozen AJV runner's lowercase-t/whitespace compatibility.
      for (final compatible in [
        '2026-11-07t11:30:00Z',
        '2026-11-07 11:30:00Z',
      ]) {
        expect(
          Position.fromJson({
            ...fixture('01-Position.json'),
            'observedAt': compatible,
          }).observedAt,
          compatible,
        );
      }
      final stats = fixture('04-AreaStatistics.json')
        ..['periodStart'] = '2026-02-30';
      expect(
        () => AreaStatistics.fromJson(stats),
        throwsA(isA<ContractFormatException>()),
      );
    },
  );

  test(
    'URI and local audio boundaries do not normalize or accept remote audio',
    () {
      final source = (fixture('03-AssistancePoint.json')['source'] as Map)
          .cast<String, Object?>();
      for (final url in [
        'http://example.org',
        'https://example.org/a b',
        'https://example.org/%GG',
        'https://example.org/台北',
      ]) {
        expect(
          () => SourceMetadata.fromJson({...source, 'sourceUrl': url}),
          throwsA(isA<ContractFormatException>()),
        );
      }
      expect(
        SourceMetadata.fromJson({
          ...source,
          'sourceUrl': 'https://example.org/#evidence',
        }).sourceUrl,
        'https://example.org/#evidence',
      );
      final scenario = fixture('10-CompanionScenario.json');
      ((scenario['steps'] as List).first as Map)['audioSrc'] =
          'https://example.org/voice.mp3';
      expect(
        () => CompanionScenario.fromJson(scenario),
        throwsA(isA<ContractFormatException>()),
      );
    },
  );

  test('JSON Schema string lengths count Unicode code points', () {
    final summary = fixture('08-IncidentSummary.json');
    summary['note'] = List.filled(500, '🙂').join();
    expect(IncidentSummary.fromJson(summary).note.runes, hasLength(500));
    summary['note'] = List.filled(501, '🙂').join();
    expect(
      () => IncidentSummary.fromJson(summary),
      throwsA(isA<ContractFormatException>()),
    );
  });

  test(
    'unique IDs, enum wire values and officialReceipt cannot silently change',
    () {
      final request = fixture('05-RouteRequest.json')
        ..['assistancePointIds'] = ['same', 'same'];
      expect(
        () => RouteRequest.fromJson(request),
        throwsA(isA<ContractFormatException>()),
      );
      expect(EmergencyChannel.police.wireValue, '110');
      expect(EmergencyChannel.fire.wireValue, '119');
      expect(CompanionReason.visibilityHidden.wireValue, 'visibility_hidden');
      final emergency = EmergencyActionResult(
        channel: EmergencyChannel.police,
        action: EmergencyAction.notConfigured,
        message: '未配置',
      );
      expect(emergency.officialReceipt, isNull);
      expect(emergency.toJson()['officialReceipt'], isNull);
      expect(
        () => EmergencyActionResult.fromJson({
          ...emergency.toJson(),
          'officialReceipt': 'fake-receipt',
        }),
        throwsA(isA<ContractFormatException>()),
      );
    },
  );

  test('validation errors contain rule paths, not private note values', () {
    final summary = fixture('08-IncidentSummary.json')
      ..['privateData'] = 'do-not-log-this-value';
    try {
      IncidentSummary.fromJson(summary);
      fail('Expected rejection');
    } on ContractFormatException catch (error) {
      expect(error.toString(), contains('privateData'));
      expect(error.toString(), isNot(contains('do-not-log-this-value')));
      expect(error.source, isNull);
    }
  });

  test(
    'cancellation is cooperative, explicit and safe to check repeatedly',
    () async {
      final cancellation = _Cancellation();
      cancellation.throwIfCancelled();
      cancellation.cancel();
      await cancellation.whenCancelled;
      expect(
        cancellation.throwIfCancelled,
        throwsA(isA<SafeWalkCancelledException>()),
      );
      expect(
        cancellation.throwIfCancelled,
        throwsA(isA<SafeWalkCancelledException>()),
      );
    },
  );
}

final class _Cancellation implements SafeWalkCancellation {
  final _completer = Completer<void>();
  @override
  bool get isCancelled => _completer.isCompleted;
  @override
  Future<void> get whenCancelled => _completer.future;
  void cancel() => _completer.complete();
}
