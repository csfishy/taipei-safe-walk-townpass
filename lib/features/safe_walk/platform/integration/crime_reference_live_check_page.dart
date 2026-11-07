import 'package:flutter/material.dart';
import 'package:town_pass/features/safe_walk/safety_data/contract_safety_data.dart';
import 'package:town_pass/features/safe_walk/safety_data/crime_reference/crime_reference_models.dart';
import 'package:town_pass/features/safe_walk/safety_data/crime_reference/crime_reference_repository.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// Live check of the reviewed read-only crime reference query. It shows the
/// source, update dates, spatial precision, results and error states exactly
/// as returned; there is no demo data. Not wired into the Safe Walk flow (M3
/// owns that presentation); used by `crime_reference_live_check_main.dart`.
class CrimeReferenceLiveCheckPage extends StatefulWidget {
  const CrimeReferenceLiveCheckPage({super.key, required this.repository});

  final CrimeReferenceRepository repository;

  @override
  State<CrimeReferenceLiveCheckPage> createState() =>
      _CrimeReferenceLiveCheckPageState();
}

class _CrimeReferenceLiveCheckPageState
    extends State<CrimeReferenceLiveCheckPage> {
  String? _city = '臺北市';
  bool _loading = false;
  String? _error;
  CrimeReferenceResult? _result;
  int _sequence = 0;

  Future<void> _query() async {
    final sequence = ++_sequence;
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    String? error;
    CrimeReferenceResult? result;
    try {
      result = await widget.repository.query(
        mode: sw.DataMode.live,
        query: CrimeReferenceQuery(city: _city, limit: 20),
      );
    } on SafeWalkDataUnavailable {
      error = '未設定 SUPABASE_URL 與公開金鑰，無法查詢；不顯示示範資料。';
    } on CrimeReferenceQueryException catch (e) {
      error = crimeReferenceFailureText(e.failure);
    } catch (_) {
      error = '查詢失敗，請稍後重試。';
    }
    if (!mounted || sequence != _sequence) return;
    setState(() {
      _loading = false;
      _error = error;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final configured = widget.repository.isConfigured;
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('北北基犯罪參考資料（唯讀）')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!configured)
            const Text('未設定 SUPABASE_URL 與公開金鑰；查詢會回報未配置，不顯示示範資料。'),
          Row(
            children: [
              DropdownButton<String?>(
                value: _city,
                onChanged: _loading ? null : (v) => setState(() => _city = v),
                items: [
                  const DropdownMenuItem(value: null, child: Text('三市全部')),
                  for (final c in crimeReferenceCities)
                    DropdownMenuItem(value: c, child: Text(c)),
                ],
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _loading ? null : _query,
                child: const Text('查詢'),
              ),
            ],
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(_error!, key: const Key('crime-reference-error')),
            ),
          if (result != null) ..._resultView(result),
        ],
      ),
    );
  }

  List<Widget> _resultView(CrimeReferenceResult result) => [
    const SizedBox(height: 8),
    Text(
      '快照 ${result.snapshot.label}（資料截至 ${result.snapshot.asOfDate}，'
      '共 ${result.snapshot.recordCount} 筆來源紀錄）',
    ),
    Text('本次取得：${result.retrievedAt}'),
    Text(
      '符合條件 ${result.totalMatching} 筆，顯示 ${result.records.length} 筆',
      key: const Key('crime-reference-count'),
    ),
    if (result.records.isEmpty) const Text('查詢成功，沒有符合條件的紀錄。'),
    for (final r in result.records)
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(
          '${r.eventDate}｜${r.city}${r.district ?? ''}｜${r.category}',
        ),
        subtitle: Text(
          '${r.locationText}\n'
          '${crimeSpatialPrecisionText(r.spatialPrecision)}；'
          '${r.hasReferenceCoordinate ? '有參考座標（非精確案發點）' : '無座標'}\n'
          '來源：${r.source.name}',
        ),
      ),
    const Divider(),
    const Text('資料來源'),
    for (final s in result.sources)
      Text(
        '${s.name}｜${s.license}｜取得 ${s.retrievedAt}｜'
        '更新 ${s.dataUpdatedAt ?? '來源未提供'}｜${s.sourceUrl}',
      ),
    const Divider(),
    for (final line in result.limitations) Text('・$line'),
  ];
}

String crimeReferenceFailureText(CrimeReferenceFailure failure) =>
    switch (failure) {
      CrimeReferenceFailure.network => '網路連線失敗，請稍後重試。',
      CrimeReferenceFailure.timeout => '查詢逾時，請稍後重試。',
      CrimeReferenceFailure.unauthorized => '公開金鑰無權執行唯讀查詢。',
      CrimeReferenceFailure.interfaceMissing => '伺服器尚未套用唯讀查詢介面。',
      CrimeReferenceFailure.invalidArgument => '查詢條件不被伺服器接受。',
      CrimeReferenceFailure.snapshotUnavailable => '審查過的資料快照目前不可用。',
      CrimeReferenceFailure.serverUnavailable => '伺服器暫時無法回應，請稍後重試。',
      CrimeReferenceFailure.invalidResponse => '伺服器回應格式不符，已拒絕顯示。',
    };

String crimeSpatialPrecisionText(CrimeSpatialPrecision p) => switch (p) {
  CrimeSpatialPrecision.publicPlaceReference => '精度：公共場所參考點',
  CrimeSpatialPrecision.roadSegmentReference => '精度：道路參考',
  CrimeSpatialPrecision.addressRangeReference => '精度：門牌範圍參考',
  CrimeSpatialPrecision.addressReference => '精度：門牌參考',
  CrimeSpatialPrecision.districtOnly => '精度：僅行政區',
  CrimeSpatialPrecision.blurredText => '精度：模糊地點文字',
  CrimeSpatialPrecision.unresolved => '精度：無法定位',
};
