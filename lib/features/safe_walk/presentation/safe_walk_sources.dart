import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// 一項資料來源或開源元件。收合時只顯示名稱、提供者、用途；展開後列出其餘欄位。
/// 不確定的欄位留 null（畫面不顯示），不拿頁面更新日期代替資料日期。
class SwDataSource {
  const SwDataSource({
    required this.title,
    required this.provider,
    required this.purpose,
    this.license,
    this.licenseUrl,
    this.sourceUrl,
    this.period,
    this.retrieved,
    this.update,
    this.limit,
    this.snapshotAsset,
    this.datasets,
  });
  final String title, provider, purpose;
  final String? license, licenseUrl, sourceUrl, period, retrieved, update, limit;

  /// App 內建快照的檔案；取得時間與筆數從檔案讀出，不寫死。
  final String? snapshotAsset;

  /// 包含的原始資料集（展開後才顯示）。
  final String? datasets;
}

/// 讀快照的 retrievedAt 與筆數，轉成臺北時間；讀不到就回 null（畫面不顯示這一列）。
Future<String?> _snapshotRetrieved(String asset) async {
  try {
    final data = jsonDecode(await rootBundle.loadString(asset)) as Map<String, dynamic>;
    final at = DateTime.parse(data['retrievedAt'] as String).toUtc().add(const Duration(hours: 8));
    String two(int n) => n.toString().padLeft(2, '0');
    final rows = (data['rows'] as List).length;
    return '${at.year}-${two(at.month)}-${two(at.day)} ${two(at.hour)}:${two(at.minute)}（臺北時間）・$rows 筆';
  } catch (_) {
    return null;
  }
}

const _osmCopyright = 'https://www.openstreetmap.org/copyright';

/// 犯罪資料卡固定保留的限制說明。
const swCrimeDataLimit =
    '歷史紀錄與參考位置不代表即時道路風險。50 公尺為本服務設定的避讓緩衝，並非官方案發範圍；未收錄資料不代表沒有風險。';

/// 開放資料（競賽須知：核心資料須為合法公開資料並註明來源）。只列目前流程實際使用的資料。
const swOpenData = <SwDataSource>[
  SwDataSource(
    title: '地圖與步行路網',
    provider: '© OpenStreetMap contributors',
    purpose: '顯示地圖，並計算步行與避讓路線',
    license: 'ODbL 1.0',
    licenseUrl: _osmCopyright,
    sourceUrl: 'https://www.openstreetmap.org/',
    update: '地圖圖磚與路線在使用時線上取得',
    limit: '地圖圖磚自動載入，不再詢問；地圖服務會收到目前檢視範圍與 IP。路線僅供參考，不代表沿途安全。',
  ),
  SwDataSource(
    title: '附近便利商店與警察設施',
    provider: '© OpenStreetMap contributors',
    purpose: '找出離你最近、標示營業中的便利商店與警察設施',
    license: 'ODbL 1.0',
    licenseUrl: _osmCopyright,
    sourceUrl: 'https://www.openstreetmap.org/',
    update: 'App 內建的 OpenStreetMap 地點快照，不會即時查詢',
    snapshotAsset: 'assets/safe_walk/osm_help_points_taipei.json',
    limit: '營業時間來自地圖標記，不是即時營業確認；便利商店不等於政府認證的求助據點。',
  ),
  SwDataSource(
    title: '政府公開犯罪參考資料',
    provider: '臺北市資料大平臺等北北基官方公開案件資料（8 個資料集）',
    purpose: '在地圖上標出歷史犯罪參考位置，規劃路線時一起避開',
    datasets: '臺北市：住宅、汽車、機車、自行車竊盜與街頭隨機強盜、搶奪點位資訊（臺北市政府警察局刑警大隊）；新北市、基隆市資料集見「回報資料說明」。共 10 個資源、2,542 筆來源紀錄，其中 1,366 筆有參考位置',
    sourceUrl: 'https://data.taipei/dataset?p=1&limit=10&sort=_score_desc&qs=%E7%8A%AF%E7%BD%AA&type=dataset&type=openapi&bool_type=dataset&bool_type=openapi&bool_type=OR&is_included_sub_org=0',
    period: '臺北至 2026-09-29、新北至 2026-06-30、基隆至 2026-09-30；不是全年或全部案類',
    update: '整理後存於雲端資料庫，規劃路線時線上查詢',
    license: '臺北市資料大平臺標示「公開」；各資料集的名稱、網址與授權，連線時在「回報資料說明」逐筆列出',
    limit: '$swCrimeDataLimit基隆的紀錄沒有參考位置，不會出現在地圖上，也不會納入避讓。',
  ),
];

