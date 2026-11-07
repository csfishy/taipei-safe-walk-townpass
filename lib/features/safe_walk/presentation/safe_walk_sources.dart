import 'package:flutter/material.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_ui.dart';

/// 一項資料來源。[demo] 為 true 表示目前畫面用的是示範資料，不是開放資料。
class SwDataSource {
  const SwDataSource({
    required this.title,
    required this.provider,
    required this.license,
    this.note,
    this.url,
    this.demo = false,
  });
  final String title, provider, license;
  final String? note, url;
  final bool demo;
}

/// 安心行用到的資料來源與授權（競賽須知：核心資料須為合法公開資料並註明來源）。
/// 只陳述來源與授權，不代表該資料已在目前版本啟用；狀態以畫面上的示範標示為準。
const swDataSources = <SwDataSource>[
  SwDataSource(
    title: '地圖底圖',
    provider: '© OpenStreetMap contributors',
    license: 'ODbL 1.0（開放資料庫授權）',
    note: '地圖圖磚自動載入，不再詢問。OpenStreetMap（tile.openstreetmap.org）會收到目前檢視範圍與 IP。',
    url: 'https://www.openstreetmap.org/copyright',
  ),
  SwDataSource(
    title: '步行路線',
    provider: 'OSRM 步行路線（routing.openstreetmap.de），使用 OpenStreetMap 資料',
    license: 'ODbL 1.0',
    note: '路線僅供參考，不代表沿途安全。',
  ),
  SwDataSource(
    title: '避開回報點的步行路線',
    provider: 'Valhalla 路線引擎（valhalla1.openstreetmap.de，FOSSGIS 提供），使用 OpenStreetMap 資料',
    license: '軟體 MIT License；路網資料 ODbL 1.0',
    note: '回報點與犯罪參考位置使用產品設定的 50 公尺避讓緩衝；不是官方犯罪範圍或來源精度保證。路線僅供參考，不代表沿途安全。',
    url: 'https://github.com/valhalla/valhalla',
  ),
  SwDataSource(
    title: '附近便利商店',
    provider: 'OpenStreetMap（Overpass API）',
    license: 'ODbL 1.0',
    note: '便利商店不等於政府認證的求助據點。',
  ),
  SwDataSource(
    title: '暴力犯罪月統計',
    provider: '臺北市政府主計處（臺北市資料大平臺）',
    license: '政府資料開放授權條款－第 1 版',
    note: '全市統計，不代表個別路段的風險。',
    url: 'https://data.taipei/dataset/detail?id=33dc5028-78ef-4892-bec6-0b459f7cb193',
  ),
  SwDataSource(title: '陪伴通話劇本', provider: '團隊自製；由手機內建文字轉語音朗讀', license: '團隊作品'),
  SwDataSource(
    title: '本服務程式',
    provider: '以臺北市政府「臺北通 TownPass」開源專案為基礎',
    license: 'GPL-3.0（上游授權）',
    url: 'https://github.com/taipei-doit/TownPass',
  ),
];

/// 一個查詢設定（例如路線查詢、犯罪資料查詢）；點了開啟同意視窗。
typedef SwQuerySetting = ({
  IconData icon,
  String label,
  String status,
  VoidCallback onTap,
});

/// 從下方彈出的「資料來源與授權」說明；[settings] 放在最上方。
Future<void> showSwDataSources(
  BuildContext context, {
  List<SwQuerySetting> settings = const [],
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: SwColors.surface,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
  ),
  builder: (sheet) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(sheet).height * .85,
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: SwColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (settings.isNotEmpty) ...[
            Semantics(header: true, child: Text('查詢設定', style: SwText.heading)),
            const SizedBox(height: 8),
            for (final setting in settings)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SwPressable(
                  onTap: () {
                    Navigator.of(sheet).pop();
                    setting.onTap();
                  },
                  color: SwColors.bg,
                  border: const BorderSide(color: SwColors.border),
                  radius: 10,
                  semanticsLabel: '${setting.label}，${setting.status}',
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 56),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          Icon(setting.icon, color: SwColors.brand),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(setting.label, style: SwText.bodyStrong),
                                Text(setting.status, style: SwText.small),
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
                ),
              ),
            const SizedBox(height: 12),
          ],
          Semantics(
            header: true,
            child: Text('資料來源與授權', style: SwText.heading),
          ),
          const SizedBox(height: 4),
          Text('安心行使用的開放資料與授權。', style: SwText.small),
          const SizedBox(height: 12),
          for (final s in swDataSources) _SourceRow(source: s),
        ],
      ),
    ),
  ),
);

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.source});
  final SwDataSource source;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: SwColors.bg,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(source.title, style: SwText.bodyStrong)),
            if (source.demo) const SwMockBadge(text: '示範'),
          ],
        ),
        const SizedBox(height: 2),
        Text(source.provider, style: SwText.body),
        Text('授權：${source.license}', style: SwText.small),
        if (source.note != null) Text(source.note!, style: SwText.small),
        if (source.url != null)
          SelectableText(
            source.url!,
            style: SwText.small.copyWith(color: SwColors.brandText),
          ),
      ],
    ),
  );
}

/// 小型文字連結：開啟資料來源與授權。點擊範圍 ≥ 48。
class SwSourcesLink extends StatelessWidget {
  const SwSourcesLink({super.key, this.settings = const []});

  /// 查詢設定，顯示在資料來源與授權的最上方。
  final List<SwQuerySetting> settings;
  @override
  Widget build(BuildContext context) => SwPressable(
    onTap: () => showSwDataSources(context, settings: settings),
    radius: 8,
    semanticsLabel: '資料來源與授權',
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: SizedBox(
      height: swTouch,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: SwColors.brandText,
          ),
          const SizedBox(width: 4),
          Text(
            '資料來源與授權',
            style: SwText.smallStrong.copyWith(
              color: SwColors.brandText,
              decoration: TextDecoration.underline,
            ),
          ),
        ],
      ),
    ),
  );
}
