import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Random per-install identifier (UUID v4). It is not linked to a TownPass account.
final _random = Random.secure();
final _uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

bool isValidAnonymousHelperId(String value) => _uuidV4.hasMatch(value);

String generateAnonymousHelperId() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

abstract interface class HelperIdStore {
  Future<String?> read();
  Future<void> write(String id);
}

final class SharedPreferencesHelperIdStore implements HelperIdStore {
  static const _key = 'safe_walk.anonymous_helper_id';

  @override
  Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key);
    return value != null && isValidAnonymousHelperId(value) ? value : null;
  }

  @override
  Future<void> write(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, id);
  }
}

/// Returns the stored anonymous ID, creating and saving one on first use.
Future<String> loadOrCreateHelperId(HelperIdStore store) async {
  final existing = await store.read();
  if (existing != null) return existing;
  final id = generateAnonymousHelperId();
  await store.write(id);
  return id;
}
