import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 使用者的「家」。本儲存服務只寫入裝置設定，不傳送網路請求或寫日誌。
/// 地圖檢視另需使用者同意載入第三方圖磚；不承諾排除系統備份。
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
  SharedPreferencesHomeLocationStore({
    Future<SharedPreferences> Function()? preferences,
  }) : _preferences = preferences ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _preferences;
  static const key = 'safe_walk.home_location';

  @override
  Future<String?> read() async => (await _preferences()).getString(key);

  @override
  Future<void> write(String value) async {
    if (!await (await _preferences()).setString(key, value)) {
      throw StateError('Unable to save home location.');
    }
  }

  @override
  Future<void> clear() async {
    if (!await (await _preferences()).remove(key)) {
      throw StateError('Unable to remove home location.');
    }
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
