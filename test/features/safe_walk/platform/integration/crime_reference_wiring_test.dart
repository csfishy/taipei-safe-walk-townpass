import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/platform/integration/crime_reference_wiring.dart';
import 'package:town_pass/features/safe_walk/platform/supabase/safe_walk_supabase_config.dart';
import 'package:town_pass/features/safe_walk/platform/supabase/supabase_rpc_client.dart';
import 'package:town_pass/features/safe_walk/safety_data/contract_safety_data.dart';
import 'package:town_pass/features/safe_walk/safety_data/crime_reference/crime_reference_repository.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

// Artificial values only: no real key, project, record or location.
const _key = 'sb_publishable_artificial-local-test-key';

String _legacyKey(String role) {
  String part(Map<String, Object?> v) =>
      base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part({'role': role})}.c2ln';
}

final crimeReferenceTestBody = {
  'interfaceVersion': 1,
  'snapshot': {
    'snapshotId': '00000000-0000-4000-8000-000000000000',
    'label': 'artificial',
    'asOfDate': '2026-09-30',
    'importedAt': '2026-10-02T00:00:00+00:00',
    'recordCount': 3,
  },
  'sources': [
    {
      'sourceKey': 'src_a',
      'datasetId': 'artificial-dataset',
      'resourceId': null,
      'name': '人工測試來源',
      'sourceUrl': 'https://example.test/dataset',
      'resourceUrl': 'https://example.test/resource.csv',
      'license': '人工測試授權',
      'retrievedAt': '2026-10-01T00:00:00+00:00',
      'dataUpdatedAt': null,
      'recordCount': 3,
    },
  ],
  'query': <String, Object?>{},
  'totalMatching': 1,
  'records': [
    {
      'sourceKey': 'src_a',
      'sourceRecordId': 'row-1',
      'eventDate': '2026-05-01',
      'city': '臺北市',
      'district': null,
      'category': '人工類別',
      'locationText': '人工測試地點',
      'latitude': null,
      'longitude': null,
      'spatialPrecision': 'unresolved',
      'confidence': 'unknown',
      'coordinateStatus': 'not_provided',
    },
  ],
};

void main() {
  group('wiring from dart-defines', () {
    test('missing URL leaves the repository explicitly unconfigured', () {
      final wiring = CrimeReferenceWiring.fromEnvironment(environment: {});
      expect(
        wiring.configurationFailure,
        SupabaseConfigurationFailure.missingUrl,
      );
      expect(wiring.repository.isConfigured, isFalse);
      expect(
        wiring.repository.query(mode: sw.DataMode.live),
        throwsA(isA<SafeWalkDataUnavailable>()),
      );
    });

    test('a service_role JWT is rejected, never used', () {
      final wiring = CrimeReferenceWiring.fromEnvironment(
        environment: {
          'SUPABASE_URL': 'https://example.test',
          'SUPABASE_ANON_KEY': _legacyKey('service_role'),
        },
      );
      expect(
        wiring.configurationFailure,
        SupabaseConfigurationFailure.invalidKey,
      );
      expect(wiring.repository.isConfigured, isFalse);
    });

    test('publishable key configures the live repository', () {
      final wiring = CrimeReferenceWiring.fromEnvironment(
        environment: {
          'SUPABASE_URL': 'https://example.test',
          'SUPABASE_PUBLISHABLE_KEY': _key,
        },
      );
      expect(wiring.configurationFailure, isNull);
      expect(wiring.repository.isConfigured, isTrue);
    });
  });

  group('RPC over loopback HTTP', () {
    late HttpServer server;
    late Uri origin;
    late void Function(HttpRequest request, String body) handler;
    final seen = <(String, String, String?, String?, String)>[];

    setUp(() async {
      seen.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      origin = Uri.parse('http://127.0.0.1:${server.port}');
      handler = (request, _) {
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(crimeReferenceTestBody));
      };
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        seen.add((
          request.method,
          request.uri.path,
          request.headers.value('apikey'),
          request.headers.value('authorization'),
          body,
        ));
        handler(request, body);
        await request.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    CrimeReferenceRepository repository() => CrimeReferenceRepository(
      transport: CrimeReferenceWiring.rpcTransport(
        SupabaseRpcClient(
          config: SafeWalkSupabaseConfig(
            url: origin,
            apiKey: _key,
            allowInsecureLocalhost: true,
          ),
        ),
      ),
    );

    test('POSTs named arguments to the reviewed function', () async {
      final result = await repository().query(mode: sw.DataMode.live);
      expect(result.records.single.locationText, '人工測試地點');
      final (method, path, apikey, auth, body) = seen.single;
      expect(method, 'POST');
      expect(path, '/rest/v1/rpc/safe_walk_crime_reference_query');
      expect(apikey, _key);
      expect(auth, isNull); // publishable keys are not bearer JWTs
      expect(jsonDecode(body), containsPair('p_limit', 50));
    });

    test('a missing function maps to interfaceMissing', () async {
      handler = (request, _) {
        request.response
          ..statusCode = 404
          ..write(jsonEncode({'code': 'PGRST202', 'message': 'x'}));
      };
      await expectLater(
        repository().query(mode: sw.DataMode.live),
        throwsA(
          isA<CrimeReferenceQueryException>().having(
            (e) => e.failure,
            'failure',
            CrimeReferenceFailure.interfaceMissing,
          ),
        ),
      );
    });

    test('redirects are not followed', () async {
      handler = (request, _) {
        request.response
          ..statusCode = 302
          ..headers.set('location', 'https://example.test/elsewhere');
      };
      await expectLater(
        repository().query(mode: sw.DataMode.live),
        throwsA(isA<CrimeReferenceQueryException>()),
      );
      expect(seen, hasLength(1));
    });

    test('rejects a malformed function name', () {
      final client = SupabaseRpcClient(
        config: SafeWalkSupabaseConfig(
          url: origin,
          apiKey: _key,
          allowInsecureLocalhost: true,
        ),
      );
      expect(() => client.call('x/../y', const {}), throwsArgumentError);
    });
  });
}
