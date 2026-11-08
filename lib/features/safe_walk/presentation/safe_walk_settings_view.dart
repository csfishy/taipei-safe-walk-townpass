import 'package:flutter/material.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_nearby_helper.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_ui.dart';
import 'package:town_pass/util/tp_app_bar.dart';
import 'package:town_pass/util/tp_colors.dart';

/// 安心行設定：家的位置、附近協助者。從首頁右上齒輪進入，不放在首頁主畫面。
class SafeWalkSettingsView extends StatelessWidget {
  const SafeWalkSettingsView({
    super.key,
    required this.onBack,
    this.onEditHome,
    this.homeSet = false,
    this.nearbyHelper,
  });

  /// 返回首頁。
  final VoidCallback onBack;

  /// 設定／編輯「家」；null 時不顯示這一項（例如未接儲存功能）。
  final VoidCallback? onEditHome;

  /// 使用者是否已設定自己的「家」，決定文字是「設定」或「編輯」。
  final bool homeSet;

  /// 「附近協助者」；null 時不顯示。
  final SafeWalkNearbyHelper? nearbyHelper;

  @override
  Widget build(BuildContext context) {
    final hasHome = onEditHome != null;
    final hasHelper = nearbyHelper != null;
    return Scaffold(
      backgroundColor: SwColors.bg,
      appBar: TPAppBar(
        backgroundColor: TPColors.primary500,
        foregroundColor: TPColors.white,
        leading: IconButton(
          tooltip: '返回',
          color: TPColors.white,
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: onBack,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Semantics(header: true, child: Text('安心行設定', style: SwText.title)),
          const SizedBox(height: 16),
          if (hasHome) ...[
            Semantics(
              header: true,
              child: Text('我的地點', style: SwText.bodyStrong),
            ),
            const SizedBox(height: 12),
            SwFeatureRow(
              icon: Icons.home_rounded,
              name: homeSet ? '編輯「家」' : '設定「家」',
              desc: homeSet ? '更換或移除家的位置' : '第一次使用請先設定，儲存在裝置上',
              onTap: onEditHome!,
            ),
            const SizedBox(height: 24),
          ],
          if (hasHelper) ...[
            Semantics(
              header: true,
              child: Text('附近協助者', style: SwText.bodyStrong),
            ),
            const SizedBox(height: 12),
            SafeWalkNearbyHelperCard(helper: nearbyHelper!),
          ],
          if (!hasHome && !hasHelper)
            Text('目前沒有可調整的設定。', style: SwText.secondary),
        ],
      ),
    );
  }
}
