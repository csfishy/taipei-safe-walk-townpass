import 'dart:async';

import 'package:geolocator/geolocator.dart' as geo;
import 'package:get/get.dart';
import 'package:town_pass/features/safe_walk/platform/platform_service.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/semantics.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;
import 'package:town_pass/service/geo_locator_service.dart';
import 'package:url_launcher/url_launcher.dart';

typedef TownPassPositionReader = Future<geo.Position> Function();

/// Hands a URI to the operating system. Completes true only when the OS
/// accepted it (for example, the phone's dialer opened).
typedef TownPassUriLauncher = Future<bool> Function(Uri uri);

/// M1's lazy, unregistered seam to the existing TownPass location service.
/// Construction never obtains a position or requests permissions.
class TownPassPlatformAdapter implements PlatformService {
  TownPassPlatformAdapter({
    TownPassPositionReader? readPosition,
    TownPassUriLauncher? launchUri,
    this.locationTimeout = const Duration(seconds: 8),
  }) : _readPosition = readPosition ?? _readFromTownPass,
       _launchUri = launchUri ?? _launchExternally;

  final TownPassPositionReader _readPosition;
  final TownPassUriLauncher _launchUri;

  /// Opens the phone's dialer with the number filled in; the person still has
  /// to press call. Nothing is dialled or sent by the app.
  static Future<bool> _launchExternally(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);
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
      return _failure('unavailable', '測試模式不提供裝置定位或人工位置。');
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
    sw.EmergencyActionResult result(String action, String message) =>
        sw.EmergencyActionResult.fromJson({
          'schemaVersion': '1.0.0',
          'channel': channel.wireValue,
          'action': action,
          'officialReceipt': null,
          'message': message,
        });

    // Only the person's own tap, in Live mode, with the dialer switched on,
    // reaches the phone. The only thing ever done is opening the dialer: the
    // app never places a call, sends a report or dispatches anyone, so no
    // result here means connected, received or dispatched.
    if (!userInitiated) {
      return result('cancelled', '尚未收到使用者求助操作；未聯絡任何人。');
    }
    if (mode == sw.DataMode.mock) {
      return result('not_configured', '示範求助：不撥號、不分享位置，未通知任何人。');
    }
    if (!allowRealCalls) {
      return result('not_configured', '真實撥號未啟用；未聯絡任何人。');
    }
    final number = switch (channel) {
      sw.EmergencyChannel.police => '110',
      sw.EmergencyChannel.fire => '119',
      sw.EmergencyChannel.trustedContact => null,
    };
    if (number == null) {
      return result('not_configured', '尚未設定緊急聯絡人；未聯絡任何人。');
    }
    final unavailable = result(
      'failed',
      '手機無法開啟撥號畫面；沒有撥號、沒有通報。請直接用手機撥打 $number。',
    );
    try {
      final opened = await _launchUri(Uri(scheme: 'tel', path: number));
      return opened
          ? result(
              'dial_link_activated',
              '已開啟手機的撥號畫面（$number）。這只是交給手機，不代表電話已接通或已受理；請自己按下撥號。',
            )
          : unavailable;
    } on Object {
      return unavailable;
    }
  }
}