/// 開源技術：軟體授權與資料授權分開寫。
const swOpenSource = <SwDataSource>[
  SwDataSource(
    title: 'Valhalla 路線引擎',
    provider: 'Valhalla 開源社群；公共服務由 FOSSGIS 提供（valhalla1.openstreetmap.de）',
    purpose: '計算避開回報點與犯罪參考位置的步行路線',
    license: '軟體 MIT；路網資料 ODbL 1.0',
    licenseUrl: 'https://github.com/valhalla/valhalla/blob/master/COPYING',
    sourceUrl: 'https://github.com/valhalla/valhalla',
    update: '目前使用公共服務，每次規劃時線上查詢',
  ),
  SwDataSource(
    title: 'OSRM 路線引擎',
    provider: 'Project OSRM；公共服務由 FOSSGIS 提供（routing.openstreetmap.de）',
    purpose: 'Valhalla 無法使用時的備援步行路線',
    license: '軟體 BSD-2-Clause；路網資料 ODbL 1.0',
    licenseUrl: 'https://github.com/Project-OSRM/osrm-backend/blob/master/LICENSE.TXT',
    sourceUrl: 'https://github.com/Project-OSRM/osrm-backend',
    limit: '改用備援路線時不會避開緩衝區，畫面會另外提示。',
  ),
  SwDataSource(
    title: 'Flutter 與 Dart',
    provider: 'Google 與 Flutter 開源社群',
    purpose: 'App 的執行環境與介面',
    license: 'BSD-3-Clause',
    sourceUrl: 'https://github.com/flutter/flutter',
  ),
  SwDataSource(
    title: 'flutter_map',
    provider: 'fleaflet 開源社群',
    purpose: '顯示地圖、路線與標記',
    license: 'BSD-3-Clause',
    sourceUrl: 'https://github.com/fleaflet/flutter_map',
  ),
  SwDataSource(
    title: 'flutter_tts',
    provider: 'flutter_tts 開源社群',
    purpose: '呼叫手機內建語音，朗讀模擬來電的台詞',
    license: 'MIT',
    sourceUrl: 'https://github.com/dlutton/flutter_tts',
    limit: '聲音由手機內建的語音引擎產生，那個語音模型不一定是開源的。',
  ),
  SwDataSource(
    title: '手機功能套件',
    provider: 'audioplayers、geolocator、sensors_plus 等開源套件',
    purpose: '播放來電提示音、取得定位、用手機感測器算出面向的方向',
    license: '依各套件授權，見「查看全部第三方授權」',
  ),
  SwDataSource(
    title: 'Supabase 與 PostgreSQL',
    provider: 'Supabase 雲端服務；PostgreSQL 開源社群',
    purpose: '存放與查詢犯罪參考資料與使用者回報',
    license: 'PostgreSQL License；雲端服務依 Supabase 服務條款',
    sourceUrl: 'https://www.postgresql.org/about/licence/',
    limit: '這是儲存服務，不是資料提供者；原始資料來源見「政府公開犯罪參考資料」。',
  ),
];

/// 使用者回報與團隊內容：不是政府資料。
const swTeamContent = <SwDataSource>[
  SwDataSource(
    title: '使用者新增回報',
    provider: '使用安心行的人',
    purpose: '標出暗路、打架等狀況，讓路線避開',
    update: '按「標示到地圖」後存到雲端資料庫，其他人進入地圖也看得到；只存分類、選的位置、說明與時間，不記錄身分或定位紀錄',
    limit: '使用者公開分享、未經核實，不是官方報案或警方受理；送出後無法匿名修改或刪除，說明請不要寫個人資料。',
  ),
  SwDataSource(
    title: '模擬陪伴劇本',
    provider: '安心行團隊製作',
    purpose: '模擬來電時的固定台詞',
    update: '固定劇本，由手機內建語音朗讀',
    license: '團隊製作的內容（不是正式授權名稱）',
  ),
];

/// 一個查詢設定（例如路線查詢、犯罪資料查詢）；點了開啟同意視窗。
typedef SwQuerySetting = ({
  IconData icon,
  String label,
  String status,
  VoidCallback onTap,
});

