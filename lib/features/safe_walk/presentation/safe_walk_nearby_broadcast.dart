import 'dart:async';

import 'package:flutter/material.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_ui.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/util/tp_colors.dart';

/// What happened when the user asked to notify people nearby.
sealed class NearbyBroadcastOutcome {
  const NearbyBroadcastOutcome();
}

/// The backend accepted the request. [recipientCount] is how many nearby
/// helpers it reported notifying; it is not proof that anyone saw it.
final class NearbyBroadcastSent extends NearbyBroadcastOutcome {
  const NearbyBroadcastSent(this.recipientCount);
  final int recipientCount;
}

/// Nothing was confirmed as sent. [message] is shown to the user as is.
final class NearbyBroadcastNotSent extends NearbyBroadcastOutcome {
  const NearbyBroadcastNotSent(this.message, {this.cancelled = false});
  final String message;
  final bool cancelled;
}

/// M1 injects this into the emergency page. M3 only presents it.
///
/// [unavailableReason] non-null means the feature cannot be used right now; the
/// card then shows the reason and offers no button. [onBroadcast] runs only
/// after the person confirmed, and must stop when [SafeWalkCancellation]
/// fires (leaving the page).
class SafeWalkNearbyBroadcast {
  const SafeWalkNearbyBroadcast({
    required this.unavailableReason,
    required this.onBroadcast,
  });

  final String? unavailableReason;
  final Future<NearbyBroadcastOutcome> Function(
    SafeWalkCancellation cancellation,
  )
  onBroadcast;
}

enum _Step { idle, confirming, sending, sent, failed }

/// 「通知附近的人」：兩段式（按下 → 確認），確認後才取得位置並送出。
/// 結果只說後端回報的人數，不說有人會來、不說已報警。
class SafeWalkNearbyBroadcastCard extends StatefulWidget {
  const SafeWalkNearbyBroadcastCard({super.key, required this.broadcast});

  final SafeWalkNearbyBroadcast broadcast;

  @override
  State<SafeWalkNearbyBroadcastCard> createState() =>
      _SafeWalkNearbyBroadcastCardState();
}

class _CardCancellation implements SafeWalkCancellation {
  final _done = Completer<void>();
  @override
  bool get isCancelled => _done.isCompleted;
  @override
  Future<void> get whenCancelled => _done.future;
  void cancel() {
    if (!_done.isCompleted) _done.complete();
  }
}

class _SafeWalkNearbyBroadcastCardState
    extends State<SafeWalkNearbyBroadcastCard> {
  _Step _step = _Step.idle;
  _CardCancellation? _operation;
  int _recipients = 0;
  String _failure = '';

  @override
  void dispose() {
    // Leaving the page cancels any request that has not finished yet.
    _operation?.cancel();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_step == _Step.sending) return;
    final operation = _operation = _CardCancellation();
    setState(() => _step = _Step.sending);
    NearbyBroadcastOutcome outcome;
    try {
      outcome = await widget.broadcast.onBroadcast(operation);
    } on Object {
      outcome = const NearbyBroadcastNotSent('附近通知沒有完成，請改用電話求助');
    }
    if (!mounted || !identical(_operation, operation)) return;
    setState(() {
      switch (outcome) {
        case NearbyBroadcastSent(:final recipientCount):
          _recipients = recipientCount;
          _step = _Step.sent;
        case NearbyBroadcastNotSent(:final message):
          _failure = message;
          _step = _Step.failed;
      }
    });
  }

  void _cancelSending() => _operation?.cancel();

  @override
  Widget build(BuildContext context) {
    final reason = widget.broadcast.unavailableReason;
    if (reason != null) {
      return SwStateMessage(
        icon: Icons.cell_tower_rounded,
        title: '通知附近的人：目前無法使用',
        message: '$reason\n請撥打 110／119。',
      );
    }
    final done = _step == _Step.sent;
    return AnimatedContainer(
      duration: SwMotion.of(context, 220),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SwColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: done ? SwColors.brand : TPColors.red200,
          width: 2,
        ),
        boxShadow: SwShadow.card,
      ),
      child: AnimatedSize(
        duration: SwMotion.of(context, 240),
        curve: SwMotion.curve,
        alignment: Alignment.topCenter,
        child: Column(
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
                    Icons.cell_tower_rounded,
                    color: SwColors.sos,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '通知附近的人',
                        style: SwText.bodyStrong.copyWith(color: SwColors.sos),
                      ),
                      Text('把求助位置傳給附近已加入協助的人', style: SwText.secondary),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._body(),
          ],
        ),
      ),
    );
  }

  List<Widget> _body() => switch (_step) {
    _Step.idle => [_action('通知附近協助者', Icons.cell_tower_rounded, _ask)],
    _Step.confirming => [
      Text(
        '按下確認後，會取得你目前的精確位置，傳給附近已加入協助的人：500 公尺內的人，以及設了守護區、範圍涵蓋這裡的人。',
        style: SwText.body,
      ),
      const SizedBox(height: 6),
      Text('對方看不到你是誰（只會用這支手機的匿名帳號送出）。這不是報警，也不保證有人會趕到。', style: SwText.body),
      const SizedBox(height: 6),
      Text('請同時撥打 110／119。', style: SwText.bodyStrong),
      const SizedBox(height: 12),
      _action('確認通知', Icons.send_rounded, _confirm),
      const SizedBox(height: 8),
      _secondary('取消', () => setState(() => _step = _Step.idle)),
    ],
    _Step.sending => [
      Row(
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: SwColors.sos,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text('正在取得位置並通知…', style: SwText.bodyStrong)),
        ],
      ),
      const SizedBox(height: 12),
      _secondary('取消', _cancelSending),
    ],
    _Step.sent => [
      SwStateMessage(
        icon: Icons.check_circle_outline_rounded,
        title: _recipients == 0 ? '已送出，但附近沒有人可通知' : '已通知 $_recipients 位附近協助者',
        message: _recipients == 0
            ? '目前附近沒有已加入協助的人。這不是報警，請撥打 110／119。'
            : '這只表示通知已送出，不代表有人會趕到，也不是報警。請同時撥打 110／119。',
      ),
    ],
    _Step.failed => [
      SwStateMessage(
        icon: Icons.error_outline_rounded,
        title: '沒有送出',
        message: '$_failure\n請撥打 110／119。',
        error: true,
        actionLabel: '再試一次',
        onAction: () => setState(() => _step = _Step.confirming),
      ),
    ],
  };

  void _ask() => setState(() => _step = _Step.confirming);

  Widget _action(String label, IconData icon, VoidCallback onTap) => SizedBox(
    width: double.infinity,
    child: SwPressable(
      onTap: onTap,
      color: SwColors.sos,
      pressedColor: SwColors.sosPressed,
      radius: 12,
      semanticsLabel: label,
      child: SizedBox(
        height: swTouchLarge,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: SwColors.onDeep),
            const SizedBox(width: 8),
            Text(
              label,
              style: SwText.bodyStrong.copyWith(color: SwColors.onDeep),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _secondary(String label, VoidCallback onTap) => SizedBox(
    width: double.infinity,
    child: SwPressable(
      onTap: onTap,
      color: SwColors.surface,
      pressedColor: SwColors.brandSoft,
      border: const BorderSide(color: SwColors.border),
      radius: 12,
      semanticsLabel: label,
      child: SizedBox(
        height: swTouchLarge,
        child: Center(child: Text(label, style: SwText.bodyStrong)),
      ),
    ),
  );
}
