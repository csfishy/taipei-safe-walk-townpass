import 'package:flutter/material.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_ui.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;
import 'package:town_pass/util/tp_colors.dart';

/// An emergency alert addressed to this person as a nearby helper. It carries
/// no sender identity: the backend never reveals who pressed SOS.
final class SafeWalkNearbyAlert {
  const SafeWalkNearbyAlert({
    required this.alertId,
    required this.location,
    required this.createdAt,
  });

  final String alertId;
  final sw.Coordinates location;
  final DateTime createdAt;
}

/// What the screens need from the helper side of "notify people nearby".
/// M1 implements it; M3 only presents it. Alerts are delivered inside the app
/// while it is open; there is no push, so nothing arrives when it is closed.
abstract interface class SafeWalkNearbyHelper implements Listenable {
  /// Non-null means joining cannot work right now (not signed in, backend not
  /// configured). The card shows it and offers no button.
  String? get unavailableReason;

  bool get isOn;
  bool get isBusy;

  /// The latest status or failure, in words the person can act on.
  String? get message;
  bool get messageIsError;

  /// Alerts not yet dismissed, newest first.
  List<SafeWalkNearbyAlert> get incoming;

  /// Called only after the person confirmed the consent text.
  Future<void> enable();

  /// Stops helping and asks the backend to delete the stored position.
  Future<void> disable();

  void dismiss(String alertId);
}

/// 首頁的「成為附近協助者」。兩段式：先看同意說明，同意後才取得位置並加入。
class SafeWalkNearbyHelperCard extends StatefulWidget {
  const SafeWalkNearbyHelperCard({super.key, required this.helper});

  final SafeWalkNearbyHelper helper;

  @override
  State<SafeWalkNearbyHelperCard> createState() =>
      _SafeWalkNearbyHelperCardState();
}