/// 從下方彈出的「資料來源與授權」；[settings] 放在最上方。關閉後回到原畫面，狀態不變。
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
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text('資料來源與授權', style: SwText.heading),
                ),
              ),
              IconButton(
                tooltip: '關閉',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: const Icon(Icons.close_rounded, color: SwColors.textSecondary),
                onPressed: () => Navigator.of(sheet).pop(),
              ),
            ],
          ),
          Text('了解路線、附近地點與語音的來源及限制。', style: SwText.small),
          for (final (name, items) in [
            ('開放資料', swOpenData),
            ('開源技術', swOpenSource),
            ('使用者回報與團隊內容', swTeamContent),
          ]) ...[
            const SizedBox(height: 16),
            Semantics(header: true, child: Text(name, style: SwText.bodyStrong)),
            const SizedBox(height: 8),
            for (final s in items) _SourceCard(source: s),
            if (identical(items, swOpenSource))
              Align(
                alignment: Alignment.centerLeft,
                child: SwChip(
                  label: '查看全部第三方授權',
                  icon: Icons.description_outlined,
                  onTap: () => showLicensePage(
                    context: sheet,
                    applicationName: '臺北通・安心行',
                  ),
                ),
              ),
          ],
          const SizedBox(height: 16),
          Semantics(header: true, child: Text('版本資訊', style: SwText.bodyStrong)),
          const SizedBox(height: 4),
          const _BuildInfo(),
        ],
      ),
    ),
  ),
);

/// 一筆來源：收合時顯示名稱、提供者、用途；點一下展開其餘欄位與連結。
class _SourceCard extends StatefulWidget {
  const _SourceCard({required this.source});
  final SwDataSource source;
  @override
  State<_SourceCard> createState() => _SourceCardState();
}

class _SourceCardState extends State<_SourceCard> {
  bool _open = false;
  late final Future<String?>? _snapshot = widget.source.snapshotAsset == null
      ? null
      : _snapshotRetrieved(widget.source.snapshotAsset!);

  @override
  Widget build(BuildContext context) {
    final s = widget.source;
    final facts = [
      ('用途', s.purpose),
      if (s.datasets != null) ('資料集', s.datasets!),
      if (s.period != null) ('資料期間', s.period!),
      if (s.retrieved != null) ('取得時間', s.retrieved!),
      if (s.update != null) ('更新方式', s.update!),
      if (s.license != null) ('授權', s.license!),
      if (s.limit != null) ('限制', s.limit!),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: SwColors.bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwPressable(
              onTap: () => setState(() => _open = !_open),
              radius: 10,
              selected: _open,
              semanticsLabel: '${s.title}，${s.provider}，${_open ? '收合' : '展開'}詳細資料',
              padding: const EdgeInsets.all(12),
              child: ExcludeSemantics(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.title, style: SwText.bodyStrong),
                          Text(s.provider, style: SwText.small),
                          if (!_open) Text(s.purpose, style: SwText.small),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      _open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      color: SwColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: SwMotion.of(context, 200),
              curve: SwMotion.curve,
              alignment: Alignment.topCenter,
              child: !_open
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_snapshot != null)
                            FutureBuilder(
                              future: _snapshot,
                              builder: (context, snap) => snap.data == null
                                  ? const SizedBox.shrink()
                                  : _Fact('取得時間', snap.data!),
                            ),
                          for (final (label, value) in facts) _Fact(label, value),
                          if (s.sourceUrl != null || s.licenseUrl != null) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (s.sourceUrl != null)
                                  _LinkButton(label: '查看原始來源', url: s.sourceUrl!),
                                if (s.licenseUrl != null)
                                  _LinkButton(label: '查看授權', url: s.licenseUrl!),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 72, child: Text(label, style: SwText.smallStrong)),
        Expanded(child: Text(value, style: SwText.small)),
      ],
    ),
  );
}

/// 有名稱的連結按鈕，點了用外部瀏覽器開啟；長按複製網址。
class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.label, required this.url});
  final String label, url;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onLongPress: () async {
      await Clipboard.setData(ClipboardData(text: url));
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('已複製網址')),
        );
      }
    },
    child: SwChip(
      label: label,
      icon: Icons.open_in_new_rounded,
      onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
    ),
  );
}

/// App 版本與來源 commit：讀 CI 寫入的 build-info.json，沒有就寫「尚未提供」。
class _BuildInfo extends StatelessWidget {
  const _BuildInfo();
  static final Future<Map<String, dynamic>?> _info = rootBundle
      .loadString('assets/build-info.json')
      .then<Map<String, dynamic>?>((s) => jsonDecode(s) as Map<String, dynamic>)
      .catchError((Object _) => null);
  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _info,
    builder: (context, snap) {
      final info = snap.data;
      final commit = info?['commit'] as String?;
      final short = commit == null
          ? '尚未提供'
          : commit.substring(0, commit.length < 7 ? commit.length : 7);
      return SelectableText(
        info == null
            ? '版本資訊尚未提供'
            : 'App 版本 ${info['version'] ?? '尚未提供'}・來源 commit $short',
        style: SwText.small,
      );
    },
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
