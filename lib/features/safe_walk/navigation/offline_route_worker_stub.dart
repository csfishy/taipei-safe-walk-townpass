import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';

Future<T> runOfflineWorker<T>(
  T Function() work,
  SafeWalkCancellation? cancellation,
) => Future.error(UnsupportedError('Offline routing is native only'));
