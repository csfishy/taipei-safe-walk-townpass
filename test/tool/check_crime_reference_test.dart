import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/platform/supabase/supabase_rpc_client.dart';

import '../../tool/check_crime_reference.dart';
import '../features/safe_walk/platform/integration/crime_reference_wiring_test.dart'
    show crimeReferenceTestBody;
import '../features/safe_walk/platform/supabase/fake_rpc_http.dart';

const _key = 'sb_publishable_artificial-never-output';
const _configuration = {
  'SUPABASE_URL': 'https://artificial-never-output.example',
  'SUPABASE_PUBLISHABLE_KEY': _key,
};

class _Response extends FakeRpcResponse {
  _Response(super.body, {this.code = 200}) : super.text();
  final int code;
  @override
  int get statusCode => code;
}

Map<String, dynamic> _response({bool coordinates = false}) {
  final body =
      jsonDecode(jsonEncode(crimeReferenceTestBody)) as Map<String, dynamic>;
  if (coordinates) {
    (body['records'] as List).single.addAll({
      'latitude': 25.0,
      'longitude': 121.5,
      'spatialPrecision': 'address_reference',
      'confidence': 'medium',
      'coordinateStatus': 'reference_geocoded',
    });
  }
  return body;
}

void main() {
  late List<String> output;
  late List<String> errors;
  late FakeRpcHttpClient http;
  var created = 0;

  Future<int> run(
    List<String> arguments, {
    Map<String, Object?> configuration = _configuration,
    Future<String> Function(String)? read,
  }) => checkCrimeReference(
    arguments,
    readConfiguration: read ?? (_) async => jsonEncode(configuration),
    createClient: (config) {
      created++;
      return SupabaseRpcClient(config: config, createHttpClient: () => http);
    },
    writeOutput: output.add,
    writeError: errors.add,
  );

  setUp(() {
    created = 0;
    output = [];
    errors = [];
    http = FakeRpcHttpClient()
      ..request.response = Future.value(_Response(jsonEncode(_response())));
  });

  test(
    'default reads one record without location and prints only evidence',
    () async {
      expect(await run(['private-config.json']), 0);
      final request = jsonDecode(utf8.decode(http.request.written)) as Map;
      expect(request['p_limit'], 1);
      expect(request['p_offset'], 0);
      expect(
        request.entries
            .where((e) => !['p_limit', 'p_offset'].contains(e.key))
            .every((e) => e.value == null),
        isTrue,
      );
      final evidence = jsonDecode(output.single) as Map;
      expect(evidence['status'], 'ok');
      expect(evidence['sourceCount'], 1);
      expect(evidence['sampleRecordCount'], 1);
      expect(evidence['sampleWithCoordinates'], 0);
      expect(output.single, isNot(contains('人工測試地點')));
      expect(output.single, isNot(contains('locationText')));
      expect(output.single, isNot(contains('latitude')));
      expect(output.single, isNot(contains(_key)));
      expect(output.single, isNot(contains('example')));
      expect(errors, isEmpty);
    },
  );

  test(
    'city sample proves coordinates through real parser without a bbox',
    () async {
      http.request.response = Future.value(
        _Response(jsonEncode(_response(coordinates: true))),
      );
      expect(
        await run([
          'private-config.json',
          '--city',
          '臺北市',
          '--require-coordinates',
        ]),
        0,
      );
      final request = jsonDecode(utf8.decode(http.request.written)) as Map;
      expect(request['p_limit'], 200);
      expect(request['p_city'], '臺北市');
      expect(request['p_min_lat'], isNull);
      expect(request['p_max_lng'], isNull);
      expect(jsonDecode(output.single)['sampleWithCoordinates'], 1);
      expect(output.single, isNot(contains('121.5')));
      expect(output.single, isNot(contains('25.0')));
    },
  );

  test('no coordinate evidence is a distinct nonzero result', () async {
    expect(
      await run([
        'private-config.json',
        '--city',
        '臺北市',
        '--require-coordinates',
      ]),
      2,
    );
    expect(jsonDecode(output.single)['status'], 'no_reference_coordinates');
    expect(errors, isEmpty);
  });

  test(
    'unknown response version cannot become successful smoke evidence',
    () async {
      http.request.response = Future.value(
        _Response(jsonEncode({..._response(), 'interfaceVersion': 2})),
      );
      expect(await run(['private-config.json']), 1);
      expect(errors.single, contains('invalidResponse'));
      expect(output, isEmpty);
    },
  );

  test('missing RPC is named without leaking the returned body', () async {
    http.request.response = Future.value(
      _Response(jsonEncode({'code': 'PGRST202', 'message': _key}), code: 404),
    );
    expect(await run(['private-config.json']), 1);
    expect(errors.single, contains('interfaceMissing'));
    expect(errors.single, isNot(contains(_key)));
    expect(output, isEmpty);
  });

  test(
    'invalid config and unreadable input are sanitized before network',
    () async {
      expect(await run(['private-config.json'], configuration: {}), 78);
      expect(errors.single, contains('missingUrl'));
      errors.clear();
      expect(
        await run([
          'private-config.json',
        ], read: (_) async => throw StateError(_key)),
        78,
      );
      expect(errors.single, isNot(contains(_key)));
      expect(created, 0);
      expect(http.calls, 0);
    },
  );

  test(
    'unsupported arguments cannot read the config or call the API',
    () async {
      for (final arguments in [
        <String>[],
        ['private-config.json', '--city', '臺中市'],
        ['private-config.json', '--city'],
        ['private-config.json', '--require-coordinates'],
        ['private-config.json', '--unknown'],
      ]) {
        expect(
          await run(arguments, read: (_) async => fail('must not read')),
          64,
        );
      }
      expect(created, 0);
      expect(http.calls, 0);
      expect(output, isEmpty);
    },
  );
}
