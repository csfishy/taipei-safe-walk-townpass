import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:town_pass/features/safe_walk/platform/home_location/home_location_service.dart';

// 全部使用明顯虛構的座標（接近 0,0 的海上），不是任何真實住家。
final class _FakeStore implements HomeLocationStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String v) async => value = v;
  @override
  Future<void> clear() async => value = null;
}

void main() {
  test('未設定時 load 回 null', () async {
    expect(await HomeLocationService(_FakeStore()).load(), isNull);
  });

  test('save 後可 load，編輯會覆蓋', () async {
    final service = HomeLocationService(_FakeStore());
    await service.save(0.5, 0.5);
    expect(await service.load(), HomeLocation.tryCreate(0.5, 0.5));
    await service.save(1.5, -2.5);
    expect(await service.load(), HomeLocation.tryCreate(1.5, -2.5));
  });

  test('clear 後回到未設定', () async {
    final service = HomeLocationService(_FakeStore());
    await service.save(0.5, 0.5);
    await service.clear();
    expect(await service.load(), isNull);
  });

  test('無效座標不寫入，錯誤訊息不含座標', () async {
    final store = _FakeStore();
    final service = HomeLocationService(store);
    for (final (lat, lng) in [(91.0, 0.0), (0.0, 181.0), (double.nan, 0.0)]) {
      await expectLater(
        service.save(lat, lng),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.toString(),
            'message',
            isNot(contains('91')),
          ),
        ),
      );
    }
    expect(store.value, isNull);
  });

  test('損毀資料視為未設定', () async {
    final store = _FakeStore();
    final service = HomeLocationService(store);
    for (final bad in [
      'not json',
      '[]',
      '{"lat":"a","lng":1}',
      '{"lat":999,"lng":0}',
    ]) {
      store.value = bad;
      expect(await service.load(), isNull);
    }
  });

  test('toString 不洩漏座標', () {
    expect(
      HomeLocation.tryCreate(12.3456, 65.4321).toString(),
      isNot(contains('12.3')),
    );
  });

  test('SharedPreferences store 往返', () async {
    SharedPreferences.setMockInitialValues({});
    final service = HomeLocationService(SharedPreferencesHomeLocationStore());
    expect(await service.load(), isNull);
    await service.save(0.25, 0.75);
    expect(await service.load(), HomeLocation.tryCreate(0.25, 0.75));
    await service.clear();
    expect(await service.load(), isNull);
  });
}
