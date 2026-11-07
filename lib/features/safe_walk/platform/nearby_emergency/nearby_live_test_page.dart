import 'dart:async';

import 'package:flutter/material.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/emergency_contact.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/emergency_dispatch.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_alert_transport.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_alert_watcher.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_emergency_service.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// Isolated device test entry. The anonymous nearby backend is unavailable.
class NearbyLiveTestPage extends StatefulWidget {
  const NearbyLiveTestPage({
    super.key,
    required this.service,
    required this.dispatch,
    required this.contacts,
    required this.helperId,
    this.pollInterval = const Duration(seconds: 10),
  });

  final Duration pollInterval;
  final NearbyEmergencyService? service;
  final EmergencyDispatch? dispatch;
  final EmergencyContactStore? contacts;
  final String helperId;

  @override
  State<NearbyLiveTestPage> createState() => _NearbyLiveTestPageState();
}

class _NearbyLiveTestPageState extends State<NearbyLiveTestPage>
    with WidgetsBindingObserver {
  final _phone = TextEditingController();
  bool _foreground = true;
  bool _locationConsent = false;
  bool _nearbyConsent = false;
  bool _smsConsent = false;
  bool _optedIn = false;
  bool _receiving = false;
  bool _busy = false;
  int _contactRevision = 0;
  String _status = '尚未操作。';
  List<NearbyAlert> _alerts = const [];
  _PageCancellation? _operation;
  NearbyAlertWatcher? _watcher;
  StreamSubscription<NearbyAlert>? _alertSub;

  bool get _nearbyAvailable =>
      widget.service != null && widget.service!.unavailableReason == null;
  bool get _canReceive =>
      mounted && _foreground && _nearbyConsent && _receiving;
  bool _active(_PageCancellation operation) =>
      mounted &&
      _foreground &&
      identical(_operation, operation) &&
      !operation.isCancelled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    unawaited(_loadContact());
    if (_nearbyAvailable) {
      _watcher = NearbyAlertWatcher(
        service: widget.service!,
        helperId: widget.helperId,
        interval: widget.pollInterval,
      );
      _alertSub = _watcher!.alerts.listen((alert) {
        if (!_canReceive) return;
        setState(() => _alerts = [..._alerts, alert]);
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _cancel(clearConsent: true);
    } else if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _operation?.cancel();
    unawaited(_alertSub?.cancel());
    _watcher?.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _cancel({bool clearConsent = false}) {
    _operation?.cancel();
    _operation = null;
    _watcher?.stop();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _receiving = false;
      _alerts = const [];
      if (clearConsent) {
        _locationConsent = false;
        _nearbyConsent = false;
        _smsConsent = false;
      }
      _status = '已停止後續操作；已提出的發送要求無法撤回。停止接收不代表伺服器已刪除位置。';
    });
  }

  Future<void> _loadContact() async {
    final revision = _contactRevision;
    try {
      final stored = await widget.contacts?.read();
      if (!mounted || revision != _contactRevision || stored == null) return;
      setState(() => _phone.text = stored);
    } on Object {
      if (mounted && revision == _contactRevision && !_busy) {
        setState(() => _status = '無法讀取聯絡人設定，請重新儲存。');
      }
    }
  }

  Future<void> _run(
    Future<String> Function(_PageCancellation operation) action,
  ) async {
    if (_busy || !_foreground) return;
    final operation = _PageCancellation();
    _operation = operation;
    setState(() => _busy = true);
    try {
      final message = await action(operation);
      if (_active(operation)) setState(() => _status = message);
    } on Object {
      if (_active(operation)) {
        setState(() => _status = '操作未完成，無法確認結果；請檢查設定或改用電話求助。');
      }
    } finally {
      if (_active(operation)) {
        setState(() => _busy = false);
        _operation = null;
      }
    }
  }

  Future<void> _saveContact() => _run((operation) async {
    final input = _phone.text;
    if (!isValidEmergencyPhone(input)) return '電話格式不正確，請輸入 8 到 15 位數字。';
    _contactRevision++;
    await widget.contacts!.write(input);
    return '已儲存緊急聯絡人設定。';
  });

  Future<void> _toggleOptIn() => _run((operation) async {
    final next = !_optedIn;
    if (next && (!_locationConsent || !_nearbyConsent)) return '請先同意定位與附近通知。';
    _watcher?.stop();
    _receiving = false;
    await widget.service!.setHelperOptIn(
      mode: sw.DataMode.live,
      helperId: widget.helperId,
      enabled: next,
      userInitiated: true,
      cancellation: operation,
    );
    if (!_active(operation)) return '';
    _optedIn = next;
    _receiving = next && _nearbyConsent;
    if (_receiving) _watcher?.start();
    if (!next) _alerts = const [];
    return next ? '後端已接受協助設定與一次位置分享；接收僅限本頁前景。' : '後端已接受關閉協助要求。';
  });

  Future<void> _sos() => _run((operation) async {
    final result = await widget.dispatch!.sos(
      mode: sw.DataMode.live,
      senderId: widget.helperId,
      cancellation: operation,
      hasLocationConsent: () => _active(operation) && _locationConsent,
      hasNearbyConsent: () =>
          _active(operation) && _nearbyConsent && _nearbyAvailable,
      hasSmsConsent: () => _active(operation) && _smsConsent,
    );
    return result.message;
  });

  Future<void> _checkAlerts() => _run((operation) async {
    final alerts = await widget.service!.fetchPendingAlerts(widget.helperId);
    if (!_active(operation) || !_canReceive) return '';
    _alerts = alerts;
    return alerts.isEmpty ? '目前沒有新的附近求助。' : '收到 ${alerts.length} 則附近求助。';
  });

  void _consentChanged(void Function() change) {
    _cancel();
    setState(change);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _foreground && !_busy;
    return Scaffold(
      appBar: AppBar(title: const Text('安心行 緊急求助測試')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('本頁是隔離裝置測試入口。簡訊可能產生電信費用，提出要求不代表送達，亦不代表警消已受理。'),
          if (!_nearbyAvailable) const Text('附近通知不可用：可信身分、接收資格與後端安全驗證尚未完成。'),
          if (widget.dispatch == null) const Text('簡訊測試未啟用，SOS 按鈕已停用。'),
          const SizedBox(height: 12),
          TextField(
            key: const Key('contact-phone'),
            controller: _phone,
            enabled: enabled,
            onChanged: (_) => _contactRevision++,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: '緊急聯絡人電話',
              border: OutlineInputBorder(),
            ),
          ),
          OutlinedButton(
            onPressed: enabled && widget.contacts != null ? _saveContact : null,
            child: const Text('儲存緊急聯絡人'),
          ),
          CheckboxListTile(
            key: const Key('consent-location'),
            value: _locationConsent,
            onChanged: _foreground
                ? (value) =>
                      _consentChanged(() => _locationConsent = value ?? false)
                : null,
            title: const Text('同意按下操作後取得一次目前位置'),
          ),
          CheckboxListTile(
            key: const Key('consent-sms'),
            value: _smsConsent,
            onChanged: _foreground && widget.dispatch != null
                ? (value) => _consentChanged(() => _smsConsent = value ?? false)
                : null,
            title: const Text('同意以簡訊將精確座標傳給已儲存的聯絡人'),
          ),
          CheckboxListTile(
            key: const Key('consent-nearby'),
            value: _nearbyConsent,
            onChanged: _foreground && _nearbyAvailable
                ? (value) =>
                      _consentChanged(() => _nearbyConsent = value ?? false)
                : null,
            title: const Text('同意附近服務處理位置、向合資格協助者分享並接收求助'),
          ),
          FilledButton(
            key: const Key('sos'),
            onPressed:
                enabled &&
                    widget.dispatch != null &&
                    _locationConsent &&
                    (_smsConsent || (_nearbyConsent && _nearbyAvailable))
                ? _sos
                : null,
            child: const Text('SOS：依已同意的管道提出發送要求'),
          ),
          FilledButton(
            key: const Key('nearby-opt-in'),
            onPressed:
                enabled &&
                    _nearbyAvailable &&
                    (_optedIn || (_locationConsent && _nearbyConsent))
                ? _toggleOptIn
                : null,
            child: Text(_optedIn ? '關閉協助附近的人' : '開啟協助附近的人（分享一次位置）'),
          ),
          OutlinedButton(
            onPressed: enabled && _canReceive ? _checkAlerts : null,
            child: const Text('查看收到的附近求助'),
          ),
          OutlinedButton(
            key: const Key('cancel-operation'),
            onPressed: _busy || _receiving ? _cancel : null,
            child: const Text('取消後續操作與停止接收'),
          ),
          const SizedBox(height: 16),
          Text(_status, key: const Key('status')),
          for (final alert in _alerts)
            Card(
              key: Key('alert-${alert.alertId}'),
              child: ListTile(
                title: const Text('附近有人需要協助'),
                subtitle: SelectableText(nearbyAlertPopupText(alert)),
              ),
            ),
        ],
      ),
    );
  }
}

final class _PageCancellation implements SafeWalkCancellation {
  final _cancelled = Completer<void>();
  @override
  bool get isCancelled => _cancelled.isCompleted;
  @override
  Future<void> get whenCancelled => _cancelled.future;
  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }
}
