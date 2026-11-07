import 'dart:convert';
import 'dart:io';

import 'package:town_pass/features/safe_walk/platform/supabase/safe_walk_supabase_config.dart';

/// Produces only public client dart-defines; never connects to the database.
/// Native CI uses the same validator as the app and refuses missing settings.
int prepareNativeClientConfig(
  List<String> arguments, {
  required Map<String, String> environment,
  required StringSink output,
  required StringSink errors,
}) {
  if (arguments.length != 1 || arguments.single.isEmpty) {
    errors.writeln(
      'Usage: dart tool/prepare_native_client_config.dart <output.json>',
    );
    return 64;
  }

  final SafeWalkSupabaseConfig config;
  try {
    // Release builds deliberately accept only a publishable key. Do not forward
    // process secrets or silently fall back to a different project's anon key.
    config = SafeWalkSupabaseConfig.fromEnvironment(
      environment: {
        'SUPABASE_URL': environment['SUPABASE_URL'] ?? '',
        'SUPABASE_PUBLISHABLE_KEY':
            environment['SUPABASE_PUBLISHABLE_KEY'] ?? '',
      },
    );
  } on SupabaseConfigurationException catch (error) {
    errors.writeln(
      'Native client configuration rejected: ${error.failure.name}. '
      'Set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY before building.',
    );
    return 78;
  }

  if (environment['GITHUB_ACTIONS'] == 'true') {
    // Flutter includes encoded dart-defines in failed native build commands.
    // GitHub's automatic raw-secret mask does not cover these derived values.
    for (final value in [
      config.apiKey,
      base64Encode(utf8.encode('SUPABASE_PUBLISHABLE_KEY=${config.apiKey}')),
      base64Encode(utf8.encode(config.apiKey)),
    ]) {
      output.writeln('::add-mask::$value');
    }
  }

  try {
    final file = File(arguments.single);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      jsonEncode({
        'SUPABASE_URL': config.url.toString(),
        'SUPABASE_PUBLISHABLE_KEY': config.apiKey,
      }),
      flush: true,
    );
  } catch (_) {
    // Filesystem exceptions can contain a caller-provided path or contents.
    errors.writeln('Could not write the native client configuration file.');
    return 74;
  }
  output.writeln('Native public client configuration validated and prepared.');
  return 0;
}

void main(List<String> arguments) {
  exitCode = prepareNativeClientConfig(
    arguments,
    environment: Platform.environment,
    output: stdout,
    errors: stderr,
  );
}
