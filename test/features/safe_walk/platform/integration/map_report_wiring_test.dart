import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/platform/home_location/home_location_service.dart';
import 'package:town_pass/features/safe_walk/platform/integration/map_report_wiring.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_composition_root.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_route_speaker.dart';
import 'package:town_pass/features/safe_walk/platform/supabase/supabase_rpc_client.dart';
import 'package:town_pass/features/safe_walk/presentation/mock/safe_walk_demo_data.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_flow.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_speaker.dart';
import 'package:town_pass/features/safe_walk/safety_data/contract_safety_data.dart';
import 'package:town_pass/features/safe_walk/safety_data/map_reports/map_report_repository.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

import '../supabase/fake_rpc_http.dart';

const _id = '00000000-0000-4000-8000-000000000001';
Map<String, Object?> _record([String id = _id]) => {
  'id': id,
  'category': 'lighting',
  'latitude': 0.01234,
  'longitude': 0.05678,
  'description': '人工測試',
  'reportedAt': '2026-11-08T00:00:00Z',
};
Anomaly _draft() => Anomaly(
  id: _id,
  category: AnomalyCategory.lighting,
  at: const LatLng(0.01234, 0.05678),
  firstReportedAt: DateTime.utc(2026),
  reportCount: 1,
  status: AnomalyStatus.pending,
  updates: ['人工測試'],
  mode: sw.DataMode.live,
);
MapReportHttpResponse _response(Map<String, Object?> body) =>
    MapReportHttpResponse(200, jsonEncode({'interfaceVersion': 1, ...body}));

class _Home implements HomeLocationStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> clear() async {}
  @override
  Future<void> write(String value) async {}
}

class _Speaker extends UnavailableSpeaker implements SafeWalkRouteSpeaker {
  @override
  void setLifecycleActive(bool active) {}
  @override
  Future<void> stopForEmergency() async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  test(
    'native resolve sends only the selected UUID and waits for acknowledgement',
    () async {
      final http = FakeRpcHttpClient();
      http.request.response = Future.value(
        FakeRpcResponse.text(
          jsonEncode({'interfaceVersion': 1, 'reportId': _id, 'removed': true}),
        ),
      );
      final wiring = MapReportWiring.fromEnvironment(
        environment: {
          'SUPABASE_URL': 'https://example.test',
          'SUPABASE_PUBLISHABLE_KEY': 'sb_publishable_artificial-client-key',
        },
        createClient: (config) =>
            SupabaseRpcClient(config: config, createHttpClient: () => http),
      );
      await wiring.resolve(_id);
      expect(jsonDecode(utf8.decode(http.request.written)), {
        'p_report_id': _id,
      });
      expect(http.calls, 1);
      expect(http.closes, 1);
    },
  );

  test(
    'resolve and fresh load remove only the selected persisted report',
    () async {
      const otherId = '00000000-0000-4000-8000-000000000002';
      final stored = {_id: _record(), otherId: _record(otherId)};
      final repository = MapReportRepository(
        transport: (function, args, {cancellation}) async {
          if (function == mapReportResolveRpcFunction) {
            expect(args, {'p_report_id': _id});
            final removed = stored.remove(_id) != null;
            return _response({'reportId': _id, 'removed': removed});
          }
          expect(function, mapReportQueryRpcFunction);
          return _response({
            'records': stored.values.toList(),
            'totalMatching': stored.length,
            'limit': 200,
            'offset': 0,
          });
        },
      );
      expect(await MapReportWiring(repository).load(), hasLength(2));
      await MapReportWiring(repository).resolve(_id);
      await MapReportWiring(repository).resolve(_id);
      expect((await MapReportWiring(repository).load()).single.id, otherId);
    },
  );