class _SafeWalkNearbyHelperCardState extends State<SafeWalkNearbyHelperCard> {
  bool _confirming = false;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.helper,
    builder: (context, _) {
      final helper = widget.helper;
      final reason = helper.unavailableReason;
      if (reason != null && !helper.isOn) {
        return SwStateMessage(
          icon: Icons.notifications_off_outlined,
          title: '附近協助者：目前無法使用',
          message: reason,
        );
      }
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: SwColors.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: SwShadow.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.notifications_active_rounded,
                  color: SwColors.brand,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('附近協助者', style: SwText.bodyStrong),
                      Text(
                        helper.isOn
                            ? '協助中：App 開啟時，附近有人求助會在這裡通知你'
                            : '附近有人按下求助時，在 App 內通知你',
                        style: SwText.secondary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._body(helper),
          ],
        ),
      );
    },
  );

  List<Widget> _body(SafeWalkNearbyHelper helper) {
    if (helper.isBusy) {
      return [
        Row(
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
            Text('處理中…', style: SwText.bodyStrong),
          ],
        ),
      ];
    }
    final status = helper.message == null
        ? const <Widget>[]
        : [
            SwStateMessage(
              icon: helper.messageIsError
                  ? Icons.error_outline_rounded
                  : Icons.info_outline_rounded,
              title: helper.messageIsError ? '沒有成功' : '目前狀態',
              message: helper.message!,
              error: helper.messageIsError,
            ),
            const SizedBox(height: 12),
          ];
    if (helper.isOn) {
      return [
        ...status,
        _button('停止協助並刪除我的位置', Icons.stop_circle_outlined, () async {
          setState(() => _confirming = false);
          await helper.disable();
        }, filled: false),
      ];
    }
    if (_confirming) {
      return [
        ...status,
        Text('加入後：', style: SwText.bodyStrong),
        const SizedBox(height: 4),
        for (final line in _consentLines) ...[
          Text('・$line', style: SwText.body),
          const SizedBox(height: 4),
        ],
        const SizedBox(height: 8),
        _button('同意並加入', Icons.check_rounded, () async {
          setState(() => _confirming = false);
          await helper.enable();
        }),
        const SizedBox(height: 8),
        _button(
          '取消',
          Icons.close_rounded,
          () => setState(() => _confirming = false),
          filled: false,
        ),
      ];
    }
    return [
      ...status,
      _button(
        '加入附近協助者',
        Icons.notifications_active_rounded,
        () => setState(() => _confirming = true),
      ),
    ];
  }

  static const _consentLines = [
    'App 開啟期間，每 4 分鐘左右取得並上傳你的位置，只保存最新一筆。',
    '離開安心行、關閉 App 或停止協助後，位置最多 10 分鐘內自動刪除。',
    '500 公尺內有人按下求助時，會在 App 內通知你；對方看不到你是誰，你也看不到對方是誰。',
    'App 關閉時不會收到通知。',
    '這不是正式救援服務，你沒有義務前往。請先確認自身安全，必要時撥打 110／119。',
  ];

  Widget _button(
    String label,
    IconData icon,
    VoidCallback onTap, {
    bool filled = true,
  }) => SizedBox(
    width: double.infinity,
    child: SwPressable(
      onTap: onTap,
      color: filled ? SwColors.brand : SwColors.surface,
      pressedColor: filled ? TPColors.primary400 : SwColors.brandSoft,
      border: filled ? null : const BorderSide(color: SwColors.border),
      radius: 12,
      semanticsLabel: label,
      child: SizedBox(
        height: swTouchLarge,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: filled ? SwColors.onBrand : SwColors.text),
            const SizedBox(width: 8),
            Text(
              label,
              style: SwText.bodyStrong.copyWith(
                color: filled ? SwColors.onBrand : SwColors.text,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 有人在附近求助時，蓋在任何畫面上方的橫幅。沒有聲稱已查證、已報警或有人趕到。
class SafeWalkNearbyAlertBanner extends StatelessWidget {
  const SafeWalkNearbyAlertBanner({
    super.key,
    required this.helper,
    required this.onOpenEmergency,
  });

  final SafeWalkNearbyHelper helper;

  /// 打開求助頁（110／119）；橫幅同時收起。
  final VoidCallback onOpenEmergency;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: helper,
    builder: (context, _) {
      final alerts = helper.incoming;
      if (alerts.isEmpty) return const SizedBox.shrink();
      final alert = alerts.first;
      final at = alert.createdAt.toLocal();
      final time =
          '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Semantics(
            liveRegion: true,
            container: true,
            child: Material(
              elevation: 8,
              color: TPColors.red50,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: SwColors.sos, width: 2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.notifications_active_rounded,
                          color: SwColors.sos,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            alerts.length == 1
                                ? '附近有人求助'
                                : '附近有人求助（共 ${alerts.length} 則）',
                            style: SwText.heading.copyWith(color: SwColors.sos),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '位置：${alert.location.lat.toStringAsFixed(5)}, '
                      '${alert.location.lng.toStringAsFixed(5)}（$time 送出）',
                      style: SwText.bodyStrong,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '這則求助未經查證，位置可能不準確。請先確認自身安全，不要獨自涉險；需要時撥打 110／119。',
                      style: SwText.body,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _BannerButton(
                            label: '知道了',
                            onTap: () => helper.dismiss(alert.alertId),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _BannerButton(
                            label: '110／119',
                            filled: true,
                            onTap: () {
                              helper.dismiss(alert.alertId);
                              onOpenEmergency();
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _BannerButton extends StatelessWidget {
  const _BannerButton({
    required this.label,
    required this.onTap,
    this.filled = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) => SwPressable(
    onTap: onTap,
    color: filled ? SwColors.sos : SwColors.surface,
    pressedColor: filled ? SwColors.sosPressed : SwColors.brandSoft,
    border: filled ? null : const BorderSide(color: SwColors.border),
    radius: 12,
    semanticsLabel: label,
    child: SizedBox(
      height: swTouchLarge,
      child: Center(
        child: Text(
          label,
          style: SwText.bodyStrong.copyWith(
            color: filled ? SwColors.onDeep : SwColors.text,
          ),
        ),
      ),
    ),
  );
}
