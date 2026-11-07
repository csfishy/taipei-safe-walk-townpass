import 'dart:async';

import 'package:geolocator/geolocator.dart' as geo;
import 'package:get/get.dart';
import 'package:town_pass/features/safe_walk/platform/platform_service.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/semantics.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;
import 'package:town_pass/service/geo_locator_service.dart';

typedef TownPassPositionReader = Future<geo.Position> Function();

/// M1's lazy, unregistered seam to the existing TownPass location service.
/// Construction never obtains a position or requests permissions.
class TownPassPlatformAdapter implements PlatformService {
  TownPassPlatformAdapter({
    TownPassPositionReader? readPosition,
    this.mockPosition,
    this.locationTimeout = const Duration(seconds: 8),
  }) : _readPosition = readPosition ?? _readFromTownPass;

  final TownPassPositionReader _readPosition;
  final sw.Position? mockPosition;
  final Duration locationTimeout;

  static Future<geo.Position> _readFromTownPass() =>
      Get.find<GeoLocatorService>().position();

  sw.LocationResult _failure(String status, String message) =>
      sw.LocationResult.fromJson({'status': status, 'message': message});

  @override
  Future<sw.LocationResult> getCurrentPosition({
    required sw.DataMode mode,
    required bool userInitiated,
    SafeWalkCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    if (!userInitiated) {
      return _failure('denied', '尚未收到明確的使用者定位操作；未取得位置。');
    }
    if (mode == sw.DataMode.mock) {
      final mock = mockPosition;
      if (mock == null || mock.toJson()['source'] != 'mock') {
        return _failure('unavailable', '尚未注入示範位置；不以真實 GPS 補足 mock。');
      }
      return sw.LocationResult.fromJson({
        'status': 'ok',
        'position': mock.toJson(),
      });
    }
    try {
      final native = _readPosition().timeout(locationTimeout);
      final position = await (cancellation == null
          ? native
          : Future.any<geo.Position>([
              native,
              cancellation.whenCancelled.then<geo.Position>(
                (_) => throw SafeWalkCancelledException(),
              ),
            ]));
      cancellation?.throwIfCancelled();
      if (!position.hasAccuracy ||
          position.isMocked ||
          position.accuracy > 100) {
        return _failure(
          'unavailable',
          position.isMocked
              ? 'TownPass 提供的是模擬位置，未作為真實起點。'
              : !position.hasAccuracy
              ? 'TownPass 尚未提供定位精度；不將缺值當成零公尺誤差。'
              : '定位精度超過 100 公尺，請重新取得起點或描述附近地標。',
        );
      }
      final convertedPosition = sw.Position.fromJson({
        'schemaVersion': '1.0.0',
        'coordinates': {'lat': position.latitude, 'lng': position.longitude},
        'source': 'gps',
        'accuracyMeters': position.accuracy,
        'observedAt': position.timestamp.toUtc().toIso8601String(),
      });
      if (positionProblems(convertedPosition).isNotEmpty) {
        return _failure('unavailable', 'TownPass 定位時間已過期或超前；請重新取得起點。');
      }
      return sw.LocationSuccess(position: convertedPosition);
    } on SafeWalkCancelledException {
      rethrow;
    } on TimeoutException {
      return _failure('timeout', 'TownPass 定位逾時；未取得可用起點。');
    } on geo.PermissionDeniedException {
      return _failure('denied', '定位權限未允許；可在系統設定調整或描述附近地標。');
    } catch (error) {
      // These are the exact, inspected errors from the unchanged official
      // GeoLocatorService. Unknown native failures remain unavailable.
      if (error == '使用者未允許定位權限' || error == '使用者未允許定位權限（永久），無法取得定位資訊') {
        return _failure('denied', '定位權限未允許；可在系統設定調整或描述附近地標。');
      }
      return _failure('unavailable', 'TownPass 未能提供位置；請確認定位服務與權限。');
    }
  }

  @override
  Future<sw.EmergencyActionResult> requestEmergency({
    required sw.DataMode mode,
    required sw.EmergencyChannel channel,
    required bool userInitiated,
    required bool allowRealCalls,
    sw.IncidentSummary? summary,
  }) async {
    // No dialer, sharing, reporting or official dispatch adapter is installed.
    // Mode/flags never imply that an external handoff happened.
    return sw.EmergencyActionResult.fromJson({
      'schemaVersion': '1.0.0',
      'channel': channel.wireValue,
      'action': !userInitiated ? 'cancelled' : 'not_configured',
      'officialReceipt': null,
      'message': !userInitiated
          ? '尚未收到使用者求助操作；未聯絡任何人。'
          : mode == sw.DataMode.mock
          ? '示範求助：不撥號、不分享位置，未通知任何人。'
          : !allowRealCalls
          ? '真實撥號未啟用；未聯絡任何人。'
          : '正式求助 Adapter 尚未配置；未撥號、未通報，沒有官方受理。',
    });
  }
}
