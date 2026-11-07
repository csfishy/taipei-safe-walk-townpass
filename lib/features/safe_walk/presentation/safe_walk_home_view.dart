import 'package:flutter_svg/flutter_svg.dart';
import 'package:town_pass/features/safe_walk/presentation/assets/safe_walk_card_assets.dart';
import 'package:flutter/material.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_ui.dart';
import 'package:town_pass/util/tp_app_bar.dart';
import 'package:town_pass/util/tp_colors.dart';

enum SafeWalkEntry { map, call, points, report }

/// 入口頁：比照臺北通開啟服務時的樣式——上方主色長條＋右上關閉；
/// 時間情境卡、「安心行」主卡（臺北天際線插圖）、其他功能一項一行、最下方緊急求助。
class SafeWalkHomeView extends StatelessWidget {
  const SafeWalkHomeView({super.key, required this.onOpen, required this.onEmergency, required this.homeMinutes, required this.avoided, this.destination = '家', this.onBack, this.now});
  final ValueChanged<SafeWalkEntry> onOpen;
  final VoidCallback onEmergency;

  /// 關閉安心行、回到臺北通（右上 ✕）。
  final VoidCallback? onBack;
  final int homeMinutes, avoided;
  final String destination;

  /// 測試可固定時間；正式由裝置時間決定。
  final DateTime? now;

  static const _more = [
    (SafeWalkEntry.call, Icons.phone_in_talk_rounded, '模擬來電', '家人來電陪你'),
    (SafeWalkEntry.points, Icons.local_police_rounded, '附近求助地點', '警察局、超商'),
    (SafeWalkEntry.report, Icons.campaign_rounded, '回報狀況', '標出暗路、打架等'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = now ?? DateTime.now();
    return Scaffold(
      backgroundColor: SwColors.bg,
      // 與臺北通網頁服務（TPWebView）同一套：主色長條＋右上 CloseButton，hover／按壓效果由官方元件處理。
      appBar: TPAppBar(
        backgroundColor: TPColors.primary500,
        foregroundColor: TPColors.white,
        leading: const SizedBox.shrink(),
        actions: [
          if (onBack != null)
            CloseButton(
              color: TPColors.white,
              onPressed: onBack,
              style: const ButtonStyle(iconSize: WidgetStatePropertyAll<double>(24)),
            )
          else
            const SizedBox(width: 56),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              children: [
                Semantics(header: true, label: '臺北安心行', child: const SizedBox.shrink()),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: SwMockBadge(text: '示範模式（Mock）'),
                ),
                const SizedBox(height: 12),
                _ContextCard(now: t),
                const SizedBox(height: 16),
                _GoHomeCard(destination: destination, minutes: homeMinutes, avoided: avoided, onTap: () => onOpen(SafeWalkEntry.map)),
                const SizedBox(height: 24),
                Semantics(header: true, child: Text('其他功能', style: SwText.heading)),
                const SizedBox(height: 12),
                for (final (id, icon, name, desc) in _more) ...[_FeatureRow(icon: icon, name: name, desc: desc, onTap: () => onOpen(id)), const SizedBox(height: 10)],
              ],
            ),
          ),
          SwActionBar.single(onEmergency: onEmergency),
        ],
      ),
    );
  }
}

/// 時間情境卡：圖示｜分隔線｜時間與一句建議。夜間（18–06 點）改深色並提醒走明亮的路。
class _ContextCard extends StatelessWidget {
  const _ContextCard({required this.now});
  final DateTime now;
  @override
  Widget build(BuildContext context) {
    final night = now.hour >= 18 || now.hour < 6;
    final hhmm = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: night ? TPColors.primary800 : SwColors.surface, borderRadius: BorderRadius.circular(12), boxShadow: SwShadow.card),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Icon(night ? Icons.nightlight_round : Icons.wb_sunny_rounded, color: night ? TPColors.secondary300 : TPColors.secondary600, size: 32),
            const SizedBox(width: 14),
            VerticalDivider(width: 1, thickness: 1, color: night ? TPColors.primary600 : SwColors.border),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$hhmm・${night ? '天色已暗' : '白天'}', style: SwText.heading.copyWith(color: night ? SwColors.onDeep : SwColors.text)),
                  Text(night ? '建議走明亮的大路，需要時開模擬來電' : '出門前先看看沿路有沒有回報', style: SwText.body.copyWith(color: night ? TPColors.primary100 : SwColors.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Figma 主卡：左下透明文字動作、右下原始天際線插圖。
class _GoHomeCard extends StatelessWidget {
  const _GoHomeCard({required this.destination, required this.minutes, required this.avoided, required this.onTap});
  final String destination;
  final int minutes, avoided;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      gradient: const LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: [TPColors.primary700, TPColors.primary600, TPColors.primary500], stops: [0, .45, 1]),
      boxShadow: SwShadow.float,
    ),
    child: SwPressable(
      onTap: onTap,
      pressedColor: TPColors.primary800.withValues(alpha: .25),
      radius: 12,
      semanticsLabel: '安心行，前往$destination，已繞開 $avoided 個異常回報，點擊開始',
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 211),
          child: Stack(
            children: [
              Positioned(right: 0, bottom: 0, width: 210, height: 155, child: Image.memory(swCardSkyline, fit: BoxFit.contain, excludeFromSemantics: true)),
              Positioned(right: 19, top: 12, width: 210, height: 44, child: Image.memory(swCardStars, fit: BoxFit.contain, excludeFromSemantics: true)),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('安心行', style: SwText.display.copyWith(color: TPColors.white)),
                    Text('Safe Walk', style: SwText.heading.copyWith(color: TPColors.white)),
                    const SizedBox(height: 48),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 56),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SvgPicture.string(swCardNavigationSvg, width: 26, height: 26),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text('點擊開始', style: SwText.title.copyWith(color: TPColors.white)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 其他功能：一項一行的卡片（圖示｜名稱＋說明｜箭頭），點擊範圍整行。
class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.name, required this.desc, required this.onTap});
  final IconData icon;
  final String name, desc;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), boxShadow: SwShadow.card),
    child: SwPressable(
      onTap: onTap,
      color: SwColors.surface,
      pressedColor: SwColors.brandSoft,
      border: const BorderSide(color: TPColors.grayscale100),
      radius: 12,
      semanticsLabel: '$name，$desc',
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: ExcludeSemantics(
        child: Row(
          children: [
            Icon(icon, size: 30, color: TPColors.primary600),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: SwText.heading),
                  Text(desc, style: SwText.secondary),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: SwColors.textSecondary),
          ],
        ),
      ),
    ),
  );
}
