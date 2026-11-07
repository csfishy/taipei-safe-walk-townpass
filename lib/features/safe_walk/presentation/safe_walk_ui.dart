import 'package:flutter/material.dart';
import 'package:town_pass/util/tp_colors.dart';
import 'package:town_pass/util/tp_text.dart';

/// 安心行用色：全部引用官方 TPColors，依 docs/SAFE_WALK_COLOR_SPEC.md 的可讀配對。
/// 白字只放在 primary700／red600 上；primary500 只當品牌點綴、邊框與圖示。
abstract final class SwColors {
  static const brand = TPColors.primary500;
  static const brandDeep = TPColors.primary700;
  static const brandDeeper = TPColors.primary800;
  static const brandSoft = TPColors.primary50;
  static const text = TPColors.grayscale900;
  static const textSecondary = TPColors.grayscale700;
  static const bg = TPColors.grayscale50;
  static const surface = TPColors.white;
  static const border = TPColors.grayscale200;
  static const warnBg = TPColors.secondary50;
  static const warnText = TPColors.secondary800;
  static const warnMark = TPColors.secondary500;
  static const sos = TPColors.red600;
  static const sosPressed = TPColors.red700;
  static const secondaryFocus = TPColors.secondary500;
  static const onDeep = TPColors.white;
}

/// 字級：以臺北通 TPTextStyles 為基礎，次要資訊至少 16，照顧長輩閱讀。
abstract final class SwText {
  static TextStyle title = TPTextStyles.h2SemiBold.copyWith(color: SwColors.text);
  static TextStyle heading = TPTextStyles.h3SemiBold.copyWith(fontSize: 18, color: SwColors.text);
  static TextStyle body = TPTextStyles.h3Regular.copyWith(color: SwColors.text, height: 1.5);
  static TextStyle bodyStrong = TPTextStyles.h3SemiBold.copyWith(color: SwColors.text, height: 1.5);
  static TextStyle secondary = TPTextStyles.h3Regular.copyWith(color: SwColors.textSecondary, height: 1.5);
  static TextStyle small = TPTextStyles.bodyRegular.copyWith(color: SwColors.textSecondary, height: 1.5);
}

const double swTouch = 48;
const double swTouchLarge = 56;

/// 陰影：沿用官方 TPCard 的柔和投影，再加一層近距離陰影，讓浮在地圖上的元件有層次。
abstract final class SwShadow {
  static final card = [BoxShadow(color: TPColors.black.withValues(alpha: .04), blurRadius: 12, offset: const Offset(0, 4))];
  static final float = [
    BoxShadow(color: TPColors.black.withValues(alpha: .10), blurRadius: 16, offset: const Offset(0, 6)),
    BoxShadow(color: TPColors.black.withValues(alpha: .06), blurRadius: 3, offset: const Offset(0, 1)),
  ];
  static final sheet = [BoxShadow(color: TPColors.black.withValues(alpha: .08), blurRadius: 20, offset: const Offset(0, -4))];
}

/// 動畫時間：系統關閉動畫時一律為 0。
abstract final class SwMotion {
  static Duration of(BuildContext context, int ms) => (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ? Duration.zero : Duration(milliseconds: ms);
  static const curve = Curves.easeOutCubic;
}

/// 載入中：用官方 TPShimmerWidget 的骨架樣式。
class SwSkeleton extends StatelessWidget {
  const SwSkeleton({super.key, this.rows = 3});
  final int rows;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '載入中',
    child: Column(
      children: [
        for (var i = 0; i < rows; i++)
          Container(
            height: 64,
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(color: TPColors.grayscale100, borderRadius: BorderRadius.circular(12)),
          ),
      ],
    ),
  );
}

/// 空值／錯誤狀態：圖示＋一句說明＋下一步動作，不讓使用者卡住。
class SwStateMessage extends StatelessWidget {
  const SwStateMessage({super.key, required this.icon, required this.title, required this.message, this.actionLabel, this.onAction, this.error = false});
  final IconData icon;
  final String title, message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool error;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: error ? TPColors.red50 : SwColors.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: error ? TPColors.red200 : SwColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: error ? SwColors.sos : SwColors.brandDeep),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title, style: SwText.heading.copyWith(color: error ? SwColors.sos : SwColors.text)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(message, style: SwText.body),
          if (actionLabel != null && onAction != null) ...[const SizedBox(height: 12), SwChip(label: actionLabel!, icon: error ? Icons.refresh_rounded : null, onTap: onAction)],
        ],
      ),
    ),
  );
}

/// 按下回饋：縮小 + 換色；系統關閉動畫時只換色。
class SwPressable extends StatefulWidget {
  const SwPressable({super.key, required this.child, required this.onTap, this.color, this.pressedColor, this.border, this.radius = 12, this.padding, this.semanticsLabel, this.selected});
  final Widget child;
  final VoidCallback? onTap;
  final Color? color;
  final Color? pressedColor;
  final BorderSide? border;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final String? semanticsLabel;
  final bool? selected;

  @override
  State<SwPressable> createState() => _SwPressableState();
}

