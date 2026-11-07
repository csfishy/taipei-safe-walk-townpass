import 'package:flutter/material.dart';
import 'package:town_pass/features/safe_walk/navigation/cancellable.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/emergency_contact.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/emergency_dispatch.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_alert_transport.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_alert_watcher.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_emergency_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// Live Safe Walk SOS page. SOS sends the real location to opted-in nearby
/// devices and to the preset contact. Use it only with devices you control.
///
/// Nothing polls in the background. Alerts are checked only when the user taps
/// the check button. Leaving the page, backgrounding it, or revoking help
/// cancels an SOS that is still in flight.
class NearbyLiveTestPage extends StatefulWidget {
  const NearbyLiveTestPage({
    super.key,
    required this.service,
    required this.dispatch,
    required this.contacts,
    required this.helperId,
  });

  /// Null when live mode is not configured. Nothing is sent in that case.
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
  bool _optedIn = false;
  bool _busy = false;
  bool _sosInFlight = false;
  bool _foreground = true;
  ManualCancellation? _sosCancellation;
  String _status = '尚未操作。';
  List<NearbyAlert> _alerts = const [];

  NearbyEmergencyService? get _service => widget.service;
  bool get _configured => _service != null && widget.dispatch != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadContact();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelSos();
    _phone.dispose();
    super.dispose();
  }

  /// `inactive` is ignored on purpose: the system location-permission dialog
  /// causes it, and that must not cancel the SOS it was requested for.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _cancelSos();
    }
  }

  /// Stops an in-flight SOS. It returns at its next checkpoint and sends no
  /// further SMS or alert. An RPC already on the wire cannot be recalled.
  void _cancelSos() {
    final cancellation = _sosCancellation;
    if (cancellation == null) return;
    _sosCancellation = null;
    cancellation.cancel();
  }

  void _showAlertPopup(NearbyAlert alert) {
    if (!mounted || !_foreground) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: Key('popup-${alert.alertId}'),
        title: const Text('附近有人需要協助'),
        content: SelectableText(nearbyAlertPopupText(alert)),
        actions: [
          TextButton(
            onPressed: () => launchUrl(
              Uri.parse(nearbyAlertMapUrl(alert)),
              mode: LaunchMode.externalApplication,
            ),
            child: const Text('開啟地圖'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadContact() async {
    final stored = await widget.contacts?.read();
    if (!mounted || stored == null) return;
    setState(() => _phone.text = stored);
  }

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

  Future<void> _saveContact() => _run(() async {
    final input = _phone.text;
    if (!isValidEmergencyPhone(input)) {
      setState(() => _status = '電話格式不正確，請輸入 8 到 15 位數字。');
      return;
    }
    await widget.contacts!.write(input);
    if (!mounted) return;
    setState(() => _status = '已儲存緊急聯絡人（只存在這支手機上）。');
  });

  Future<void> _toggleOptIn() {
    final next = !_optedIn;
    // Revoking help stops any SOS still in flight, even while another action is busy.
    if (!next) _cancelSos();
    return _run(() async {
      await _service!.setHelperOptIn(
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
  }

  Future<void> _sos() async {
    if (_busy || _sosInFlight || !_configured) return;
    final cancellation = ManualCancellation();
    _sosCancellation = cancellation;
    setState(() {
      _sosInFlight = true;
      _status = '求助進行中（離開頁面、切到背景或關閉協助會停止）…';
    });
    try {
      final result = await widget.dispatch!.sos(
        mode: sw.DataMode.live,
        senderId: widget.helperId,
        cancellation: cancellation,
      );
      if (!mounted) return;
      setState(() => _status = result.message);
    } catch (error) {
      if (mounted) setState(() => _status = '操作失敗：$error');
    } finally {
      if (identical(_sosCancellation, cancellation)) _sosCancellation = null;
      if (mounted) setState(() => _sosInFlight = false);
    }
  }

  Future<void> _checkAlerts() => _run(() async {
    final alerts = await _service!.fetchPendingAlerts(widget.helperId);
    if (!mounted) return;
    setState(() {
      _alerts = alerts;
      _status = alerts.isEmpty ? '目前沒有新的附近求助。' : '收到 ${alerts.length} 則附近求助。';
    });
    if (alerts.isNotEmpty) _showAlertPopup(alerts.first);
  });

  @override
  Widget build(BuildContext context) {
    final idle = _configured && !_busy;
    return Scaffold(
      appBar: AppBar(title: const Text('安心行 緊急求助（真實）')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: const Color(0xFFFFF4E5),
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                '警告：SOS 會把你目前的真實座標送給緊急聯絡人，'
                '並通知 500 公尺內已開啟協助的裝置。'
                '只用於你自己控制的裝置，不要用在真實危急情況。',
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (!_configured)
            const Text('未設定 SUPABASE_URL、SUPABASE_ANON_KEY 或 NEARBY_LIVE_ENABLED=true，所有按鈕已停用。'),
          const SizedBox(height: 8),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: '緊急聯絡人電話',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: idle && !_sosInFlight ? _saveContact : null,
            child: const Text('儲存緊急聯絡人'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB3261E)),
            onPressed: idle && !_sosInFlight ? _sos : null,
            child: const Text('SOS：送出座標給聯絡人並通知附近'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _configured && (!_busy || (_optedIn && _sosInFlight))
                ? _toggleOptIn
                : null,
            child: Text(_optedIn ? '關閉協助附近的人' : '開啟協助附近的人（分享一次位置）'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: idle ? _checkAlerts : null,
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
