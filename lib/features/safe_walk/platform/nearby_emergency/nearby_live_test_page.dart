import 'package:flutter/material.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_alert_transport.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_emergency_service.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// Standalone live test page for nearby helper alerts. It is not part of the
/// mock Safe Walk shell and is only used by `nearby_live_test_main.dart`.
///
/// Pressing the buttons sends the phone's real location to opted-in devices
/// within the radius. Use it only with devices you control.
class NearbyLiveTestPage extends StatefulWidget {
  const NearbyLiveTestPage({
    super.key,
    required this.service,
    required this.helperId,
  });

  /// Null when live testing is not configured. Nothing is sent in that case.
  final NearbyEmergencyService? service;
  final String helperId;

  @override
  State<NearbyLiveTestPage> createState() => _NearbyLiveTestPageState();
}

class _NearbyLiveTestPageState extends State<NearbyLiveTestPage> {
  bool _optedIn = false;
  bool _busy = false;
  String _status = '尚未操作。';
  List<NearbyAlert> _alerts = const [];

  NearbyEmergencyService? get _service => widget.service;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _status = '操作失敗：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleOptIn() => _run(() async {
    final service = _service!;
    final next = !_optedIn;
    await service.setHelperOptIn(
      mode: sw.DataMode.live,
      helperId: widget.helperId,
      enabled: next,
      userInitiated: true,
    );
    if (!mounted) return;
    setState(() {
      _optedIn = next;
      _status = next
          ? '已開啟協助：你的位置已送出一次，附近求助會通知你。'
          : '已關閉協助：你的位置已從資料庫移除。';
    });
  });

  Future<void> _sos() => _run(() async {
    final result = await _service!.triggerEmergency(
      mode: sw.DataMode.live,
      senderId: widget.helperId,
      userInitiated: true,
    );
    if (!mounted) return;
    setState(() {
      _status = switch (result) {
        NearbyEmergencySent(:final recipientCount) =>
          '已送出：$recipientCount 位附近的求助者會收到你的位置。',
        NearbyEmergencyNotSent(:final message) => '未送出：$message',
      };
    });
  });

  Future<void> _checkAlerts() => _run(() async {
    final alerts = await _service!.fetchPendingAlerts(widget.helperId);
    if (!mounted) return;
    setState(() {
      _alerts = alerts;
      _status = alerts.isEmpty ? '目前沒有新的附近求助。' : '收到 ${alerts.length} 則附近求助。';
    });
  });

  @override
  Widget build(BuildContext context) {
    final enabled = _service != null && !_busy;
    return Scaffold(
      appBar: AppBar(title: const Text('附近求助 真實測試')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: const Color(0xFFFFF4E5),
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                '警告：按下後會把你目前的真實位置送給 500 公尺內已開啟協助的裝置。'
                '只用於你自己控制的測試裝置，不要用在真實危急情況。',
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_service == null)
            const Text('未設定 SUPABASE_URL、SUPABASE_ANON_KEY 或 NEARBY_LIVE_ENABLED=true，所有按鈕已停用。'),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: enabled ? _toggleOptIn : null,
            child: Text(_optedIn ? '關閉協助附近的人' : '開啟協助附近的人（分享一次位置）'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB3261E)),
            onPressed: enabled ? _sos : null,
            child: const Text('SOS 通知附近求助者（送出位置）'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: enabled ? _checkAlerts : null,
            child: const Text('查看收到的附近求助'),
          ),
          const SizedBox(height: 16),
          Text(_status, key: const Key('status')),
          for (final alert in _alerts)
            ListTile(
              key: Key('alert-${alert.alertId}'),
              title: Text(
                '求助 ${alert.location.lat.toStringAsFixed(4)}, ${alert.location.lng.toStringAsFixed(4)}',
              ),
              subtitle: Text('半徑 ${alert.radiusMeters} m · ${alert.createdAt.toLocal()}'),
            ),
        ],
      ),
    );
  }
}
