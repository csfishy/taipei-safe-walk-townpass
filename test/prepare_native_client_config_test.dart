import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/prepare_native_client_config.dart';

void main() {
  const url = 'https://reference.example.test';
  const key = 'sb_publishable_artificial_test_only';
  late Directory temporary;
  late File definitions;
  late StringBuffer output;
  late StringBuffer errors;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('native-client-config-');
    definitions = File('${temporary.path}/client.json');
    output = StringBuffer();
    errors = StringBuffer();
  });

  tearDown(() => temporary.deleteSync(recursive: true));

  int prepare(Map<String, String> environment) => prepareNativeClientConfig(
    [definitions.path],
    environment: environment,
    output: output,
    errors: errors,
  );

  test('writes only validated public client values without logging them', () {
    expect(
      prepare({
        'SUPABASE_URL': ' $url/ ',
        'SUPABASE_PUBLISHABLE_KEY': ' $key ',
        'DATABASE_PASSWORD': 'artificial-management-secret',
        'SAFE_WALK_WEB_ROUTES': 'true',
      }),
      0,
    );
    expect(jsonDecode(definitions.readAsStringSync()), {
      'SUPABASE_URL': url,
      'SUPABASE_PUBLISHABLE_KEY': key,
    });
    expect(errors.toString(), isEmpty);
    expect(output.toString(), isNot(contains('::add-mask::')));
    for (final value in [url, key, 'artificial-management-secret']) {
      expect(output.toString(), isNot(contains(value)));
    }
  });

  test('Actions masks raw and encoded key before any native build output', () {
    expect(
      prepare({
        'SUPABASE_URL': url,
        'SUPABASE_PUBLISHABLE_KEY': ' $key ',
        'GITHUB_ACTIONS': 'true',
      }),
      0,
    );
    final lines = const LineSplitter().convert(output.toString());
    expect(lines.take(3), [
      '::add-mask::$key',
      '::add-mask::${base64Encode(utf8.encode('SUPABASE_PUBLISHABLE_KEY=$key'))}',
      '::add-mask::${base64Encode(utf8.encode(key))}',
    ]);
    expect(lines.skip(3).join('\n'), isNot(contains(key)));
    expect(errors.toString(), isEmpty);
  });

  test(
    'non-Actions environment never emits masking commands or encoded key',
    () {
      expect(
        prepare({
          'SUPABASE_URL': url,
          'SUPABASE_PUBLISHABLE_KEY': key,
          'GITHUB_ACTIONS': 'false',
        }),
        0,
      );
      expect(output.toString(), isNot(contains('::add-mask::')));
      expect(output.toString(), isNot(contains(key)));
      expect(
        output.toString(),
        isNot(contains(base64Encode(utf8.encode(key)))),
      );
      expect(
        output.toString(),
        isNot(
          contains(base64Encode(utf8.encode('SUPABASE_PUBLISHABLE_KEY=$key'))),
        ),
      );
    },
  );

  for (final entry in <String, Map<String, String>>{
    'missing URL': {'SUPABASE_PUBLISHABLE_KEY': key},
    'missing key': {'SUPABASE_URL': url},
    'insecure URL': {
      'SUPABASE_URL': 'http://reference.example.test',
      'SUPABASE_PUBLISHABLE_KEY': key,
    },
    'URL with embedded credentials': {
      'SUPABASE_URL': 'https://private:password@reference.example.test',
      'SUPABASE_PUBLISHABLE_KEY': key,
    },
    'secret key': {
      'SUPABASE_URL': url,
      'SUPABASE_PUBLISHABLE_KEY': 'sb_secret_artificial_management_secret',
    },
    'legacy service role key': {
      'SUPABASE_URL': url,
      'SUPABASE_PUBLISHABLE_KEY':
          '${base64Url.encode(utf8.encode('{"alg":"HS256"}')).replaceAll('=', '')}.'
          '${base64Url.encode(utf8.encode('{"role":"service_role"}')).replaceAll('=', '')}.'
          'artificial-signature',
    },
    'no fallback to a legacy key': {
      'SUPABASE_URL': url,
      'SUPABASE_ANON_KEY': 'not-a-publishable-key',
    },
  }.entries) {
    test('${entry.key} fails before producing a build configuration', () {
      expect(prepare(entry.value), 78);
      expect(definitions.existsSync(), isFalse);
      expect(output.toString(), isEmpty);
      expect(
        errors.toString(),
        contains('Native client configuration rejected'),
      );
      for (final value in entry.value.values) {
        expect(errors.toString(), isNot(contains(value)));
      }
    });
  }

  test('write errors expose neither credentials nor caller paths', () {
    definitions.createSync();
    final privatePath = '${definitions.path}/artificial-private-path.json';
    expect(
      prepareNativeClientConfig(
        [privatePath],
        environment: {'SUPABASE_URL': url, 'SUPABASE_PUBLISHABLE_KEY': key},
        output: output,
        errors: errors,
      ),
      74,
    );
    expect(output.toString(), isEmpty);
    expect(errors.toString(), isNot(contains('artificial-private-path')));
    expect(errors.toString(), isNot(contains(key)));
  });

  test('native CI builds consume validated settings; Web stays disabled', () {
    final workflow = File('.github/workflows/build.yml').readAsStringSync();
    String job(String name) => RegExp(
      '^  $name:\\r?\\n(.*?)(?=^  [a-z][a-z-]*:|\\Z)',
      multiLine: true,
      dotAll: true,
    ).firstMatch(workflow)!.group(1)!;
    for (final platform in ['android', 'ios']) {
      final native = job(platform);
      expect(
        native,
        contains('dart run tool/prepare_native_client_config.dart'),
      );
      expect(native, contains('SUPABASE_URL: \${{ vars.SUPABASE_URL }}'));
      expect(
        native,
        contains(
          'SUPABASE_PUBLISHABLE_KEY: \${{ secrets.SUPABASE_PUBLISHABLE_KEY }}',
        ),
      );
      expect(
        native,
        contains('--dart-define-from-file="\$RUNNER_TEMP/native-client.json"'),
      );
      expect(
        native,
        contains('--supabase-config "\$RUNNER_TEMP/native-client.json"'),
      );
      expect(native, isNot(contains('continue-on-error: true')));
    }
    expect(job('check'), isNot(contains('SUPABASE_PUBLISHABLE_KEY')));
    expect(job('web'), isNot(contains('dart-define')));
  });
}
