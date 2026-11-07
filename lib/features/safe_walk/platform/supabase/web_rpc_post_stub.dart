import 'package:town_pass/features/safe_walk/platform/supabase/web_rpc_post_types.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';

/// Native builds use SupabaseRpcClient; this path never sends a request.
Future<(int, String)> webRpcPost(
  Uri url,
  Map<String, String> headers,
  String body, {
  SafeWalkCancellation? cancellation,
  Duration timeout = const Duration(seconds: 12),
  int maxBytes = 2 * 1024 * 1024,
}) => Future.error(const WebRpcPostException(WebRpcPostFailure.unsupported));
