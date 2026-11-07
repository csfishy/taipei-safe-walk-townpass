import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 使用者的「家」。只存在這支手機；不上傳、不寫日誌、不進 repo、不放 URL。
/// [toString] 刻意不含座標，避免意外被 print／log 印出。
final class HomeLocation {
  const HomeLocation._(this.lat, this.lng);

  /// 座標必須是有限數值且在地球範圍內，否則回傳 null。
  static HomeLocation? tryCreate(double lat, double lng) {
    if (!lat.isFinite || !lng.isFinite) return null;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    return HomeLocation._(lat, lng);
  }

  final double lat;
  final double lng;

  @override
  bool operator ==(Object other) =>
      other is HomeLocation && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);

  @override
  String toString() => 'HomeLocation(redacted)';
}

/// 儲存抽象；測試用 fake，正式用 [SharedPreferencesHomeLocationStore]。
abstract interface class HomeLocationStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

final class SharedPreferencesHomeLocationStore implements HomeLocationStore {
  static const key = 'safe_walk.home_location';

  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> write(String value) async {
    await (await SharedPreferences.getInstance()).setString(key, value);
  }

  @override
  Future<void> clear() async {
    await (await SharedPreferences.getInstance()).remove(key);
  }
}

/// 家的設定：讀取、儲存（新增或編輯）、清除。資料損毀時視為未設定。
final class HomeLocationService {
  HomeLocationService(this._store);

  final HomeLocationStore _store;

  Future<HomeLocation?> load() async {
    final String? raw;
    try {
      raw = await _store.read();
    } catch (_) {
      return null;
    }
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map || json['lat'] is! num || json['lng'] is! num) {
        return null;
      }
      return HomeLocation.tryCreate(
        (json['lat'] as num).toDouble(),
        (json['lng'] as num).toDouble(),
      );
    } catch (_) {
      return null;
    }
  }

  /// 座標無效時丟 [ArgumentError]（訊息不含座標），不寫入。
  Future<HomeLocation> save(double lat, double lng) async {
    final home = HomeLocation.tryCreate(lat, lng);
    if (home == null) throw ArgumentError('Invalid home coordinates.');
    await _store.write(jsonEncode({'lat': home.lat, 'lng': home.lng}));
    return home;
  }

  Future<void> clear() => _store.clear();
}
