import 'package:flutter/material.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_ui.dart';

enum SafeWalkEntry { map, call, points, report }

/// 首頁：四個入口由上到下，最下方緊急求助。名稱下方一句白話說明，照顧不熟手機的長輩。
class SafeWalkHomeView extends StatelessWidget {
  const SafeWalkHomeView({super.key, required this.onOpen, required this.onEmergency, this.onBack});
  final ValueChanged<SafeWalkEntry> onOpen;
  final VoidCallback onEmergency;
  final VoidCallback? onBack;

  static const _entries = [
    (SafeWalkEntry.map, Icons.home_rounded, '安心回家', '看回家路線，避開別人回報的狀況'),
    (SafeWalkEntry.call, Icons.phone_in_talk_rounded, '模擬來電', '假裝家人打來陪你講電話，路上比較安心'),
    (SafeWalkEntry.points, Icons.local_police_rounded, '附近求助地點', '警察局、便利商店等可以求助的地方'),
    (SafeWalkEntry.report, Icons.campaign_rounded, '回報狀況', '看到打架、暗路、施工，標給大家知道'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SwColors.bg,
      appBar: AppBar(
        backgroundColor: SwColors.surface,
        foregroundColor: SwColors.textSecondary,
        elevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
        leading: onBack == null ? null : IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), tooltip: '返回', onPressed: onBack),
        title: Text('臺北安心行', style: SwText.heading),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: SwMockBadge(text: '示範模式（Mock）'),
                  ),
                  const SizedBox(height: 12),
                  for (final (id, icon, name, desc) in _entries) ...[
                    _EntryCard(icon: icon, name: name, desc: desc, main: id == SafeWalkEntry.map, onTap: () => onOpen(id)),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
            Container(
              color: SwColors.surface,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: SwSosButton(onTap: onEmergency, expand: true),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.icon, required this.name, required this.desc, required this.main, required this.onTap});
  final IconData icon;
  final String name, desc;
  final bool main;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = main ? SwColors.onDeep : SwColors.text;
    return SwPressable(
      onTap: onTap,
      semanticsLabel: '$name，$desc',
      color: main ? SwColors.brandDeep : SwColors.surface,
      pressedColor: main ? SwColors.brandDeeper : SwColors.brandSoft,
      border: main ? null : const BorderSide(color: SwColors.border),
      radius: 12,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: ExcludeSemantics(
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: main ? SwColors.surface : SwColors.brandSoft, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 28, color: SwColors.brandDeep),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: SwText.heading.copyWith(color: fg, fontSize: 20)),
                  const SizedBox(height: 2),
                  Text(desc, style: SwText.body.copyWith(color: main ? SwColors.onDeep : SwColors.textSecondary)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: main ? SwColors.onDeep : SwColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
