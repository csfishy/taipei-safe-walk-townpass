import 'dart:async';

import 'package:town_pass/features/safe_walk/platform/nearby_emergency/emergency_contact.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/emergency_message.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_alert_transport.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/sms_sender.dart';
import 'package:town_pass/features/safe_walk/platform/platform_service.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/semantics.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

final class EmergencyDispatchResult {
  const EmergencyDispatchResult({
    required this.message,
    required this.nearbyRecipients,
    required this.smsSubmitted,
    required this.located,
    this.smsStatus,
    this.nearbyRequested = false,
    this.smsRequested = false,
    this.cancelled = false,
  });

  final String message;

  /// Backend-reported recipients, when known. This does not prove delivery.
  final int? nearbyRecipients;

  /// True only when system acceptance is known; false can mean unknown.
  /// Sending and delivery remain unconfirmed even when this is true.
  final bool smsSubmitted;

  /// Null when no SMS attempt started. An interrupted/failed pending request
  /// remains [SmsHandoffStatus.outcomeUnknown], never a claim of no side effects.
  final SmsHandoffStatus? smsStatus;

  @Deprecated('Use smsSubmitted; system acceptance does not prove delivery.')
  bool get smsSent => smsSubmitted;

  final bool located;

  /// An external call started. A cancelled/failed call may still have effects.
  final bool nearbyRequested;
  final bool smsRequested;
  final bool cancelled;
}

