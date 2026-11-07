import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/platform/supabase/safe_walk_supabase_config.dart';

String _legacyKey(String role) {
  String segment(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${segment({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${segment({'role': role, 'iss': 'supabase'})}.dGVzdA';
}

void main() {
  const origin = 'https://example.supabase.co';
  const key = 'sb_publishable_artificial-test-key';

  SafeWalkSupabaseConfig environment(Map<String, String> values) =>
      SafeWalkSupabaseConfig.fromEnvironment(environment: values);

  Matcher failure(SupabaseConfigurationFailure expected) =>
      isA<SupabaseConfigurationException>().having(
        (error) => error.failure,
        'failure',
        expected,
      );

  test('publishable configuration normalizes an origin and has no bearer', () {
    final config = environment({
      'SUPABASE_URL': '$origin/',
      'SUPABASE_PUBLISHABLE_KEY': key,
    });

    expect(config.url.toString(), origin);
    expect(config.keyKind, SupabaseClientKeyKind.publishable);
    expect(config.requestHeaders, {'apikey': key});
    expect(config.toString(), isNot(contains(key)));
    expect(config.toString(), isNot(contains(origin)));
  });

  test('legacy compatibility accepts only an anon JWT', () {
    final anon = _legacyKey('anon');
    final config = environment({
      'SUPABASE_URL': origin,
      'SUPABASE_ANON_KEY': anon,
    });

    expect(config.keyKind, SupabaseClientKeyKind.legacyAnon);
    expect(config.requestHeaders, {
      'apikey': anon,
      'Authorization': 'Bearer $anon',
    });
  });

  test('publishable setting takes precedence over the compatibility key', () {
    final config = environment({
      'SUPABASE_URL': origin,
      'SUPABASE_PUBLISHABLE_KEY': key,
      'SUPABASE_ANON_KEY': _legacyKey('anon'),
    });
    expect(config.apiKey, key);
    expect(config.requestHeaders.containsKey('Authorization'), isFalse);
  });

  test('missing URL and key produce distinct fixed errors', () {
    expect(
      () => environment({'SUPABASE_PUBLISHABLE_KEY': key}),
      throwsA(failure(SupabaseConfigurationFailure.missingUrl)),
    );
    expect(
      () => environment({'SUPABASE_URL': origin}),
      throwsA(failure(SupabaseConfigurationFailure.missingKey)),
    );
  });

  test('production settings require an HTTPS origin without embedded data', () {
    for (final url in [
      'http://example.supabase.co',
      'http://localhost:8080',
      '$origin/rest/v1/',
      '$origin?key=private-data',
      '$origin#private-data',
      'https://username:password@example.supabase.co',
      'https://',
      'https://example.supabase.co:0',
      'not a URL',
    ]) {
      expect(
        () =>
            environment({'SUPABASE_URL': url, 'SUPABASE_PUBLISHABLE_KEY': key}),
        throwsA(failure(SupabaseConfigurationFailure.invalidUrl)),
        reason: 'reject non-origin or insecure configuration',
      );
    }
  });

  test('explicit HTTP test configuration remains limited to loopback', () {
    final config = SafeWalkSupabaseConfig(
      url: Uri.parse('http://127.0.0.1:1234'),
      apiKey: key,
      allowInsecureLocalhost: true,
    );
    expect(config.url.scheme, 'http');
    expect(
      () => SafeWalkSupabaseConfig(
        url: Uri.parse('http://example.com'),
        apiKey: key,
        allowInsecureLocalhost: true,
      ),
      throwsA(failure(SupabaseConfigurationFailure.invalidUrl)),
    );
  });

  test('secret, service role, malformed and misplaced keys are rejected', () {
    for (final rejected in [
      'sb_secret_artificial-test-key',
      _legacyKey('service_role'),
      _legacyKey('authenticated'),
      'not-a-key',
      'one.two.three',
      'sb_publishable_',
    ]) {
      expect(
        () => environment({
          'SUPABASE_URL': origin,
          'SUPABASE_PUBLISHABLE_KEY': rejected,
        }),
        throwsA(failure(SupabaseConfigurationFailure.invalidKey)),
      );
      expect(
        () => environment({
          'SUPABASE_URL': origin,
          'SUPABASE_ANON_KEY': rejected,
        }),
        throwsA(failure(SupabaseConfigurationFailure.invalidKey)),
      );
    }
    expect(
      () => environment({
        'SUPABASE_URL': origin,
        'SUPABASE_PUBLISHABLE_KEY': _legacyKey('anon'),
      }),
      throwsA(failure(SupabaseConfigurationFailure.invalidKey)),
    );
    expect(
      () => environment({'SUPABASE_URL': origin, 'SUPABASE_ANON_KEY': key}),
      throwsA(failure(SupabaseConfigurationFailure.invalidKey)),
    );
  });

  test('errors never expose rejected URL or elevated key', () {
    const privateUrl = 'https://name:private-password@example.supabase.co';
    final privateKey = _legacyKey('service_role');
    for (final values in [
      {'SUPABASE_URL': privateUrl, 'SUPABASE_PUBLISHABLE_KEY': key},
      {'SUPABASE_URL': origin, 'SUPABASE_ANON_KEY': privateKey},
    ]) {
      try {
        environment(values);
        fail('invalid configuration must throw');
      } on SupabaseConfigurationException catch (error) {
        expect(error.toString(), isNot(contains(privateUrl)));
        expect(error.toString(), isNot(contains('private-password')));
        expect(error.toString(), isNot(contains(privateKey)));
      }
    }
  });
}
