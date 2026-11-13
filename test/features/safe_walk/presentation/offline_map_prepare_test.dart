import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/presentation/offline_map_file_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'production prepare rechecks a deleted or corrupted installed archive',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'safe-walk-revalidate',
      );
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => directory.path);
      try {
        final first = await prepareOfflineMapFile();
        final bytes = await File(first).length();
        await File(first).delete();
        final repaired = await prepareOfflineMapFile();
        expect(await File(repaired).exists(), isTrue);
        expect(await File(repaired).length(), bytes);
        await File(repaired).writeAsBytes([0]);
        expect(await File(await prepareOfflineMapFile()).length(), bytes);
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        await directory.delete(recursive: true);
      }
    },
  );
}