/// One explicitly consented operation. The caller cancels its own token on
/// consent withdrawal, backgrounding, or disposal; callbacks are also checked
/// after every await and immediately before each external operation.
final class EmergencyDispatch {
  EmergencyDispatch({
    required this._platform,
    required this._transport,
    required this._sms,
    required this._contacts,
    this.radiusMeters = 500,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final PlatformService _platform;
  final NearbyAlertTransport _transport;
  final SmsSender _sms;
  final EmergencyContactStore _contacts;
  final int radiusMeters;
  final DateTime Function() _clock;

  Future<EmergencyDispatchResult> sos({
    required sw.DataMode mode,
    required String senderId,
    SafeWalkCancellation? cancellation,
    bool Function()? hasLocationConsent,
    bool Function()? hasNearbyConsent,
    bool Function()? hasSmsConsent,
  }) async {
    int? recipients;
    var located = false;
    var nearbyRequested = false;
    var smsRequested = false;
    var smsSubmitted = false;
    SmsHandoffStatus? smsStatus;
    var cancelled = false;
    String? nearbyNote;
    String? smsNote;

    EmergencyDispatchResult finish([String? note]) => EmergencyDispatchResult(
      message: [
        nearbyNote,
        smsNote,
        note,
      ].whereType<String>().where((value) => value.isNotEmpty).join('；'),
      nearbyRecipients: recipients,
      smsSubmitted: smsSubmitted,
      smsStatus: smsStatus,
      located: located,
      nearbyRequested: nearbyRequested,
      smsRequested: smsRequested,
      cancelled: cancelled,
    );

    String cancellationNote() => nearbyRequested || smsRequested
        ? '已取消後續操作；已提出的請求無法撤回，送達狀態未確認'
        : '已取消，未提出任何發送請求';

    String? stopReason() {
      if (cancellation?.isCancelled ?? false) {
        cancelled = true;
        return cancellationNote();
      }
      if (!_consented(hasLocationConsent)) {
        return '未同意或已撤回定位，已停止後續操作';
      }
      return null;
    }

    if (mode != sw.DataMode.live) {
      return finish('示範模式不傳送任何訊息。');
    }
    var stopped = stopReason();
    if (stopped != null) return finish(stopped);

    final nearbyAvailable = nearbyBackendUnavailableReason(_transport) == null;
    final nearbySelected = _consented(hasNearbyConsent);
    final smsSelected = _consented(hasSmsConsent);
    if (!nearbyAvailable) {
      nearbyNote = '附近通知無法使用：安全後端尚未完成驗證';
    } else if (!nearbySelected) {
      nearbyNote = '未同意附近通知，未提出附近通知請求';
    }
    if (!smsSelected) {
      smsNote = '未同意簡訊，未提出簡訊發送要求';
    }
    if ((!nearbyAvailable || !nearbySelected) && !smsSelected) {
      return finish();
    }

    final sw.LocationResult location;
    try {
      location = await _awaitActive(
        _platform.getCurrentPosition(
          mode: mode,
          userInitiated: true,
          cancellation: cancellation,
        ),
        cancellation,
      );
    } on SafeWalkCancelledException {
      cancelled = true;
      return finish('已取消，未提出任何發送請求');
    } on Object {
      return finish(stopReason() ?? '無法取得位置，未提出任何發送請求');
    }
    stopped = stopReason();
    if (stopped != null) return finish(stopped);
    if (location is! sw.LocationSuccess || !_validFix(location.position)) {
      return finish('無法取得新鮮且精確的 GPS 位置，未提出任何發送請求');
    }
    located = true;
    final position = location.position;

    if (nearbyAvailable && nearbySelected && _consented(hasNearbyConsent)) {
      stopped = stopReason();
      if (stopped != null) return finish(stopped);
      if (!_validFix(position)) return finish('位置已過期，已停止後續操作');
      if (senderId.trim().isEmpty || radiusMeters <= 0 || radiusMeters > 5000) {
        nearbyNote = '附近通知設定無效，未提出附近通知請求';
      } else {
        nearbyRequested = true;
        nearbyNote = '已提出附近通知請求，結果尚未確認';
        try {
          final count = await _awaitActive(
            _transport.sendEmergencyAlert(
              senderId: senderId,
              location: position.coordinates,
              radiusMeters: radiusMeters,
            ),
            cancellation,
          );
          if (count < 0) throw const FormatException();
          recipients = count;
          nearbyNote = '附近通知請求已完成（後端回報 $count 位接收者），送達尚未確認';
        } on SafeWalkCancelledException {
          cancelled = true;
          return finish(cancellationNote());
        } on Object {
          nearbyNote = '附近通知請求結果未確認，請勿視為已通知';
        }
      }
    } else if (nearbyAvailable && nearbySelected) {
      nearbyNote = '已撤回附近通知同意，未提出附近通知請求';
    }

    stopped = stopReason();
    if (stopped != null) return finish(stopped);
    if (!smsSelected || !_consented(hasSmsConsent)) {
      smsNote = '未同意或已撤回簡訊，未提出簡訊發送要求';
      return finish();
    }

    final String? contact;
    try {
      contact = await _awaitActive(_contacts.read(), cancellation);
    } on SafeWalkCancelledException {
      cancelled = true;
      return finish(cancellationNote());
    } on Object {
      return finish(stopReason() ?? '無法讀取緊急聯絡人，未提出簡訊發送要求');
    }
    stopped = stopReason();
    if (stopped != null) return finish(stopped);
    if (!_consented(hasSmsConsent)) {
      smsNote = '未同意或已撤回簡訊，未提出簡訊發送要求';
      return finish();
    }
    if (contact == null || !isValidEmergencyPhone(contact)) {
      smsNote = '尚未設定有效緊急聯絡人，未提出簡訊發送要求';
      return finish();
    }
    if (!_validFix(position)) return finish('位置已過期，未提出簡訊發送要求');

    smsRequested = true;
    smsStatus = SmsHandoffStatus.outcomeUnknown;
    smsNote = '已向系統提出簡訊發送要求，尚未確認發送或送達';
    try {
      smsStatus = await _awaitActive(
        _sms.send(
          number: normalizeEmergencyPhone(contact),
          body: buildEmergencyMessage(
            location: position.coordinates,
            sentAt: _clock(),
            accuracyMeters: position.accuracyMeters,
          ),
        ),
        cancellation,
      );
      smsSubmitted = smsStatus == SmsHandoffStatus.handedToSystem;
      smsNote = switch (smsStatus) {
        SmsHandoffStatus.handedToSystem => '已向系統提出簡訊發送要求，尚未確認發送或送達',
        SmsHandoffStatus.permissionRequired => '缺少簡訊權限，本次未提交簡訊；請先確認權限，再重新操作',
        SmsHandoffStatus.invalidRequest => '簡訊收件人或內容無效，本次未提交簡訊',
        SmsHandoffStatus.unavailable => '此裝置未提供簡訊傳送能力；請改用電話求助',
        SmsHandoffStatus.outcomeUnknown => '簡訊發送要求結果未確認，請勿視為已發送或送達',
      };
    } on SafeWalkCancelledException {
      cancelled = true;
      return finish(cancellationNote());
    } on Object {
      smsNote = '簡訊發送要求結果未確認，請勿視為已發送或送達';
    }
    return finish(stopReason());
  }

  bool _validFix(sw.Position position) {
    final coordinates = position.coordinates;
    final accuracy = position.accuracyMeters;
    return position.source == sw.PositionSource.gps &&
        coordinates.lat.isFinite &&
        coordinates.lng.isFinite &&
        coordinates.lat.abs() <= 90 &&
        coordinates.lng.abs() <= 180 &&
        accuracy != null &&
        accuracy.isFinite &&
        accuracy >= 0 &&
        accuracy <= 100 &&
        positionProblems(position, now: _clock()).isEmpty;
  }
}

bool _consented(bool Function()? callback) {
  try {
    return callback?.call() ?? false;
  } on Object {
    return false;
  }
}

Future<T> _awaitActive<T>(
  Future<T> operation,
  SafeWalkCancellation? cancellation,
) => Future.any<T>([
  operation,
  if (cancellation != null)
    cancellation.whenCancelled.then<T>(
      (_) => throw const SafeWalkCancelledException(),
    ),
]).timeout(const Duration(seconds: 15));
