import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/platform/integration/crime_reference_live_check_page.dart';
import 'package:town_pass/features/safe_walk/safety_data/crime_reference/crime_reference_repository.dart';

import 'crime_reference_wiring_test.dart' show crimeReferenceTestBody;

void main() {
  Widget page(CrimeReferenceRepository repository) =>
      MaterialApp(home: CrimeReferenceLiveCheckPage(repository: repository));

  testWidgets('unconfigured shows an explicit unavailable state', (
    tester,
  ) async {
    await tester.pumpWidget(page(CrimeReferenceRepository(transport: null)));
    await tester.tap(find.text('查詢'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crime-reference-error')), findsOneWidget);
    expect(find.byKey(const Key('crime-reference-count')), findsNothing);
  });

  testWidgets('shows source, dates, precision and limitation', (tester) async {
    await tester.pumpWidget(
      page(
        CrimeReferenceRepository(
          transport: (_, {cancellation}) async => CrimeReferenceHttpResponse(
            200,
            jsonEncode(crimeReferenceTestBody),
          ),
        ),
      ),
    );
    await tester.tap(find.text('查詢'));
    await tester.pumpAndSettle();
    expect(find.textContaining('資料截至 2026-09-30'), findsOneWidget);
    expect(find.textContaining('精度：無法定位'), findsOneWidget);
    expect(find.textContaining('更新 來源未提供'), findsOneWidget);
    expect(find.textContaining('人工測試授權'), findsOneWidget);
    expect(find.textContaining('不是精確案發點'), findsOneWidget);
  });

  testWidgets('server failure is named, not replaced with data', (
    tester,
  ) async {
    await tester.pumpWidget(
      page(
        CrimeReferenceRepository(
          transport: (_, {cancellation}) async => CrimeReferenceHttpResponse(
            400,
            jsonEncode({
              'code': 'P0001',
              'message': 'crime_reference_snapshot_unavailable',
            }),
          ),
        ),
      ),
    );
    await tester.tap(find.text('查詢'));
    await tester.pumpAndSettle();
    expect(find.text('審查過的資料快照目前不可用。'), findsOneWidget);
    expect(find.byKey(const Key('crime-reference-count')), findsNothing);
  });
}
