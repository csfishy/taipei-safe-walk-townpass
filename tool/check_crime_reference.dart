import 'dart:convert';
import 'dart:io';

import 'package:town_pass/features/safe_walk/platform/integration/crime_reference_wiring.dart';
import 'package:town_pass/features/safe_walk/platform/supabase/safe_walk_supabase_config.dart';
import 'package:town_pass/features/safe_walk/platform/supabase/supabase_rpc_client.dart';
import 'package:town_pass/features/safe_walk/safety_data/crime_reference/crime_reference_models.dart';
import 'package:town_pass/features/safe_walk/safety_data/crime_reference/crime_reference_repository.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// Explicit native smoke check through the same transport and parser as App.
/// Never obtains GPS, sends a route, writes data, or prints individual records.
Future<void> main(List<String> arguments) async {
  exitCode = await checkCrimeReference(arguments);
}

/// Returns 0 for an accepted query, 1 for a query failure, 2 when the requested
/// coordinate evidence is absent, 64 for usage, or 78 for configuration errors.
/// Injection is for isolated tests; the command uses the real native RPC client.
Future<int> checkCrimeReference(
  List<String> arguments, {
  Future<String> Function(String path)? readConfiguration,
  SupabaseRpcClient Function(SafeWalkSupabaseConfig config)? createClient,
  void Function(String message)? writeOutput,
  void Function(String message)? writeError,
}) async {
  final output = writeOutput ?? stdout.writeln;
  final error = writeError ?? stderr.writeln;
  String? city;
  var requireCoordinates = false;
  var validArguments = arguments.isNotEmpty && !arguments.first.startsWith('-');
  for (var i = 1; i < arguments.length && validArguments; i++) {
    switch (arguments[i]) {
      case '--city':
        if (city != null || i + 1 >= arguments.length) {
          validArguments = false;
        } else {
          city = arguments[++i];
          validArguments = crimeReferenceCities.contains(city);
        }
      case '--require-coordinates':
        if (requireCoordinates) validArguments = false;
        requireCoordinates = true;
      default:
        validArguments = false;
    }
  }
  if (!validArguments || (requireCoordinates && city == null)) {
    error(
      'Usage: dart tool/check_crime_reference.dart <local-dart-defines.json> '
      '[--city <臺北市|新北市|基隆市>] [--require-coordinates]\n'
      'Default: one record, no location filter. City: at most 200 records. '
      '--require-coordinates requires --city.',
    );
    return 64;
  }

  final Map<String, String> environment;
  try {
    final value = jsonDecode(
      await (readConfiguration ?? (path) => File(path).readAsString())(
        arguments.first,
      ),
    );
    if (value is! Map<String, dynamic> ||
        value.values.any((element) => element is! String)) {
      throw const FormatException();
    }
    environment = value.cast<String, String>();
  } catch (_) {
    // File/JSON exceptions may contain a path, raw input, or credentials.
    error('Could not read the local Supabase configuration JSON.');
    return 78;
  }

  final wiring = CrimeReferenceWiring.fromEnvironment(
    environment: environment,
    createClient: createClient,
  );
  if (wiring.configurationFailure case final failure?) {
    error('Supabase configuration failed: ${failure.name}');
    return 78;
  }

  try {
    final result = await wiring.repository.query(
      mode: sw.DataMode.live,
      query: CrimeReferenceQuery(city: city, limit: city == null ? 1 : 200),
    );
    // Only an identifier with the expected syntax may enter diagnostic output.
    if (!RegExp(r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')
        .hasMatch(result.snapshot.snapshotId)) {
      throw const CrimeReferenceQueryException(
        CrimeReferenceFailure.invalidResponse,
      );
    }
    final withCoordinates = result.records
        .where((record) => record.hasReferenceCoordinate)
        .length;
    final missingCoordinates = requireCoordinates && withCoordinates == 0;
    output(
      jsonEncode({
        'status': missingCoordinates ? 'no_reference_coordinates' : 'ok',
        'snapshotId': result.snapshot.snapshotId,
        'asOfDate': result.snapshot.asOfDate,
        'snapshotRecordCount': result.snapshot.recordCount,
        'sourceCount': result.sources.length,
        'totalMatching': result.totalMatching,
        'sampleRecordCount': result.records.length,
        'sampleWithCoordinates': withCoordinates,
        'sampleIsComplete': result.records.length == result.totalMatching,
      }),
    );
    return missingCoordinates ? 2 : 0;
  } on CrimeReferenceQueryException catch (failure) {
    // The repository's fixed error categories contain no response or key.
    error(failure.toString());
    return 1;
  } catch (_) {
    error('Crime reference check failed without a verified response.');
    return 1;
  }
}
