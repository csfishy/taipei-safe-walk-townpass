import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/platform/integration/crime_reference_wiring.dart';
import 'package:town_pass/features/safe_walk/platform/supabase/safe_walk_supabase_config.dart';
import 'package:town_pass/features/safe_walk/platform/supabase/supabase_rpc_client.dart';
import 'package:town_pass/features/safe_walk/safety_data/crime_reference/crime_reference_models.dart';
import 'package:town_pass/features/safe_walk/safety_data/crime_reference/crime_reference_repository.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

import 'fake_rpc_http.dart';

final _config = SafeWalkSupabaseConfig(
  url: Uri.parse('https://artificial.example'),
  apiKey: 'sb_publishable_artificial-local-test-key',
);
const _query = CrimeReferenceQuery(
  bounds: CrimeReferenceBounds(
    minLat: 25,
    minLng: 121.5,
    maxLat: 25.01,
    maxLng: 121.51,
  ),
);

class _Cancel implements SafeWalkCancellation {
  final _done = Completer<void>();
  @override
  bool get isCancelled => _done.isCompleted;
  @override
  Future<void> get whenCancelled => _done.future;
  void cancel() => _done.complete();
}

void main() {
  test('pre-cancelled RPC never creates a client', () async {
    var created = 0;
    final rpc = SupabaseRpcClient(
      config: _config,
      createHttpClient: () {
        created++;
        return FakeRpcHttpClient();
      },
    );
    await expectLater(
      rpc.call(
        crimeReferenceRpcFunction,
        _query.toRpcArguments(),
        cancellation: _Cancel()..cancel(),
      ),
      throwsA(isA<SafeWalkCancelledException>()),
    );
    expect(created, 0);
  });

  test(
    'repository and wiring cancel delayed connect; a later call still works',
    () async {
      final connection = Completer<HttpClientRequest>();
      final first = FakeRpcHttpClient()..connection = connection.future;
      final second = FakeRpcHttpClient();
      final clients = [first, second];
      var created = 0;
      final rpc = SupabaseRpcClient(
        config: _config,
        createHttpClient: () => clients[created++],
      );
      final repository = CrimeReferenceRepository(
        transport: CrimeReferenceWiring.rpcTransport(rpc),
      );
      final cancellation = _Cancel();
      final expectation = expectLater(
        repository.query(
          mode: sw.DataMode.live,
          query: _query,
          cancellation: cancellation,
        ),
        throwsA(isA<SafeWalkCancelledException>()),
      );
      await first.arrived.future;
      cancellation.cancel();
      await expectation.timeout(const Duration(seconds: 1));
      expect(first.closes, greaterThan(0));
      connection.complete(first.request);
      await Future<void>.delayed(Duration.zero);
      expect(first.request.written, isEmpty);
      expect(first.request.closeCalls, 0);
      final result = await rpc.call(
        crimeReferenceRpcFunction,
        _query.toRpcArguments(),
      );
      expect(result.statusCode, 200);
      expect(created, 2);
      expect(
        jsonDecode(utf8.decode(second.request.written)),
        _query.toRpcArguments(),
      );
      expect(second.request.followRedirects, isFalse);
    },
  );

  test(
    'whole-call deadline fences late connection and permits retry',
    () async {
      final connection = Completer<HttpClientRequest>();
      final first = FakeRpcHttpClient()..connection = connection.future;
      final second = FakeRpcHttpClient();
      final clients = [first, second];
      var created = 0;
      final rpc = SupabaseRpcClient(
        config: _config,
        timeout: const Duration(milliseconds: 20),
        createHttpClient: () => clients[created++],
      );
      await expectLater(
        rpc.call(crimeReferenceRpcFunction, _query.toRpcArguments()),
        throwsA(isA<TimeoutException>()),
      );
      expect(first.closes, greaterThan(0));
      connection.complete(first.request);
      await Future<void>.delayed(Duration.zero);
      expect(first.request.written, isEmpty);
      expect(first.request.closeCalls, 0);
      expect(
        (await rpc.call(crimeReferenceRpcFunction, const {})).statusCode,
        200,
      );
      expect(created, 2);
    },
  );

  test('cancelling one call does not close a concurrent request', () async {
    final reply = Completer<HttpClientResponse>();
    final first = FakeRpcHttpClient();
    first.request.response = reply.future;
    final second = FakeRpcHttpClient();
    final clients = [first, second];
    var created = 0;
    final rpc = SupabaseRpcClient(
      config: _config,
      createHttpClient: () => clients[created++],
    );
    final cancellation = _Cancel();
    final expectation = expectLater(
      rpc.call(crimeReferenceRpcFunction, const {}, cancellation: cancellation),
      throwsA(isA<SafeWalkCancelledException>()),
    );
    await first.request.closed.future;
    final other = rpc.call(crimeReferenceRpcFunction, const {});
    cancellation.cancel();
    await expectation;
    expect((await other).statusCode, 200);
    reply.complete(FakeRpcResponse.text('{}'));
    await Future<void>.delayed(Duration.zero);
    expect(created, 2);
  });

  test(
    'response body wait is cancelled without waiting for more bytes',
    () async {
      final listening = Completer<void>();
      final bytes = StreamController<List<int>>(onListen: listening.complete);
      final client = FakeRpcHttpClient();
      client.request.response = Future.value(FakeRpcResponse(bytes.stream));
      final rpc = SupabaseRpcClient(
        config: _config,
        createHttpClient: () => client,
      );
      final cancellation = _Cancel();
      final expectation = expectLater(
        rpc.call(
          crimeReferenceRpcFunction,
          const {},
          cancellation: cancellation,
        ),
        throwsA(isA<SafeWalkCancelledException>()),
      );
      await listening.future;
      cancellation.cancel();
      await expectation.timeout(const Duration(seconds: 1));
      expect(client.closes, greaterThan(0));
      await bytes.close();
    },
  );
}
