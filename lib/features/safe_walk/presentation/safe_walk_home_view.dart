import 'package:flutter/material.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_ui.dart';
import 'package:town_pass/util/tp_colors.dart';

enum SafeWalkEntry { map, call, points, report }

/// 入口頁：比照臺北通開啟服務時的樣式——上方主色長條＋右上關閉；
/// 時間情境卡、「安心回家」主卡（臺北天際線插圖）、其他功能一項一行、最下方緊急求助。
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
      body: Column(
        children: [
          _ServiceBar(onClose: onBack),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              children: [
                Semantics(header: true, label: '臺北安心行', child: const SizedBox.shrink()),
                _ContextCard(now: t),
                const SizedBox(height: 16),
                _GoHomeCard(destination: destination, minutes: homeMinutes, avoided: avoided, onTap: () => onOpen(SafeWalkEntry.map)),
                const SizedBox(height: 24),
                Semantics(header: true, child: Text('其他功能', style: SwText.heading)),
                const SizedBox(height: 12),
                for (final (id, icon, name, desc) in _more) ...[_FeatureRow(icon: icon, name: name, desc: desc, onTap: () => onOpen(id)), const SizedBox(height: 10)],
                const SizedBox(height: 6),
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

/// 臺北通開啟服務時的上方長條：主色底，右上角圓形關閉鈕（白色 ✕ 放在較深的 primary600 圓底上，對比 3.8:1）。
class _ServiceBar extends StatelessWidget {
  const _ServiceBar({required this.onClose});
  final VoidCallback? onClose;
  @override
  Widget build(BuildContext context) => Container(
    color: TPColors.primary500,
    child: SafeArea(
      bottom: false,
      child: SizedBox(
        height: 56,
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: onClose == null
                ? const SizedBox.shrink()
                : Tooltip(
                    message: '關閉',
                    child: SwPressable(
                      onTap: onClose,
                      color: TPColors.primary600,
                      pressedColor: TPColors.primary700,
                      radius: 24,
                      semanticsLabel: '關閉臺北安心行',
                      child: const SizedBox(width: 48, height: 48, child: Icon(Icons.close_rounded, color: TPColors.white, size: 26)),
                    ),
                  ),
          ),
        ),
      ),
    ),
  );
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

/// 「安心回家」主卡：比照臺北通服務卡的青色底＋右側插圖（臺北天際線、打勾地標、小路、家）。
/// 文字放在左側較深的 primary700 區塊，白字對比足夠；按鈕白底。
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
      semanticsLabel: '安心回家，到$destination約 $minutes 分鐘，已繞開 $avoided 個異常回報，開始回家',
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 220),
          child: Stack(
            children: [
              const Positioned(right: 0, top: 8, bottom: 72, width: 190, child: CustomPaint(painter: _CityHomeIllustration())),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(destination == '家' ? '安心回家' : '安心去$destination', style: SwText.title.copyWith(fontSize: 30, color: TPColors.white)),
                    Text('Safe Walk Home', style: SwText.bodyStrong.copyWith(fontSize: 18, color: TPColors.white)),
                    const SizedBox(height: 48),
                    Container(
                      constraints: const BoxConstraints(minHeight: 56),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(color: SwColors.surface, borderRadius: BorderRadius.circular(12), boxShadow: SwShadow.card),
                      child: Row(
                        children: [
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.navigation_rounded, color: SwColors.brandDeep, size: 26),
                                const SizedBox(width: 10),
                                Flexible(
                                  child: Text(
                                    '開始回家',
                                    maxLines: 1,
                                    softWrap: false,
                                    overflow: TextOverflow.ellipsis,
                                    style: SwText.title.copyWith(fontSize: 22, color: SwColors.brandDeep),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text('約 $minutes 分', maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: SwText.secondary),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, color: SwColors.textSecondary),
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

/// 右側插圖：淡色臺北天際線（含 101）、打勾的地點標記、白色小路與家。只用白色透明度，不另建色票。
class _CityHomeIllustration extends CustomPainter {
  const _CityHomeIllustration();
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final city = Paint()..color = TPColors.white.withValues(alpha: .22);
    for (final r in [Rect.fromLTWH(w * .02, h * .55, w * .12, h * .45), Rect.fromLTWH(w * .15, h * .42, w * .09, h * .58), Rect.fromLTWH(w * .25, h * .6, w * .1, h * .4)]) {
      canvas.drawRect(r, city);
    }
    final tower = Path()
      ..moveTo(w * .4, h)
      ..lineTo(w * .4, h * .3)
      ..lineTo(w * .42, h * .3)
      ..lineTo(w * .42, h * .22)
      ..lineTo(w * .445, h * .22)
      ..lineTo(w * .445, h * .02)
      ..lineTo(w * .455, h * .02)
      ..lineTo(w * .455, h * .22)
      ..lineTo(w * .48, h * .22)
      ..lineTo(w * .48, h * .3)
      ..lineTo(w * .5, h * .3)
      ..lineTo(w * .5, h)
      ..close();
    canvas.drawPath(tower, Paint()..color = TPColors.white.withValues(alpha: .32));
    canvas.drawRect(Rect.fromLTWH(w * .52, h * .66, w * .08, h * .34), city);

    final line = Paint()
      ..color = TPColors.white.withValues(alpha: .85)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final road = Path()
      ..moveTo(w * .3, h * 1.25)
      ..quadraticBezierTo(w * .5, h * .95, w * .66, h * .98)
      ..quadraticBezierTo(w * .78, h * 1.0, w * .84, h * .88);
    canvas.drawPath(road, line..strokeWidth = 5);
    final house = Path()
      ..moveTo(w * .72, h * .56)
      ..lineTo(w * .86, h * .38)
      ..lineTo(w * 1.0, h * .56)
      ..moveTo(w * .75, h * .52)
      ..lineTo(w * .75, h * .86)
      ..lineTo(w * .97, h * .86)
      ..lineTo(w * .97, h * .52);
    canvas.drawPath(house, line..strokeWidth = 4);
    canvas.drawRect(Rect.fromLTWH(w * .83, h * .68, w * .06, h * .18), Paint()..color = TPColors.white.withValues(alpha: .85));
    final c = Offset(w * .6, h * .62);
    final pin = Path()
      ..addOval(Rect.fromCircle(center: c, radius: w * .075))
      ..moveTo(c.dx - w * .05, c.dy + w * .05)
      ..lineTo(c.dx, c.dy + w * .14)
      ..lineTo(c.dx + w * .05, c.dy + w * .05);
    canvas.drawPath(pin, Paint()..color = TPColors.white);
    final check = Path()
      ..moveTo(c.dx - w * .03, c.dy)
      ..lineTo(c.dx - w * .005, c.dy + w * .025)
      ..lineTo(c.dx + w * .035, c.dy - w * .02);
    canvas.drawPath(
      check,
      Paint()
        ..color = TPColors.primary600
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
                  Text(name, style: SwText.heading.copyWith(fontSize: 20)),
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
