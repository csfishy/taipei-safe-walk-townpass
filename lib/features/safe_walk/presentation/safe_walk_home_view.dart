import 'package:flutter/material.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_ui.dart';
import 'package:town_pass/util/tp_colors.dart';

enum SafeWalkEntry { map, call, points, report }

/// 首頁（方向 B＋A）：
/// - A 情境卡：依現在時間提醒（天色、建議）。
/// - B 一鍵回家：最常用的功能放最大，點一下直接進導航。
/// - 其他三個功能沿用臺北通「我的服務」的圓形圖示排列。
/// - 最下方固定緊急求助。
class SafeWalkHomeView extends StatelessWidget {
  const SafeWalkHomeView({super.key, required this.onOpen, required this.onEmergency, required this.homeMinutes, required this.avoided, this.onBack, this.now});
  final ValueChanged<SafeWalkEntry> onOpen;
  final VoidCallback onEmergency;
  final VoidCallback? onBack;
  final int homeMinutes, avoided;

  /// 測試可固定時間；正式由裝置時間決定。
  final DateTime? now;

  static const _more = [
    (SafeWalkEntry.call, Icons.phone_in_talk_rounded, '模擬來電', '家人來電陪你'),
    (SafeWalkEntry.points, Icons.local_police_rounded, '附近求助地點', '警察局、超商'),
    (SafeWalkEntry.report, Icons.campaign_rounded, '回報狀況', '標出暗路、打架'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = now ?? DateTime.now();
    return Scaffold(
      backgroundColor: SwColors.bg,
      appBar: AppBar(
        backgroundColor: SwColors.surface,
        foregroundColor: SwColors.textSecondary,
        elevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
        leading: onBack == null ? null : IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), tooltip: '返回', onPressed: onBack),
        title: Semantics(header: true, child: Text('臺北安心行', style: SwText.heading)),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              children: [
                _ContextCard(now: t),
                const SizedBox(height: 12),
                _GoHomeCard(minutes: homeMinutes, avoided: avoided, onTap: () => onOpen(SafeWalkEntry.map)),
                const SizedBox(height: 20),
                Semantics(header: true, child: Text('其他功能', style: SwText.heading)),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (id, icon, name, desc) in _more)
                      Expanded(
                        child: _ServiceIcon(icon: icon, name: name, desc: desc, onTap: () => onOpen(id)),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: SwMockBadge(text: '示範模式（Mock）'),
                ),
              ],
            ),
          ),
          SwActionBar.single(onEmergency: onEmergency),
        ],
      ),
    );
  }
}

/// A 情境卡：時間＋天色＋一句建議。夜間（18–06 點）提醒走明亮的路。
class _ContextCard extends StatelessWidget {
  const _ContextCard({required this.now});
  final DateTime now;
  @override
  Widget build(BuildContext context) {
    final night = now.hour >= 18 || now.hour < 6;
    final hhmm = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: night ? TPColors.primary800 : SwColors.surface, borderRadius: BorderRadius.circular(12), boxShadow: SwShadow.card),
      child: Row(
        children: [
          Icon(night ? Icons.nightlight_round : Icons.wb_sunny_rounded, color: night ? TPColors.secondary300 : TPColors.secondary600, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$hhmm・${night ? '天色已暗' : '白天'}', style: SwText.bodyStrong.copyWith(color: night ? SwColors.onDeep : SwColors.text)),
                Text(night ? '建議走明亮的大路，需要時開模擬來電' : '出門前先看看沿路有沒有回報', style: SwText.body.copyWith(color: night ? TPColors.primary100 : SwColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// B 一鍵回家：本頁唯一的大區塊。顯示預估時間與「已繞開」數字，整張卡都可以點。
class _GoHomeCard extends StatelessWidget {
  const _GoHomeCard({required this.minutes, required this.avoided, required this.onTap});
  final int minutes, avoided;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), boxShadow: SwShadow.float),
    child: SwPressable(
      onTap: onTap,
      color: SwColors.brandDeep,
      pressedColor: SwColors.brandDeeper,
      radius: 16,
      semanticsLabel: '安心回家，約 $minutes 分鐘，已繞開 $avoided 個異常回報，開始導航',
      padding: const EdgeInsets.all(20),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(color: SwColors.surface, shape: BoxShape.circle),
                  child: const Icon(Icons.home_rounded, color: SwColors.brandDeep),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('安心回家', style: SwText.title.copyWith(color: SwColors.onDeep)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$minutes',
                    style: SwText.title.copyWith(fontSize: 48, height: 1, color: SwColors.onDeep),
                  ),
                  TextSpan(
                    text: ' 分鐘到家',
                    style: SwText.heading.copyWith(color: SwColors.onDeep),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.verified_outlined, size: 18, color: TPColors.primary100),
                const SizedBox(width: 6),
                Flexible(
                  child: Text('路線已繞開 $avoided 個異常回報（示範）', style: SwText.body.copyWith(color: TPColors.primary100)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              height: swTouch,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: SwColors.surface, borderRadius: BorderRadius.circular(10)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.navigation_rounded, color: SwColors.brandDeep),
                  const SizedBox(width: 8),
                  Text('開始回家', style: SwText.heading.copyWith(color: SwColors.brandDeep)),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 臺北通「我的服務」樣式：白色圓形圖示＋名稱，另加一行短說明給長輩看懂用途。
class _ServiceIcon extends StatelessWidget {
  const _ServiceIcon({required this.icon, required this.name, required this.desc, required this.onTap});
  final IconData icon;
  final String name, desc;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SwPressable(
    onTap: onTap,
    radius: 12,
    semanticsLabel: '$name，$desc',
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
    child: ExcludeSemantics(
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: SwColors.surface, shape: BoxShape.circle, boxShadow: SwShadow.card),
            child: Icon(icon, size: 30, color: SwColors.brandDeep),
          ),
          const SizedBox(height: 8),
          Text(name, textAlign: TextAlign.center, style: SwText.bodyStrong),
          Text(desc, textAlign: TextAlign.center, style: SwText.small),
        ],
      ),
    ),
  );
}
