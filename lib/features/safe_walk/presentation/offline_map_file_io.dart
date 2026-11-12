import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

final _store = OfflineMapFileStore();

/// Concurrent map views share one verified, atomic asset installation.
Future<String> prepareOfflineMapFile() => _store.prepare();

/// Share concurrent installation work, never a permanently trusted file path.
/// Each later open verifies the current metadata and the bytes on disk again.
class OfflineMapFileStore {
  OfflineMapFileStore({this.bundle, this.supportDirectory});
  final AssetBundle? bundle;
  final Future<Directory> Function()? supportDirectory;
  Future<String>? _pending;

  Future<String> prepare() {
    if (_pending != null) return _pending!;
    late final Future<String> work;
    work =
        installOfflineMapFile(
          bundle: bundle,
          supportDirectory: supportDirectory,
        ).whenComplete(() {
          if (identical(_pending, work)) _pending = null;
        });
    return _pending = work;
  }
}

Future<String> installOfflineMapFile({
  AssetBundle? bundle,
  Future<Directory> Function()? supportDirectory,
}) async {
  final assets = bundle ?? rootBundle;
  const prefix = 'assets/safe_walk/map/';
  final meta = jsonDecode(
    await assets.loadString('${prefix}taipei_basemap.meta.json', cache: false),
  ) as Map<String, dynamic>;
  final expected = meta['sha256'] as String;
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(expected)) {
    throw const FormatException('Invalid offline map digest');
  }
  final directory = Directory(
    '${(await (supportDirectory ?? getApplicationSupportDirectory)()).path}/safe_walk_map',
  );
  await directory.create(recursive: true);
  final target = File('${directory.path}/taipei-$expected.mbtiles');
  if (await target.exists() &&
      (await sha256.bind(target.openRead()).first).toString() == expected) {
    return target.path;
  }
  final bytes = await assets.load('${prefix}taipei.mbtiles');
  final data = bytes.buffer.asUint8List(
    bytes.offsetInBytes,
    bytes.lengthInBytes,
  );
  if (sha256.convert(data).toString() != expected) {
    throw const FormatException('Offline map asset checksum mismatch');
  }
  final staging = await directory.createTemp('install-');
  final temporary = File('${staging.path}/taipei.mbtiles');
  try {
    await temporary.writeAsBytes(data, flush: true);
    if ((await sha256.bind(temporary.openRead()).first).toString() !=
        expected) {
      throw const FileSystemException('Offline map copy checksum mismatch');
    }
    if (await target.exists()) {
      // Another installer may have published this same snapshot while we wrote.
      if ((await sha256.bind(target.openRead()).first).toString() == expected) {
        return target.path;
      }
      await target.delete();
    }
    await temporary.rename(target.path);
    return target.path;
  } finally {
    await staging.delete(recursive: true);
  }
}