  testWidgets(
    'composition injects resolve and cancels its pending request on exit',
    (tester) async {
      final started = Completer<void>();
      final pending = Completer<MapReportHttpResponse>();
      SafeWalkCancellation? signal;
      final repository = MapReportRepository(
        transport: (function, args, {cancellation}) {
          expect(function, mapReportResolveRpcFunction);
          expect(args, {'p_report_id': _id});
          signal = cancellation;
          started.complete();
          return pending.future;
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SafeWalkCompositionRoot(
            liveRoutes: true,
            showLiveMap: false,
            mapReportRepository: repository,
            homeLocationStore: _Home(),
            speaker: _Speaker(),
          ),
        ),
      );
      await tester.pump();
      final flow = tester.widget<SafeWalkFlow>(find.byType(SafeWalkFlow));
      expect(flow.onResolveReport, isNotNull);
      final resolving = flow.onResolveReport!(_id);
      final expectation = expectLater(
        resolving,
        throwsA(isA<SafeWalkCancelledException>()),
      );
      await started.future;
      flow.onLeaveMap!();
      expect(signal!.isCancelled, isTrue);
      await expectation;
      pending.complete(_response({'reportId': _id, 'removed': true}));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'missing public configuration is unavailable without fallback',
    () async {
      final wiring = MapReportWiring.fromEnvironment(environment: {});
      expect(wiring.repository.isConfigured, isFalse);
      await expectLater(
        wiring.save(_draft()),
        throwsA(isA<SafeWalkDataUnavailable>()),
      );
    },
  );

  test(
    'native wiring sends submission arguments through generic RPC client',
    () async {
      final http = FakeRpcHttpClient();
      http.request.response = Future.value(
        FakeRpcResponse.text(
          jsonEncode({'interfaceVersion': 1, 'report': _record()}),
        ),
      );
      final wiring = MapReportWiring.fromEnvironment(
        environment: {
          'SUPABASE_URL': 'https://example.test',
          'SUPABASE_PUBLISHABLE_KEY': 'sb_publishable_artificial-client-key',
        },
        createClient: (config) =>
            SupabaseRpcClient(config: config, createHttpClient: () => http),
      );
      final saved = await wiring.save(_draft());
      final arguments = jsonDecode(utf8.decode(http.request.written));
      expect(arguments['p_request_id'], _id);
      expect(arguments['p_category'], 'lighting');
      expect(arguments['p_description'], '人工測試');
      expect(saved.mode, sw.DataMode.live);
      expect(saved.firstReportedAt.toUtc(), DateTime.utc(2026, 11, 8));
      expect(http.calls, 1);
      expect(http.closes, 1);
    },
  );

  test('fresh wiring reloads confirmed report with server timestamp', () async {
    Map<String, Object?>? stored;
    final repository = MapReportRepository(
      transport: (function, arguments, {cancellation}) async {
        if (function == mapReportSubmitRpcFunction) {
          stored = _record();
          return _response({'report': stored});
        }
        expect(function, mapReportQueryRpcFunction);
        return _response({
          'records': [stored],
          'totalMatching': 1,
          'limit': 200,
          'offset': 0,
        });
      },
    );
    await MapReportWiring(repository).save(_draft());
    final loaded = await MapReportWiring(repository).load();
    expect(loaded.single.id, _id);
    expect(loaded.single.mode, sw.DataMode.live);
    expect(loaded.single.at.lat, 0.01234);
    expect(loaded.single.updates, ['人工測試']);
  });

  test(
    'native HTTP acknowledgement retains full map point precision',
    () async {
      const latitude = 0.012345678901234567;
      const longitude = 0.0567890123456789123;
      final http = FakeRpcHttpClient();
      http.request.response = Future.value(
        FakeRpcResponse.text(
          jsonEncode({
            'interfaceVersion': 1,
            'report': {
              ..._record(),
              'latitude': latitude,
              'longitude': longitude,
            },
          }),
        ),
      );
      final wiring = MapReportWiring.fromEnvironment(
        environment: {
          'SUPABASE_URL': 'https://example.test',
          'SUPABASE_PUBLISHABLE_KEY': 'sb_publishable_artificial-client-key',
        },
        createClient: (config) =>
            SupabaseRpcClient(config: config, createHttpClient: () => http),
      );
      final saved = await wiring.save(
        Anomaly(
          id: _id,
          category: AnomalyCategory.lighting,
          at: const LatLng(latitude, longitude),
          firstReportedAt: DateTime.utc(2026),
          reportCount: 1,
          status: AnomalyStatus.pending,
          updates: ['人工測試'],
          mode: sw.DataMode.live,
        ),
      );
      final arguments = jsonDecode(utf8.decode(http.request.written));
      expect(arguments['p_latitude'], latitude);
      expect(arguments['p_longitude'], longitude);
      expect(saved.at.lat, latitude);
      expect(saved.at.lng, longitude);
      expect(saved.mode, sw.DataMode.live);
    },
  );

  test(
    'loads subsequent pages so avoidance does not silently omit reports',
    () async {
      final offsets = <int>[];
      final records = [
        for (var i = 0; i < 201; ++i)
          _record('00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}'),
      ];
      final wiring = MapReportWiring(
        MapReportRepository(
          transport: (function, args, {cancellation}) async {
            final offset = args['p_offset']! as int;
            offsets.add(offset);
            return _response({
              'records': records.skip(offset).take(200).toList(),
              'totalMatching': records.length,
              'limit': 200,
              'offset': offset,
            });
          },
        ),
      );
      expect(await wiring.load(), hasLength(201));
      expect(offsets, [0, 200]);
    },
  );

  testWidgets(
    'composition injects real persistence callbacks and cancels pending writes on exit',
    (tester) async {
      final requestStarted = Completer<void>();
      final pending = Completer<MapReportHttpResponse>();
      SafeWalkCancellation? signal;
      final repository = MapReportRepository(
        transport: (function, args, {cancellation}) {
          expect(function, mapReportSubmitRpcFunction);
          signal = cancellation;
          requestStarted.complete();
          return pending.future;
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SafeWalkCompositionRoot(
            liveRoutes: true,
            showLiveMap: false,
            mapReportRepository: repository,
            homeLocationStore: _Home(),
            speaker: _Speaker(),
          ),
        ),
      );
      await tester.pump();
      final flow = tester.widget<SafeWalkFlow>(find.byType(SafeWalkFlow));
      expect(flow.onLoadReports, isNotNull);
      final save = flow.onSaveReport!(_draft());
      final expectation = expectLater(
        save,
        throwsA(isA<SafeWalkCancelledException>()),
      );
      await requestStarted.future;
      flow.onLeaveMap!();
      expect(signal!.isCancelled, isTrue);
      await expectation;
      pending.complete(_response({'report': _record()}));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
