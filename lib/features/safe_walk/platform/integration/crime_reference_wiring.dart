import 'package:town_pass/features/safe_walk/platform/supabase/safe_walk_supabase_config.dart';
import 'package:town_pass/features/safe_walk/platform/supabase/supabase_rpc_client.dart';
import 'package:town_pass/features/safe_walk/safety_data/crime_reference/crime_reference_repository.dart';

/// M1 composition of the M4 crime reference repository with the public
/// Supabase client configuration (`--dart-define=SUPABASE_URL` plus
/// `SUPABASE_PUBLISHABLE_KEY` or legacy `SUPABASE_ANON_KEY`).
///
/// A missing or rejected configuration yields an unconfigured repository that
/// throws `SafeWalkDataUnavailable`; there is no mock fallback.
final class CrimeReferenceWiring {
  const CrimeReferenceWiring._(this.repository, this.configurationFailure);

  factory CrimeReferenceWiring.fromEnvironment({
    Map<String, String>? environment,
    SupabaseRpcClient Function(SafeWalkSupabaseConfig config)? createClient,
  }) {
    final SafeWalkSupabaseConfig config;
    try {
      config = SafeWalkSupabaseConfig.fromEnvironment(environment: environment);
    } on SupabaseConfigurationException catch (error) {
      return CrimeReferenceWiring._(
        CrimeReferenceRepository(transport: null),
        error.failure,
      );
    }
    final client = (createClient ?? _defaultClient)(config);
    return CrimeReferenceWiring._(
      CrimeReferenceRepository(transport: rpcTransport(client)),
      null,
    );
  }

  final CrimeReferenceRepository repository;

  /// Why the repository is unconfigured; null when configured.
  final SupabaseConfigurationFailure? configurationFailure;

  static SupabaseRpcClient _defaultClient(SafeWalkSupabaseConfig config) =>
      SupabaseRpcClient(config: config);

  /// Adapts the generic RPC client to the M4 transport contract.
  static CrimeReferenceRpcTransport rpcTransport(SupabaseRpcClient client) =>
      (arguments, {cancellation}) async {
        final response = await client.call(
          crimeReferenceRpcFunction,
          arguments,
          cancellation: cancellation,
        );
        return CrimeReferenceHttpResponse(response.statusCode, response.body);
      };
}
