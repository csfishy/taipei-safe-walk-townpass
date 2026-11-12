import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

Future<String>? _preparing;

/// Concurrent map views share one verified, atomic asset installation.
Future<String> prepareOfflineMapFile() => _preparing ??= installOfflineMapFile()
    .catchError((Object error, StackTrace stack) {
      _preparing = null;
      Error.throwWithStackTrace(error, stack);
    });

Future<String> installOfflineMapFile({
  AssetBundle? bundle,
  Future<Directory> Function()? supportDirectory,
}) async {
  final assets = bundle ?? rootBundle;
  const prefix = 'assets/safe_walk/map/';
  final meta = jsonDecode(
    await assets.loadString('${prefix}taipei_basemap.meta.json'),
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
  final temporary = File('${target.path}.tmp');
  try {
    await temporary.writeAsBytes(data, flush: true);
    if ((await sha256.bind(temporary.openRead()).first).toString() !=
        expected) {
      throw const FileSystemException('Offline map copy checksum mismatch');
    }
    if (await target.exists()) await target.delete();
    await temporary.rename(target.path);
    return target.path;
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}
