import 'package:flutter/material.dart';
import 'package:town_pass/features/safe_walk/presentation/mock/safe_walk_demo_data.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_nearby_broadcast.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_ui.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;
import 'package:town_pass/util/tp_colors.dart';

/// 單獨一頁的緊急求助。撥號由 M1 的 PlatformService.requestEmergency 處理；M3 只送出使用者選擇。
class SafeWalkEmergencyView extends StatelessWidget {
  const SafeWalkEmergencyView({
    super.key,
    required this.mode,
    required this.allowRealCalls,
    required this.position,
    required this.onChannel,
    required this.onLocate,
    required this.onClose,
    this.onSendSms,
    this.nearbyBroadcast,
    this.nearbyPointName,
    this.statusMessage,
    this.statusIsError = false,
    this.locating = false,
  });
  final sw.DataMode mode;
  final bool allowRealCalls;
  final sw.Position? position;
  final ValueChanged<sw.EmergencyChannel> onChannel;
  final VoidCallback onLocate, onClose;

  /// M1：使用者確認後交給手機開啟簡訊（OS handoff）；回傳 true 表示已開啟簡訊 App，不代表已送達或受理。
  /// null 時為示範：只模擬「已準備好並送出」的畫面，不會真的傳送。
  final Future<bool> Function(String body)? onSendSms;

  /// M1：「通知附近的人」。null 時不顯示這張卡；有值但 unavailableReason 非 null 時只顯示原因。
  final SafeWalkNearbyBroadcast? nearbyBroadcast;
  final String? nearbyPointName;
  final String? statusMessage;
  final bool statusIsError, locating;