class _SwPressableState extends State<SwPressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final enabled = widget.onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      selected: widget.selected,
      label: widget.semanticsLabel,
      child: AnimatedScale(
        scale: _down && !reduce ? .96 : 1,
        duration: const Duration(milliseconds: 100),
        child: Material(
          color: (_down ? (widget.pressedColor ?? widget.color) : widget.color) ?? Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(widget.radius), side: widget.border ?? BorderSide.none),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            highlightColor: Colors.transparent,
            hoverColor: SwColors.brand.withValues(alpha: .08),
            splashColor: SwColors.brand.withValues(alpha: .16),
            onHighlightChanged: (v) => setState(() => _down = v),
            child: Padding(padding: widget.padding ?? EdgeInsets.zero, child: widget.child),
          ),
        ),
      ),
    );
  }
}

/// 主要按鈕：primary700 底白字（官方 primary500 配白字對比不足）。
class SwPrimaryButton extends StatelessWidget {
  const SwPrimaryButton({super.key, required this.label, this.icon, required this.onTap});
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SwPressable(
    onTap: onTap,
    color: onTap == null ? TPColors.grayscale100 : SwColors.brandDeep,
    pressedColor: TPColors.primary800,
    radius: 8,
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: SizedBox(
      height: swTouch,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[Icon(icon, size: 20, color: onTap == null ? SwColors.textSecondary : SwColors.onDeep), const SizedBox(width: 8)],
          Text(label, style: SwText.bodyStrong.copyWith(color: onTap == null ? SwColors.textSecondary : SwColors.onDeep)),
        ],
      ),
    ),
  );
}

/// 次要動作：白底品牌色框的膠囊按鈕（同臺北通 secondary 按鈕語彙）。
class SwChip extends StatelessWidget {
  const SwChip({super.key, required this.label, this.icon, required this.onTap, this.selected = false});
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final fg = onTap == null ? SwColors.textSecondary : SwColors.brandDeep;
    return SwPressable(
      onTap: onTap,
      selected: selected,
      color: selected ? SwColors.brandSoft : SwColors.surface,
      pressedColor: SwColors.brandSoft,
      border: BorderSide(color: selected ? SwColors.brand : SwColors.border),
      radius: 24,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        height: swTouch,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 20, color: fg), const SizedBox(width: 6)],
            Text(label, style: SwText.bodyStrong.copyWith(color: fg)),
          ],
        ),
      ),
    );
  }
}

/// 緊急求助：紅底白字，有圖示也有文字，不能只靠顏色。
class SwSosButton extends StatelessWidget {
  const SwSosButton({super.key, required this.onTap, this.expand = false});
  final VoidCallback onTap;
  final bool expand;

  @override
  Widget build(BuildContext context) => SwPressable(
    onTap: onTap,
    color: SwColors.sos,
    pressedColor: SwColors.sosPressed,
    radius: 12,
    semanticsLabel: '緊急求助',
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: swTouchLarge),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.sos_rounded, size: 26, color: SwColors.onDeep),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '緊急求助',
                textAlign: TextAlign.center,
                style: SwText.heading.copyWith(color: SwColors.onDeep),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 示範模式標示：所有安心行畫面都要看得到。
class SwMockBadge extends StatelessWidget {
  const SwMockBadge({super.key, this.text = '示範模式・未通知任何人'});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: SwColors.warnBg,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: TPColors.secondary300),
    ),
    child: Text(
      text,
      style: SwText.small.copyWith(color: SwColors.warnText, fontWeight: FontWeight.w600),
    ),
  );
}

/// 圓形浮動按鈕（返回、關閉）。
class SwRoundButton extends StatelessWidget {
  const SwRoundButton({super.key, required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: SwShadow.float),
    child: SwPressable(
      onTap: onTap,
      color: SwColors.surface,
      pressedColor: SwColors.brandSoft,
      radius: swTouch / 2,
      semanticsLabel: label,
      child: SizedBox(
        width: swTouch,
        height: swTouch,
        child: Icon(icon, color: SwColors.text),
      ),
    ),
  );
}

/// 底列的次要動作（模擬來電、結束通話）：白底灰框，比緊急求助低調。
class SwSecondaryAction extends StatelessWidget {
  const SwSecondaryAction({super.key, required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SwPressable(
    onTap: onTap,
    color: SwColors.surface,
    pressedColor: SwColors.brandSoft,
    border: const BorderSide(color: SwColors.border),
    radius: 12,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: swTouchLarge - 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: SwColors.textSecondary),
          const SizedBox(width: 8),
          Flexible(child: Text(label, style: SwText.bodyStrong)),
        ],
      ),
    ),
  );
}

/// 最底列：寬度足夠時「左次要、右緊急求助」；窄螢幕（< 360）或字級放大時改成上下排，緊急求助在上、滿寬。
class SwActionBar extends StatelessWidget {
  const SwActionBar({super.key, required this.secondary, required this.onEmergency});
  final Widget secondary;
  final VoidCallback onEmergency;
  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: SwColors.surface,
      border: Border(top: BorderSide(color: SwColors.border)),
    ),
    padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.paddingOf(context).bottom),
    child: LayoutBuilder(
      builder: (context, box) {
        final bigText = MediaQuery.textScalerOf(context).scale(16) > 20;
        if (box.maxWidth < 360 || bigText) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwSosButton(onTap: onEmergency, expand: true),
              const SizedBox(height: 8),
              secondary,
            ],
          );
        }
        return Row(
          children: [
            Flexible(child: secondary),
            const SizedBox(width: 16),
            const Spacer(),
            SwSosButton(onTap: onEmergency),
          ],
        );
      },
    ),
  );
}
