import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/safety_data/contract_safety_data.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

Map<String, Object?> fixture(String relativePath) => (jsonDecode(
  File('test/fixtures/safe_walk/$relativePath').readAsStringSync(),
) as Map).cast<String, Object?>();

Map<String, Object?> pointJson() => fixture('valid/03-AssistancePoint.json');
Map<String, Object?> statisticsJson() =>
    fixture('valid/04-AreaStatistics.json');

void main() {
  const parser = ContractSafetyDataParser();

  group('ContractSafetyDataParser', () {
    test('preserves unknown point information without inventing evidence', () {
      final point = parser.parseAssistancePoint(pointJson());

      expect(point.availability, sw.OpeningStatus.unknown);
      expect(point.availabilityCheckedAt, isNull);
      expect(point.publicPhone, isNull);
      expect(point.address, isNull);
      expect(point.recognition, isA<sw.UnconfirmedRecognition>());
      expect(point.source.dataMode, sw.DataMode.mock);
      expect(point.source.sourceUrl, isNull);
      expect(point.source.dataUpdatedAt, isNull);
    });

    test('keeps zero cases distinct from unknown population and rate', () {
      final statistics = parser.parseAreaStatistics(statisticsJson());

      expect(statistics.caseCount, 0);
      expect(statistics.populationDenominator, isNull);
      expect(statistics.ratePer100k, isNull);
      expect(statistics.aggregation, sw.StatisticsAggregation.month);
      expect(statistics.source.dataMode, sw.DataMode.mock);
    });

    test('rejects an extra personal field without echoing its value', () {
      const marker = 'invented-personal-value-for-rejection-test';
      final json = pointJson()..['contactName'] = marker;

      expect(
        () => parser.parseAssistancePoint(json),
        throwsA(
          isA<FormatException>()
              .having((error) => error.source, 'rejected payload', isNull)
              .having(
                (error) => error.toString(),
                'error text',
                isNot(contains(marker)),
              ),
        ),
      );
    });

    test('requires nullable fields instead of silently supplying defaults', () {
      final json = pointJson()..remove('publicPhone');

      expect(() => parser.parseAssistancePoint(json), throwsFormatException);
    });

    test('rejects recognition without evidence from the negative fixture', () {
      expect(
        () => parser.parseAssistancePoint(
          fixture('invalid/05-recognition-without-evidence.json'),
        ),
        throwsFormatException,
      );
    });

    for (final path in [
      'invalid/06-invented-hourly-statistic.json',
      'invalid/07-negative-rate.json',
    ]) {
      test('rejects the statistics fixture $path', () {
        expect(
          () => parser.parseAreaStatistics(fixture(path)),
          throwsFormatException,
        );
      });
    }

    test('does not allow valid-looking evidence to certify a mock point', () {
      final json = pointJson()
        ..['recognition'] = {
          'status': 'confirmed',
          'evidenceUrl': 'https://example.org/demo-evidence',
          'checkedAt': '2026-11-07T11:30:00+08:00',
        };

      expect(() => parser.parseAssistancePoint(json), throwsFormatException);
    });

    test('rejects an opening claim without its observation time', () {
      final json = pointJson()..['availability'] = 'open';

      expect(() => parser.parseAssistancePoint(json), throwsFormatException);
    });

    test('rejects a live point without a source URL', () {
      final json = pointJson();
      (json['source'] as Map<String, Object?>)['dataMode'] = 'live';

      expect(() => parser.parseAssistancePoint(json), throwsFormatException);
    });

    test('rejects a reversed statistics period', () {
      final json = statisticsJson()..['periodEnd'] = '2025-12-31';

      expect(() => parser.parseAreaStatistics(json), throwsFormatException);
    });

    test('rejects an invented rate without its population denominator', () {
      final json = statisticsJson()..['ratePer100k'] = 20;

      expect(() => parser.parseAreaStatistics(json), throwsFormatException);
    });
  });

  group('MockSafetyDataRepository', () {
    late List<sw.AssistancePoint> points;
    late List<sw.AreaStatistics> statistics;
    late MockSafetyDataRepository repository;

    setUp(() {
      points = [parser.parseAssistancePoint(pointJson())];
      statistics = [parser.parseAreaStatistics(statisticsJson())];
      repository = MockSafetyDataRepository(
        assistancePoints: points,
        areaStatistics: statistics,
      );
    });

    test(
      'snapshots injected lists so later caller changes cannot change data',
      () async {
        points.clear();
        statistics.clear();

        expect(
          await repository.getAssistancePoints(mode: sw.DataMode.mock),
          hasLength(1),
        );
        expect(
          await repository.getAreaStatistics(mode: sw.DataMode.mock),
          hasLength(1),
        );
      },
    );

    test('returns read-only lists for both datasets', () async {
      final returnedPoints = await repository.getAssistancePoints(
        mode: sw.DataMode.mock,
      );
      final returnedStatistics = await repository.getAreaStatistics(
        mode: sw.DataMode.mock,
      );

      expect(returnedPoints.clear, throwsUnsupportedError);
      expect(returnedStatistics.clear, throwsUnsupportedError);
    });

    test('allows a configured empty mock dataset', () async {
      final empty = MockSafetyDataRepository(
        assistancePoints: const [],
        areaStatistics: const [],
      );

      expect(await empty.getAssistancePoints(mode: sw.DataMode.mock), isEmpty);
      expect(await empty.getAreaStatistics(mode: sw.DataMode.mock), isEmpty);
    });

    test(
      'reports unconfigured live data instead of returning mock or empty data',
      () async {
        await expectLater(
          repository.getAssistancePoints(mode: sw.DataMode.live),
          throwsA(isA<SafeWalkDataUnavailable>()),
        );
        await expectLater(
          repository.getAreaStatistics(mode: sw.DataMode.live),
          throwsA(isA<SafeWalkDataUnavailable>()),
        );
      },
    );

    test('rejects live points injected into the mock repository', () {
      final json = pointJson();
      (json['source'] as Map<String, Object?>)
        ..['dataMode'] = 'live'
        ..['sourceUrl'] = 'https://example.org/source';

      expect(
        () => MockSafetyDataRepository(
          assistancePoints: [parser.parseAssistancePoint(json)],
          areaStatistics: statistics,
        ),
        throwsFormatException,
      );
    });

    test('rejects live statistics injected into the mock repository', () {
      final json = statisticsJson();
      (json['source'] as Map<String, Object?>)
        ..['dataMode'] = 'live'
        ..['sourceUrl'] = 'https://example.org/source';

      expect(
        () => MockSafetyDataRepository(
          assistancePoints: points,
          areaStatistics: [parser.parseAreaStatistics(json)],
        ),
        throwsFormatException,
      );
    });

    test('rechecks semantics for a model created without this parser', () {
      final json = statisticsJson()..['periodEnd'] = '2025-12-31';
      final structurallyValid = sw.AreaStatistics.fromJson(json);

      expect(
        () => MockSafetyDataRepository(
          assistancePoints: points,
          areaStatistics: [structurallyValid],
        ),
        throwsFormatException,
      );
    });

    test('does not return either dataset after cancellation', () async {
      final cancellation = TestCancellation()..cancel();

      await expectLater(
        repository.getAssistancePoints(
          mode: sw.DataMode.mock,
          cancellation: cancellation,
        ),
        throwsA(isA<SafeWalkCancelledException>()),
      );
      await expectLater(
        repository.getAreaStatistics(
          mode: sw.DataMode.mock,
          cancellation: cancellation,
        ),
        throwsA(isA<SafeWalkCancelledException>()),
      );
    });

    test(
      'accepts an uncancelled token without starting external work',
      () async {
        final cancellation = TestCancellation();

        expect(
          await repository.getAssistancePoints(
            mode: sw.DataMode.mock,
            cancellation: cancellation,
          ),
          hasLength(1),
        );
        expect(
          await repository.getAreaStatistics(
            mode: sw.DataMode.mock,
            cancellation: cancellation,
          ),
          hasLength(1),
        );
        expect(cancellation.isCancelled, isFalse);
      },
    );
  });
}

final class TestCancellation implements SafeWalkCancellation {
  final Completer<void> _cancelled = Completer<void>();

  @override
  bool get isCancelled => _cancelled.isCompleted;

  @override
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}
