import 'package:flutter/material.dart';
import 'package:town_pass/util/tp_colors.dart';
import 'package:town_pass/util/tp_text.dart';

/// 安心行用色：全部引用官方 TPColors，依 docs/SAFE_WALK_COLOR_SPEC.md 的可讀配對。
/// 主色用 primary500（同臺北通），上面放白字與白色圖示，與臺北通相同。
abstract final class SwColors {
  /// 臺北通主色（同 App 長條、服務卡）：路線、圖示、邊框、選取與填色；填色上的字與圖示用 [onBrand]。
  static const brand = TPColors.primary500;

  /// 放在 [brand] 上的字與圖示：白色，與臺北通長條、服務卡一致（白／primary500 對比 2.39:1，低於 WCAG，11/7 使用者決定沿用臺北通做法）。
  static const onBrand = TPColors.white;

  /// 主色系「文字」：白底上要 4.5:1，primary500 只有 2.39:1，所以文字用 primary700。
  static const brandText = TPColors.primary700;

  /// 只在必須放白字的深色區塊使用（夜間情境卡）。
  static const brandDeep = TPColors.primary700;
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
  // 與臺北通 TPText 一致：英文與數字用 Roboto，中文落到 PingFangTC（Roboto 沒有中文字）。
  static TextStyle _tp(TextStyle s) => s.copyWith(fontFamily: 'Roboto', fontFamilyFallback: const ['PingFangTC']);
  // 字級一律對應 TPTextStyles，用法比照臺北通：頁面大標 24、彈出選單標題 18、卡片／清單／區塊標題與內文 16、說明 14、小字 12。
  // 臺北通頁面不用 36，所以這裡也不提供。不在畫面上另設 fontSize、fontWeight。
  static TextStyle title = _tp(TPTextStyles.h2SemiBold.copyWith(color: SwColors.text)); // 24 頁面大標
  static TextStyle heading = _tp(TPTextStyles.titleSemiBold.copyWith(color: SwColors.text)); // 18 彈出選單／狀態標題
  static TextStyle body = _tp(TPTextStyles.h3Regular.copyWith(color: SwColors.text, height: 1.5)); // 16
  static TextStyle bodyStrong = _tp(TPTextStyles.h3SemiBold.copyWith(color: SwColors.text, height: 1.5)); // 16
  static TextStyle secondary = _tp(TPTextStyles.h3Regular.copyWith(color: SwColors.textSecondary, height: 1.5)); // 16
  static TextStyle small = _tp(TPTextStyles.bodyRegular.copyWith(color: SwColors.textSecondary, height: 1.5)); // 14
  static TextStyle smallStrong = _tp(TPTextStyles.bodySemiBold.copyWith(color: SwColors.textSecondary, height: 1.5)); // 14
  static TextStyle caption = _tp(TPTextStyles.caption.copyWith(color: SwColors.textSecondary)); // 12
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
              Icon(icon, color: error ? SwColors.sos : SwColors.brand),
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

/// 主要按鈕：臺北通主色 primary500 底＋白字（同臺北通 TPButton.primary）。
class SwPrimaryButton extends StatelessWidget {
  const SwPrimaryButton({super.key, required this.label, this.icon, required this.onTap});
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SwPressable(
    onTap: onTap,
    color: onTap == null ? TPColors.grayscale100 : SwColors.brand,
    pressedColor: TPColors.primary600, // 同官方 TPButton.primary
    radius: 8,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    // 至少 48 高；空間不夠（例如兩顆並排或字放大）時換行，不截字。
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: swTouch - 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[Icon(icon, size: 20, color: onTap == null ? SwColors.textSecondary : SwColors.onBrand), const SizedBox(width: 8)],
          Flexible(
            child: Text(label, textAlign: TextAlign.center, style: SwText.bodyStrong.copyWith(color: onTap == null ? SwColors.textSecondary : SwColors.onBrand)),
          ),
        ],
      ),
    ),
  );
}

/// 外框按鈕：白底主色框（同官方 TPButton.secondary），與 [SwPrimaryButton] 同高同圓角。
class SwOutlineButton extends StatelessWidget {
  const SwOutlineButton({super.key, required this.label, this.icon, required this.onTap});
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = onTap == null ? SwColors.textSecondary : SwColors.brandText;
    return SwPressable(
      onTap: onTap,
      color: SwColors.surface,
      pressedColor: TPColors.primary50, // 同官方 TPButton.secondary
      border: BorderSide(color: onTap == null ? SwColors.border : SwColors.brand),
      radius: 8,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: swTouch - 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[Icon(icon, size: 20, color: fg), const SizedBox(width: 6)],
            Flexible(
              child: Text(label, textAlign: TextAlign.center, style: SwText.bodyStrong.copyWith(color: fg)),
            ),
          ],
        ),
      ),
    );
  }
}

/// 二選一：兩顆等寬按鈕，左邊主要、右邊次要（參考 2024 得獎作品 ParkFlow 的底部卡片）。
class SwButtonPair extends StatelessWidget {
  const SwButtonPair({super.key, required this.first, required this.second});
  final Widget first, second;
  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    // 一顆換行時另一顆一起變高，兩顆維持一樣大。
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: first),
        const SizedBox(width: 12),
        Expanded(child: second),
      ],
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
    final fg = onTap == null ? SwColors.textSecondary : SwColors.brandText;
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
                style: SwText.bodyStrong.copyWith(color: SwColors.onDeep),
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
    child: Text(text, style: SwText.smallStrong.copyWith(color: SwColors.warnText)),
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
          Flexible(
            child: Text(label, maxLines: 1, softWrap: false, overflow: TextOverflow.fade, style: SwText.bodyStrong),
          ),
        ],
      ),
    ),
  );
}

/// 最底列：寬度足夠時「左次要、右緊急求助」；窄螢幕（畫面寬 < 360，扣掉左右留白後 < 328）或字級放大時改成上下排，緊急求助在上、滿寬。
class SwActionBar extends StatelessWidget {
  const SwActionBar({super.key, required Widget this.secondary, required this.onEmergency});

  /// 只有緊急求助（例如首頁）。
  const SwActionBar.single({super.key, required this.onEmergency}) : secondary = null;
  final Widget? secondary;
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
        if (secondary == null) return SwSosButton(onTap: onEmergency, expand: true);
        final bigText = MediaQuery.textScalerOf(context).scale(16) > 20;
        if (box.maxWidth < 328 || bigText) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwSosButton(onTap: onEmergency, expand: true),
              const SizedBox(height: 8),
              secondary!,
            ],
          );
        }
        return Row(
          children: [
            secondary!,
            const SizedBox(width: 12),
            Expanded(child: SwSosButton(onTap: onEmergency, expand: true)),
          ],
        );
      },
    ),
  );
}