  @override
  Widget build(BuildContext context) {
    final notes = mode == sw.DataMode.live && allowRealCalls
        ? const ['按下後由手機開啟撥號，不代表已接通或已受理']
        : const ['目前沒有撥號設定', '未實際串接警方'];
    return Scaffold(
      backgroundColor: SwColors.bg,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: SwColors.surface,
              border: Border(top: BorderSide(color: SwColors.sos, width: 8)),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        '緊急求助',
                        style: SwText.title.copyWith(color: SwColors.sos),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        for (final n in notes) Text(n, style: SwText.secondary),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _CallButton(
                  icon: Icons.local_police_rounded,
                  title: '撥打 110 報警',
                  when: '被跟蹤、遇到可疑的人、發生衝突',
                  onTap: () => onChannel(sw.EmergencyChannel.police),
                ),
                const SizedBox(height: 12),
                _CallButton(
                  icon: Icons.local_hospital_rounded,
                  title: '撥打 119',
                  when: '受傷、身體不舒服、火災',
                  onTap: () => onChannel(sw.EmergencyChannel.fire),
                ),
                if (nearbyBroadcast != null) ...[
                  const SizedBox(height: 12),
                  SafeWalkNearbyBroadcastCard(broadcast: nearbyBroadcast!),
                ],
                const SizedBox(height: 12),
                _SmsReportCard(
                  mode: mode,
                  position: position,
                  nearbyPointName: nearbyPointName,
                  onSend: onSendSms,
                ),
                AnimatedSwitcher(
                  duration: SwMotion.of(context, 220),
                  transitionBuilder: (c, a) => SizeTransition(
                    sizeFactor: a,
                    child: FadeTransition(opacity: a, child: c),
                  ),
                  child: statusMessage == null
                      ? const SizedBox(width: double.infinity)
                      : Padding(
                          key: ValueKey(statusMessage),
                          padding: const EdgeInsets.only(top: 12),
                          child: statusIsError
                              ? SwStateMessage(
                                  icon: Icons.error_outline_rounded,
                                  title: '沒有成功',
                                  message: statusMessage!,
                                  error: true,
                                  actionLabel: position == null ? '再試一次' : null,
                                  onAction: position == null ? onLocate : null,
                                )
                              : SwStateMessage(
                                  icon: Icons.info_outline_rounded,
                                  title: '目前狀態',
                                  message: statusMessage!,
                                ),
                        ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: SwColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: SwShadow.card,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('告訴對方你在哪裡', style: SwText.bodyStrong),
                      const SizedBox(height: 6),
                      Text(
                        position == null
                            ? '還沒有位置。可以說出附近的路名、店名或明顯地標。'
                            : '${position!.source == sw.PositionSource.mock ? '示範位置（不是真實定位）' : '已取得位置'}：${position!.coordinates.lat.toStringAsFixed(5)}, ${position!.coordinates.lng.toStringAsFixed(5)}（精度 ${position!.accuracyMeters == null ? '未提供' : '約 ${position!.accuracyMeters!.round()} 公尺'}）',
                        style: SwText.body,
                      ),
                      if (position == null) ...[
                        const SizedBox(height: 8),
                        locating
                            ? Row(
                                children: [
                                  const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      color: SwColors.brand,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text('正在取得位置…', style: SwText.bodyStrong),
                                ],
                              )
                            : SwChip(
                                label: '取得目前位置',
                                icon: Icons.my_location_rounded,
                                onTap: onLocate,
                              ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: SwColors.brandSoft,
                    border: Border(
                      left: BorderSide(color: SwColors.brand, width: 4),
                    ),
                  ),
                  child: Text('先走到明亮、人多的地方，例如便利商店或派出所。', style: SwText.body),
                ),
              ],
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              color: SwColors.surface,
              border: Border(top: BorderSide(color: SwColors.border)),
            ),
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              12 + MediaQuery.paddingOf(context).bottom,
            ),
            child: SizedBox(
              width: double.infinity,
              child: SwPressable(
                onTap: onClose,
                color: SwColors.surface,
                pressedColor: SwColors.brandSoft,
                border: const BorderSide(color: SwColors.border),
                radius: 12,
                child: SizedBox(
                  height: swTouchLarge,
                  child: Center(
                    child: Text('我現在安全，關閉', style: SwText.bodyStrong),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 簡訊報警：給不方便說話的人。選情況 → 預覽內容 → 同意附上位置 → 傳送。
/// 示範模式只模擬傳送成功的畫面，不會真的發出簡訊；收件號碼由 M1 決定。
class _SmsReportCard extends StatefulWidget {
  const _SmsReportCard({
    required this.mode,
    required this.position,
    required this.nearbyPointName,
    required this.onSend,
  });
  final sw.DataMode mode;
  final sw.Position? position;
  final String? nearbyPointName;
  final Future<bool> Function(String body)? onSend;
  @override
  State<_SmsReportCard> createState() => _SmsReportCardState();
}

enum _SmsStep { draft, sending, sent, failed }

class _SmsReportCardState extends State<_SmsReportCard> {
  static const _situations = ['被跟蹤', '有人打架', '可疑人士', '身體不舒服', '其他危險'];
  String _situation = _situations.first;
  bool _shareLocation = true;
  bool _preview = false; // 預設收合，讓「傳送簡訊」在第一個畫面就看得到
  _SmsStep _step = _SmsStep.draft;

  String get _body {
    final now = DateTime.now();
    final time =
        '${now.month}/${now.day} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return SmsDraftTemplate.format(
      time: time,
      position: _shareLocation ? widget.position : null,
      situation: _situation,
      nearbyPointName: widget.nearbyPointName,
    );
  }

  bool get _usesSender =>
      widget.mode == sw.DataMode.live && widget.onSend != null;

  Future<void> _send() async {
    if (widget.mode == sw.DataMode.live && widget.onSend == null) return;
    setState(() => _step = _SmsStep.sending);
    // Mock 一律只在本地模擬，即使 M1 已注入 sender 也不呼叫，避免帶位置的內容外傳。
    bool ok;
    try {
      ok = _usesSender
          ? await widget.onSend!(_body)
          : await Future.delayed(const Duration(milliseconds: 900), () => true);
    } catch (_) {
      ok = false;
    }
    if (mounted) setState(() => _step = ok ? _SmsStep.sent : _SmsStep.failed);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mode == sw.DataMode.live && widget.onSend == null) {
      return const SwStateMessage(
        icon: Icons.sms_failed_outlined,
        title: '簡訊求助尚未配置',
        message: '未設定接收號碼或手機簡訊交接，無法送出。請使用手機電話功能聯絡 110／119。',
      );
    }
    final mock = !_usesSender;
    return AnimatedContainer(
      duration: SwMotion.of(context, 220),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SwColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _step == _SmsStep.sent ? SwColors.brand : TPColors.red200,
          width: 2,
        ),
        boxShadow: SwShadow.card,
      ),
      child: AnimatedSize(
        duration: SwMotion.of(context, 240),
        curve: SwMotion.curve,
        alignment: Alignment.topCenter,
        child: _step == _SmsStep.sent
            ? _sent(mock)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: TPColors.red50,
                        ),
                        child: const Icon(
                          Icons.sms_rounded,
                          color: SwColors.sos,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '簡訊報警',
                              style: SwText.bodyStrong.copyWith(
                                color: SwColors.sos,
                              ),
                            ),
                            Text('不方便說話時，用文字通知', style: SwText.secondary),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('發生什麼事？', style: SwText.bodyStrong),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in _situations)
                        SwPressable(
                          onTap: _step == _SmsStep.sending
                              ? null
                              : () => setState(() => _situation = s),
                          selected: _situation == s,
                          color: _situation == s
                              ? TPColors.red50
                              : SwColors.surface,
                          border: BorderSide(
                            color: _situation == s
                                ? SwColors.sos
                                : SwColors.border,
                            width: _situation == s ? 2 : 1,
                          ),
                          radius: 24,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: SizedBox(
                            height: swTouch,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_situation == s) ...[
                                  const Icon(
                                    Icons.check_rounded,
                                    size: 18,
                                    color: SwColors.sos,
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Text(
                                  s,
                                  style: SwText.bodyStrong.copyWith(
                                    color: _situation == s
                                        ? SwColors.sos
                                        : SwColors.text,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '收件：${SmsDraftTemplate.recipient ?? '報案簡訊號碼（尚未設定）'}',
                    style: SwText.secondary,
                  ),
                  const SizedBox(height: 6),
                  SwPressable(
                    onTap: () => setState(() => _preview = !_preview),
                    color: SwColors.bg,
                    pressedColor: SwColors.brandSoft,
                    radius: 12,
                    semanticsLabel: _preview ? '收合簡訊內容' : '查看簡訊內容',
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: SizedBox(
                      height: swTouch,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('查看簡訊內容', style: SwText.bodyStrong),
                          ),
                          Icon(
                            _preview
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                            color: SwColors.textSecondary,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_preview)
                    Semantics(
                      label: '簡訊內容預覽',
                      child: AnimatedSwitcher(
                        duration: SwMotion.of(context, 180),
                        child: Container(
                          key: ValueKey('$_situation$_shareLocation'),
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: SwColors.bg,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(_body, style: SwText.body),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Material(
                    type: MaterialType.transparency,
                    child: CheckboxListTile(
                      value: _shareLocation,
                      onChanged: _step == _SmsStep.sending
                          ? null
                          : (v) => setState(() => _shareLocation = v ?? false),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: SwColors.brand,
                      checkColor: SwColors.onBrand,
                      title: Text('簡訊附上我的位置', style: SwText.bodyStrong),
                      subtitle: Text(
                        widget.position == null
                            ? '目前還沒有位置，會寫「尚未取得」'
                            : '只放在這則簡訊裡，不會另外傳送',
                        style: SwText.small,
                      ),
                    ),
                  ),
                  if (_step == _SmsStep.failed) ...[
                    const SwStateMessage(
                      icon: Icons.error_outline_rounded,
                      title: '沒有開啟簡訊',
                      message: '手機沒有開啟簡訊 App，請改打 110。',
                      error: true,
                    ),
                    const SizedBox(height: 8),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: SwPressable(
                      onTap: _step == _SmsStep.sending ? null : _send,
                      color: _step == _SmsStep.sending
                          ? TPColors.red300
                          : SwColors.sos,
                      pressedColor: SwColors.sosPressed,
                      radius: 12,
                      semanticsLabel: _step == _SmsStep.sending
                          ? '傳送中'
                          : '傳送簡訊報警',
                      child: SizedBox(
                        height: swTouchLarge,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_step == _SmsStep.sending)
                              const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  color: SwColors.onDeep,
                                ),
                              )
                            else
                              const Icon(
                                Icons.send_rounded,
                                color: SwColors.onDeep,
                              ),
                            const SizedBox(width: 8),
                            Text(
                              _step == _SmsStep.sending ? '傳送中…' : '傳送簡訊',
                              style: SwText.bodyStrong.copyWith(
                                color: SwColors.onDeep,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (mock) ...[
                    const SizedBox(height: 6),
                    Text('目前沒有設定報案簡訊號碼。', style: SwText.small),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _sent(bool mock) => Semantics(
    liveRegion: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: .4, end: 1),
              duration: SwMotion.of(context, 360),
              curve: Curves.easeOutBack,
              builder: (_, s, child) => Transform.scale(scale: s, child: child),
              child: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: SwColors.brand,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: SwColors.onBrand,
                  size: 28,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                mock ? '簡訊內容已準備好' : '已開啟簡訊 App',
                style: SwText.bodyStrong,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          mock
              ? '這是模擬畫面，沒有真的傳送給任何人。正式版會由手機的簡訊 App 送出。'
              : '請在簡訊 App 按下傳送。開啟簡訊不代表警方已收到或受理。',
          style: SwText.body,
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: SwColors.bg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(_body, style: SwText.secondary),
        ),
        const SizedBox(height: 8),
        SwChip(
          label: '重新編輯',
          icon: Icons.edit_outlined,
          onTap: () => setState(() => _step = _SmsStep.draft),
        ),
      ],
    ),
  );
}

/// 紅色大按鈕：圖示＋標題＋使用時機（16px，照顧長輩與緊張時閱讀）。
class _CallButton extends StatelessWidget {
  const _CallButton({
    required this.icon,
    required this.title,
    required this.when,
    required this.onTap,
  });
  final IconData icon;
  final String title, when;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      boxShadow: SwShadow.float,
    ),
    child: SwPressable(
      onTap: onTap,
      color: SwColors.sos,
      pressedColor: SwColors.sosPressed,
      radius: 16,
      semanticsLabel: '$title，$when',
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: ExcludeSemantics(
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: TPColors.red700,
              ),
              child: Icon(icon, color: SwColors.onDeep, size: 30),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: SwText.heading.copyWith(color: SwColors.onDeep),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    when,
                    style: SwText.small.copyWith(color: SwColors.onDeep),
                  ),
                ],
              ),
            ),
            const Icon(Icons.phone_rounded, color: SwColors.onDeep, size: 26),
          ],
        ),
      ),
    ),
  );
}
