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

/// 「安心行」主卡：比照臺北通服務卡的青色底＋右側插圖（臺北天際線、打勾地標、小路、家）。
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
      semanticsLabel: '安心行，前往$destination，已繞開 $avoided 個異常回報，點擊開始',
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
                    Text('安心行', style: SwText.title.copyWith(fontSize: 30, color: TPColors.white)),
                    Text('Safe Walk', style: SwText.bodyStrong.copyWith(fontSize: 18, color: TPColors.white)),
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
                                    '點擊開始',
                                    maxLines: 1,
                                    softWrap: false,
                                    overflow: TextOverflow.ellipsis,
                                    style: SwText.title.copyWith(fontSize: 22, color: SwColors.brandDeep),
                                  ),
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

/// 右側插圖：遠近兩層臺北天際線（含分層的 101）、山丘、虛線安全路線通往亮著窗的家，路上一個打勾定位點。只用白色透明度與 primary600。
class _CityHomeIllustration extends CustomPainter {
  const _CityHomeIllustration();
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    Paint white(double a) => Paint()..color = TPColors.white.withValues(alpha: a);

    // 星點
    for (final (x, y, r) in [(.08, .12, 2.0), (.3, .05, 1.5), (.72, .08, 2.5), (.9, .2, 1.5), (.58, .22, 1.5)]) {
      canvas.drawCircle(Offset(w * x, h * y), r, white(.55));
    }

    // 遠景天際線
    final far = Path()..moveTo(0, h);
    for (final (x, top, width) in [(.0, .62, .1), (.1, .5, .08), (.18, .58, .1), (.62, .55, .09), (.71, .62, .12), (.83, .5, .08), (.91, .6, .09)]) {
      far.addRRect(RRect.fromRectAndCorners(Rect.fromLTWH(w * x, h * top, w * width, h * (1 - top)), topLeft: const Radius.circular(2), topRight: const Radius.circular(2)));
    }
    canvas.drawPath(far, white(.12));

    // 近景：101（分節塔身）與兩側建物
    final tower = Path()
      ..moveTo(w * .36, h)
      ..lineTo(w * .36, h * .78)
      ..lineTo(w * .375, h * .78);
    var y = .78;
    for (var k = 0; k < 6; k++) {
      final top = y - .07;
      tower
        ..lineTo(w * .372, h * (y - .005))
        ..lineTo(w * .38, h * top)
        ..lineTo(w * .375, h * top);
      y = top;
    }
    tower
      ..lineTo(w * .395, h * (y - .03))
      ..lineTo(w * .4, h * .04)
      ..lineTo(w * .405, h * (y - .03))
      ..lineTo(w * .425, h * y);
    y = .36;
    for (var k = 0; k < 6; k++) {
      final bottom = y + .07;
      tower
        ..lineTo(w * .42, h * y)
        ..lineTo(w * .428, h * (bottom - .005))
        ..lineTo(w * .425, h * bottom);
      y = bottom;
    }
    tower
      ..lineTo(w * .44, h * .78)
      ..lineTo(w * .44, h)
      ..close();
    canvas.drawPath(tower, white(.3));
    for (final r in [Rect.fromLTWH(w * .26, h * .6, w * .08, h * .4), Rect.fromLTWH(w * .46, h * .68, w * .1, h * .32)]) {
      canvas.drawRRect(RRect.fromRectAndCorners(r, topLeft: const Radius.circular(3), topRight: const Radius.circular(3)), white(.22));
    }

    // 山丘
    final hill = Path()
      ..moveTo(0, h)
      ..quadraticBezierTo(w * .35, h * .78, w * .7, h * .9)
      ..quadraticBezierTo(w * .88, h * .96, w, h * .86)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(hill, white(.16));

    // 虛線安全路線
    final route = Path()
      ..moveTo(w * .05, h * 1.02)
      ..cubicTo(w * .3, h * .86, w * .5, h * 1.0, w * .78, h * .86);
    for (final m in route.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 14) {
        canvas.drawPath(
          m.extractPath(d, d + 8),
          Paint()
            ..color = TPColors.white.withValues(alpha: .9)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    // 家：白色實心，窗戶與門用 primary600
    final hx = w * .72, hy = h * .5, hw = w * .24;
    final house = Path()
      ..moveTo(hx - 4, hy + hw * .42)
      ..lineTo(hx + hw / 2, hy)
      ..lineTo(hx + hw + 4, hy + hw * .42)
      ..close()
      ..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(hx + 3, hy + hw * .38, hw - 6, hw * .62), const Radius.circular(3)));
    canvas.drawPath(house, white(.95));
    final accent = Paint()..color = TPColors.primary600;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(hx + hw * .4, hy + hw * .66, hw * .2, hw * .34), const Radius.circular(2)), accent);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(hx + hw * .14, hy + hw * .5, hw * .16, hw * .14), const Radius.circular(2)), Paint()..color = TPColors.secondary100);

    // 打勾定位點
    final c = Offset(w * .5, h * .7);
    final r = w * .065;
    final pin = Path()
      ..addOval(Rect.fromCircle(center: c, radius: r))
      ..moveTo(c.dx - r * .7, c.dy + r * .7)
      ..lineTo(c.dx, c.dy + r * 1.9)
      ..lineTo(c.dx + r * .7, c.dy + r * .7)
      ..close();
    canvas.drawPath(pin, white(1));
    canvas.drawPath(
      Path()
        ..moveTo(c.dx - r * .42, c.dy)
        ..lineTo(c.dx - r * .08, c.dy + r * .34)
        ..lineTo(c.dx + r * .45, c.dy - r * .3),
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
