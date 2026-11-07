import 'dart:convert';
import 'dart:io';

import 'package:town_pass/features/safe_walk/platform/supabase/safe_walk_supabase_config.dart';
import 'package:town_pass/features/safe_walk/platform/supabase/supabase_connection.dart';

/// Explicit, read-only native connection check; never calls an alert RPC.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln(
      'Usage: dart tool/check_supabase_connection.dart '
      '<local-dart-defines.json>',
    );
    exitCode = 64;
    return;
  }

  final SafeWalkSupabaseConfig config;
  try {
    final value = jsonDecode(await File(arguments.single).readAsString());
    if (value is! Map<String, dynamic> ||
        value.values.any((element) => element is! String)) {
      throw const FormatException();
    }
    config = SafeWalkSupabaseConfig.fromEnvironment(
      environment: value.cast<String, String>(),
    );
  } on SupabaseConfigurationException catch (error) {
    stderr.writeln(error);
    exitCode = 78;
    return;
  } catch (_) {
    // File/JSON errors can contain paths, rejected values, or credentials.
    stderr.writeln('Could not read the local Supabase configuration JSON.');
    exitCode = 78;
    return;
  }

  final connection = SupabaseConnection(config: config);
  try {
    final status = await connection.checkConnection();
    stdout.writeln(switch (status) {
      SupabaseConnectionStatus.apiReachable =>
        'PASS: Supabase Data API is reachable (OpenAPI verified).',
      SupabaseConnectionStatus.postgrestReachable =>
        'PASS: Supabase public key reaches PostgREST '
            '(expected missing diagnostic table).',
    });
    stdout.writeln(
      'No table rows were read or written; no alert RPC was called.',
    );
  } on SupabaseConnectionException catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  } finally {
    connection.close();
  }
}
