import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_map.dart';

import 'support/fake_map_tile_provider.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final previous = SafeWalkMap.tileProviderFactoryForTesting;
  setUp(() {
    SafeWalkMap.tileProviderFactoryForTesting = FakeMapTileProvider.new;
  });
  tearDown(() {
    SafeWalkMap.tileProviderFactoryForTesting = previous;
  });
  try {
    await testMain();
  } finally {
    SafeWalkMap.tileProviderFactoryForTesting = previous;
  }
}
