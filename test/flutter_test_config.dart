import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/presentation/demo_map.dart';

import 'support/fake_map_tile_provider.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final previous = DemoMap.tileProviderFactoryForTesting;
  setUp(() {
    DemoMap.tileProviderFactoryForTesting = FakeMapTileProvider.new;
  });
  tearDown(() {
    DemoMap.tileProviderFactoryForTesting = previous;
  });
  try {
    await testMain();
  } finally {
    DemoMap.tileProviderFactoryForTesting = previous;
  }
}
