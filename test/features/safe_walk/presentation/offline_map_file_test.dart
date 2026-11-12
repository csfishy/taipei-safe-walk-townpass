import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/presentation/offline_map_file_io.dart';

class _Assets extends CachingAssetBundle {
  _Assets(this.bytes, {this.corrupt = false});
  final List<int> bytes;
  final bool corrupt;
  int tileLoads = 0;
  @override
  Future<ByteData> load(String key) async {
    if (key.endsWith('.json')) {
      return ByteData.sublistView(
        Uint8List.fromList(
          utf8.encode(jsonEncode({'sha256': sha256.convert(bytes).toString()})),
        ),
      );
    }
    tileLoads++;
    return ByteData.sublistView(Uint8List.fromList(corrupt ? [0] : bytes));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'copy, warm SHA verification, corruption repair and asset update',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'safe-walk-copy-test',
      );
      try {
        final assets = _Assets([1, 2, 3]);
        Future<String> install(_Assets bundle) => installOfflineMapFile(
          bundle: bundle,
          supportDirectory: () async => directory,
        );
        final first = await install(assets);
        expect(await File(first).readAsBytes(), [1, 2, 3]);
        expect(await install(assets), first);
        expect(assets.tileLoads, 1);
        await File(first).writeAsBytes([9]);
        await install(assets);
        expect(await File(first).readAsBytes(), [1, 2, 3]);
        expect(assets.tileLoads, 2);
        final next = await install(_Assets([4, 5]));
        expect(next, isNot(first));
        expect(await File(next).readAsBytes(), [4, 5]);
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  test('corrupt asset and unwritable support path fail explicitly', () async {
    final directory = await Directory.systemTemp.createTemp(
      'safe-walk-copy-test',
    );
    try {
      await expectLater(
        installOfflineMapFile(
          bundle: _Assets([1], corrupt: true),
          supportDirectory: () async => directory,
        ),
        throwsFormatException,
      );
      final blocked = File('${directory.path}/blocked');
      await blocked.writeAsString('file, not directory');
      await expectLater(
        installOfflineMapFile(
          bundle: _Assets([1]),
          supportDirectory: () async => Directory(blocked.path),
        ),
        throwsA(isA<FileSystemException>()),
      );
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
