import 'package:flutter_svg/flutter_svg.dart';
import 'package:town_pass/features/safe_walk/presentation/assets/safe_walk_card_assets.dart';
import 'package:flutter/material.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_sources.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_ui.dart';
import 'package:town_pass/util/tp_app_bar.dart';
import 'package:town_pass/util/tp_colors.dart';

enum SafeWalkEntry { map, call, points, report }

/// 入口頁：比照臺北通開啟服務時的樣式——上方主色長條＋右上關閉；
/// 時間情境卡、「安心行」主卡（臺北天際線插圖）、其他功能一項一行、最下方緊急求助。
class SafeWalkHomeView extends StatelessWidget {
  const SafeWalkHomeView({
    super.key,
    required this.onOpen,
    required this.onEmergency,
    required this.avoided,
    this.destination = '家',
    this.homeSet = false,
    this.onEditHome,
    this.onBack,
    this.now,
    this.isLive = false,
  });
  final bool isLive;
  final ValueChanged<SafeWalkEntry> onOpen;
  final VoidCallback onEmergency;

  /// 關閉安心行、回到臺北通（右上 ✕）。
  final VoidCallback? onBack;
  final int avoided;
  final String destination;

  /// 使用者是否已設定自己的「家」；[onEditHome] 為 null 時不顯示設定入口。
  final bool homeSet;
  final VoidCallback? onEditHome;

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
              style: const ButtonStyle(
                iconSize: WidgetStatePropertyAll<double>(24),
              ),
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
                Semantics(
                  header: true,
                  label: '臺北安心行',
                  child: const SizedBox.shrink(),
                ),
                _ContextCard(now: t),
                const SizedBox(height: 16),
                _GoHomeCard(
                  destination: destination,
                  avoided: avoided,
                  isLive: isLive,
                  onTap: () => onOpen(SafeWalkEntry.map),
                ),
                if (onEditHome != null) ...[
                  const SizedBox(height: 16),
                  _FeatureRow(
                    icon: Icons.home_rounded,
                    name: homeSet ? '編輯「家」' : '設定「家」',
                    desc: homeSet ? '更換或移除家的位置' : '第一次使用請先設定，儲存在裝置上',
                    onTap: onEditHome!,
                  ),
                ],
                const SizedBox(height: 24),
                Semantics(
                  header: true,
                  child: Text('其他功能', style: SwText.bodyStrong),
                ),
                const SizedBox(height: 12),
                for (final (id, icon, name, desc) in _more) ...[
                  _FeatureRow(
                    icon: icon,
                    name: name,
                    desc: isLive && id == SafeWalkEntry.report
                        ? '歷史資料來源、更新日期與限制'
                        : desc,
                    onTap: () => onOpen(id),
                  ),
                  const SizedBox(height: 10),
                ],
                const Align(
                  alignment: Alignment.centerLeft,
                  child: SwSourcesLink(),
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

/// 時間情境卡：圖示｜分隔線｜時間與一句建議。夜間（18–06 點）改深色並提醒走明亮的路。
class _ContextCard extends StatelessWidget {
  const _ContextCard({required this.now});
  final DateTime now;
  @override
  Widget build(BuildContext context) {
    final night = now.hour >= 18 || now.hour < 6;
    final hhmm =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: night ? TPColors.primary800 : SwColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: SwShadow.card,
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Icon(
              night ? Icons.nightlight_round : Icons.wb_sunny_rounded,
              color: night ? TPColors.secondary300 : TPColors.secondary600,
              size: 32,
            ),
            const SizedBox(width: 14),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: night ? TPColors.primary600 : SwColors.border,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$hhmm・${night ? '天色已暗' : '白天'}',
                    style: SwText.bodyStrong.copyWith(
                      color: night ? SwColors.onDeep : SwColors.text,
                    ),
                  ),
                  Text(
                    night ? '建議走明亮的大路' : '出門前看看沿路回報',
                    style: SwText.body.copyWith(
                      color: night
                          ? TPColors.primary100
                          : SwColors.textSecondary,
                    ),
                  ),
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
class _GoHomeCard extends StatefulWidget {
  const _GoHomeCard({
    required this.destination,
    required this.avoided,
    required this.onTap,
    required this.isLive,
  });
  final bool isLive;
  final String destination;
  final int avoided;
  final VoidCallback onTap;

  @override
  State<_GoHomeCard> createState() => _GoHomeCardState();
}

/// 依 Figma「安心行」卡片 State=Default／Pressed：深青→主色漸層、透明底白色插圖、白字；
/// 按下時整張卡（含文字）蓋一層 25% primary800，不縮放。
class _GoHomeCardState extends State<_GoHomeCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: widget.isLive
        ? '安心行，選擇目的地並規劃步行路線，點擊開始'
        : '安心行，前往${widget.destination}，已繞開 ${widget.avoided} 個異常回報，點擊開始',
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: SwShadow.float,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: widget.onTap,
            onHighlightChanged: (v) => setState(() => _pressed = v),
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            hoverColor: TPColors.primary800.withValues(alpha: .08),
            child: ExcludeSemantics(
              child: Stack(
                children: [
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            TPColors.primary700,
                            TPColors.primary600,
                            TPColors.primary500,
                          ],
                          stops: [0, .45, 1],
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: SvgPicture.string(
                      swCardArtSvg,
                      fit: BoxFit.cover,
                      alignment: Alignment.bottomRight,
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: 211,
                      minWidth: double.infinity,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '安心行',
                            style: SwText.title.copyWith(color: TPColors.white),
                          ),
                          Text(
                            'Safe Walk',
                            style: SwText.small.copyWith(color: TPColors.white),
                          ),
                          const SizedBox(height: 48),
                          ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 56),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SvgPicture.string(
                                  swCardNavigationSvg,
                                  width: 26,
                                  height: 26,
                                ),
                                const SizedBox(width: 10),
                                Flexible(
                                  child: Text(
                                    '點擊開始',
                                    style: SwText.bodyStrong.copyWith(
                                      color: TPColors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: _pressed ? 1 : 0,
                        duration: SwMotion.of(context, 100),
                        child: ColoredBox(
                          color: TPColors.primary800.withValues(alpha: .25),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// 其他功能：一項一行的卡片（圖示｜名稱＋說明｜箭頭），點擊範圍整行。
class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.name,
    required this.desc,
    required this.onTap,
  });
  final IconData icon;
  final String name, desc;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      boxShadow: SwShadow.card,
    ),
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
            Icon(icon, size: 30, color: SwColors.brand),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: SwText.bodyStrong),
                  Text(desc, style: SwText.secondary),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: SwColors.textSecondary,
            ),
          ],
        ),
      ),
    ),
  );
}
