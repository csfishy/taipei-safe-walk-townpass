import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:town_pass/features/safe_walk/navigation/coordinate_math.dart';
import 'package:town_pass/features/safe_walk/navigation/route_reference_area_check.dart';
import 'package:town_pass/features/safe_walk/platform/integration/crime_reference_live_check_page.dart';
import 'package:town_pass/features/safe_walk/platform/integration/crime_route_alert_live_check_page.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_live_loop_controller.dart';
import 'package:town_pass/features/safe_walk/safety_data/crime_reference/crime_reference_models.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// Official live route screen (map entry of the TownPass Safe Walk flow).
///
/// Layout is deliberately plain; M3 owns the final visual design. Every state
/// comes from [SafeWalkLiveLoopController]; nothing here reads GPS, calls a
/// provider or falls back to demo data on its own.
class SafeWalkLiveRoutePage extends StatefulWidget {
  const SafeWalkLiveRoutePage({
    super.key,
    required this.controller,
    required this.onBack,
    required this.onEmergency,
    this.showMap = true,
    this.savedHome,
  });

  final SafeWalkLiveLoopController controller;
  final VoidCallback onBack;
  final VoidCallback onEmergency;

  /// Tests disable OSM tiles to avoid network access.
  final bool showMap;
  final sw.Coordinates? savedHome;

  @override
  State<SafeWalkLiveRoutePage> createState() => _SafeWalkLiveRoutePageState();
}

class _SafeWalkLiveRoutePageState extends State<SafeWalkLiveRoutePage> {
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  bool _mapConsent = false;

  SafeWalkLiveLoopController get _c => widget.controller;

  void _leave(VoidCallback then) {
    _c.close();
    then();
  }

  void _setTypedDestination() {
    final lat = double.tryParse(_lat.text.trim());
    final lng = double.tryParse(_lng.text.trim());
    if (lat == null || lng == null || !isValidLatLng(lat, lng)) {
      _c.setDestination(null);
      return;
    }
    _c.setDestination(sw.Coordinates(lat: lat, lng: lng));
  }

  @override
  void dispose() {
    // Leaving by system back, SOS or exit: no work may outlive the screen.
    _c.close();
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _c,
    builder: (context, _) {
      final route = _c.route;
      final working = _c.busy || _c.stage == LiveLoopStage.assessing;
      return Scaffold(
        appBar: AppBar(
          title: const Text('安心行・真實步行路線'),
          leading: BackButton(onPressed: () => _leave(widget.onBack)),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              '定位與第三方路線查詢需分別同意。OSRM 路網只代表可步行的路，'
              '不代表安全路線；犯罪資料為歷史參考，不是即時道路風險。',
            ),
            SwitchListTile(
              key: const Key('live-consent-location'),
              contentPadding: EdgeInsets.zero,
              value: _c.locationConsent,
              onChanged: _c.setLocationConsent,
              title: const Text('同意由 TownPass 取得目前位置（只在按下按鈕時讀取一次）'),
            ),
            SwitchListTile(
              key: const Key('live-consent-routing'),
              contentPadding: EdgeInsets.zero,
              value: _c.routingConsent,
              onChanged: _c.setRoutingConsent,
              title: const Text(
                '同意將起訖座標傳送至第三方 OSRM 步行路線服務（routing.openstreetmap.de）',
              ),
            ),
            SwitchListTile(
              key: const Key('live-consent-reference'),
              contentPadding: EdgeInsets.zero,
              value: _c.referenceConsent,
              onChanged: _c.setReferenceConsent,
              title: const Text('同意將路線外框（約加 200 公尺）傳送至 Supabase 犯罪參考資料服務進行查詢'),
            ),
            FilledButton(
              key: const Key('live-locate'),
              onPressed: _c.canLocate ? () => unawaited(_c.locate()) : null,
              child: const Text('取得目前位置'),
            ),
            Text(
              _c.origin == null
                  ? '尚未取得起點。'
                  : '已取得起點（精度約 ${_c.origin!.accuracyMeters?.round()} 公尺）。',
              key: const Key('live-origin'),
            ),
            const SizedBox(height: 8),
            if (widget.savedHome != null)
              TextButton(
                key: const Key('live-use-saved-home'),
                onPressed: working
                    ? null
                    : () => _c.setDestination(widget.savedHome),
                child: const Text('使用已儲存的家作為目的地'),
              ),
            const Text('選擇目的地：在地圖上點選，或輸入座標。'),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('live-dest-lat'),
                    controller: _lat,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(labelText: '目的地緯度'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    key: const Key('live-dest-lng'),
                    controller: _lng,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(labelText: '目的地經度'),
                  ),
                ),
              ],
            ),
            TextButton(
              key: const Key('live-set-destination'),
              onPressed: working ? null : _setTypedDestination,
              child: const Text('設定目的地'),
            ),
            Text(
              _c.destination == null ? '尚未選擇目的地。' : '已選擇目的地。',
              key: const Key('live-destination'),
            ),
            if (widget.showMap)
              SwitchListTile(
                key: const Key('live-consent-map'),
                contentPadding: EdgeInsets.zero,
                value: _mapConsent,
                onChanged: (value) => setState(() => _mapConsent = value),
                title: const Text(
                  '同意載入 OpenStreetMap 地圖圖磚（tile.openstreetmap.org）',
                ),
                subtitle: const Text('會傳送目前檢視範圍，可能包含起點與目的地；不同意仍可輸入座標規劃。'),
              ),
            if (widget.showMap && _mapConsent && _c.origin != null)
              SizedBox(
                height: 280,
                child: SafeWalkLiveMap(
                  key: ValueKey(route?.requestId ?? 'origin'),
                  origin: _c.origin!.coordinates,
                  destination: _c.destination,
                  candidates: route?.routes ?? const [],
                  areas: _c.reviewedAreas,
                  onTap: working ? null : _c.setDestination,
                ),
              ),
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('live-plan'),
              onPressed: _c.canPlan ? () => unawaited(_c.planRoute()) : null,
              child: const Text('規劃真實步行路線'),
            ),
            if (working) ...[
              const LinearProgressIndicator(),
              Text(switch (_c.stage) {
                LiveLoopStage.locating => '正在取得目前位置…',
                LiveLoopStage.routing => '正在查詢 OSRM 步行路線…',
                _ => '正在查詢犯罪參考資料…',
              }),
              OutlinedButton(
                key: const Key('live-cancel'),
                onPressed: _c.cancel,
                child: const Text('取消'),
              ),
            ],
            if (_c.message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_c.message!, key: const Key('live-message')),
              ),
            if (route != null) ..._routeDetails(route),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton.icon(
              key: const Key('live-emergency'),
              style: FilledButton.styleFrom(backgroundColor: Colors.red[700]),
              onPressed: () => _leave(widget.onEmergency),
              icon: const Icon(Icons.sos_rounded),
              label: const Text('緊急求助'),
            ),
          ),
        ),
      );
    },
  );

  List<Widget> _routeDetails(sw.RouteSuccess route) {
    final alert = _c.alert;
    final checks = {
      for (final c
          in alert?.comparison.candidates ?? <RouteAreaCandidateCheck>[])
        c.candidateId: c,
    };
    return [
      for (final c in route.routes)
        Text(
          '${c.id}：約 ${c.distanceMeters.round()} 公尺'
          '${c.durationSeconds == null ? '' : '，約 ${(c.durationSeconds! / 60).ceil()} 分鐘'}'
          '${checks[c.id] == null
              ? ''
              : checks[c.id]!.crossesArea
              ? '，經過已核對參考範圍'
              : '，未經過已核對參考範圍'}'
          '（${c.provider}）',
          key: ValueKey('live-candidate-${c.id}'),
        ),
      for (final w in {
        ...route.warnings,
        for (final c in route.routes) ...c.warnings,
      })
        Text('・$w'),
      const SizedBox(height: 8),
      ...switch (_c.referenceState) {
        LiveLoopReferenceState.notRequested => const <String>[],
        LiveLoopReferenceState.notConsented => const [
          '未同意查詢犯罪參考資料；本次未查詢，也未比對。',
        ],
        LiveLoopReferenceState.loading => const ['正在查詢犯罪參考資料…'],
        LiveLoopReferenceState.timeout => const [
          '犯罪參考資料查詢逾時；未產生提示，路線維持 OSRM 原樣。',
        ],
        LiveLoopReferenceState.failed => const ['犯罪參考資料比對失敗；未產生提示。'],
        LiveLoopReferenceState.done => crimeRouteAlertLines(alert!),
      }.map((line) => Text(line, key: const Key('live-reference-line'))),
    ];
  }
}

/// Report-status screen: queries the reviewed database on every entry and
/// shows only reviewed areas with documented evidence. It sends no report.
class SafeWalkReportStatusPage extends StatefulWidget {
  const SafeWalkReportStatusPage({
    super.key,
    required this.controller,
    required this.onBack,
    this.showMap = true,
  });

  final SafeWalkReportStatusController controller;
  final VoidCallback onBack;
  final bool showMap;

  @override
  State<SafeWalkReportStatusPage> createState() =>
      _SafeWalkReportStatusPageState();
}

class _SafeWalkReportStatusPageState extends State<SafeWalkReportStatusPage> {
  // AnimatedSwitcher may keep an outgoing page alive while a new visit uses
  // the same controller. Only the latest visit may cancel its work.
  static final _currentVisits = Expando<Object>('report page visit');

  SafeWalkReportStatusController get _c => widget.controller;
  Object? _visit;
  bool _mapConsent = false;

  @override
  void initState() {
    super.initState();
    _beginVisit();
  }

  void _beginVisit() {
    final controller = _c;
    final visit = _visit = Object();
    _currentVisits[controller] = visit;
    // A previous page may still listen during its exit animation. Notify it
    // after the new page's build, never from this page's initState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          identical(widget.controller, controller) &&
          identical(_currentVisits[controller], visit)) {
        unawaited(controller.load());
      }
    });
  }

  void _endVisit(SafeWalkReportStatusController controller) {
    final visit = _visit;
    _visit = null;
    if (visit == null || !identical(_currentVisits[controller], visit)) return;
    _currentVisits[controller] = null;
    controller.cancel();
  }

  void _retry() {
    if (_visit != null && identical(_currentVisits[_c], _visit)) {
      unawaited(_c.load());
    }
  }

  @override
  void didUpdateWidget(covariant SafeWalkReportStatusPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _endVisit(oldWidget.controller);
      _beginVisit();
    }
  }

  @override
  void dispose() {
    _endVisit(_c);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _c,
    builder: (context, _) {
      final retry = TextButton(
        key: const Key('report-retry'),
        onPressed: _retry,
        child: const Text('再試一次'),
      );
      return Scaffold(
        appBar: AppBar(
          title: const Text('回報狀況・資料庫現況'),
          leading: BackButton(
            onPressed: () {
              _endVisit(_c);
              widget.onBack();
            },
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('使用者回報尚未接上真實後端；本頁只查詢資料庫現況，不送出任何回報。'),
            if (widget.showMap)
              SwitchListTile(
                value: _mapConsent,
                onChanged: (value) => setState(() => _mapConsent = value),
                title: const Text('同意向 OpenStreetMap 載入檢視範圍的圖磚'),
              ),
            const SizedBox(height: 8),
            Text(
              _statusLabel(_c.queryStatus),
              key: const Key('report-query-status'),
            ),
            const SizedBox(height: 8),
            ...switch (_c.stage) {
              ReportStatusStage.idle || ReportStatusStage.loading => [
                const LinearProgressIndicator(),
                const Text('正在查詢犯罪參考資料庫現況…'),
              ],
              ReportStatusStage.notConfigured => [
                const Text(
                  '犯罪參考資料庫未設定（SUPABASE_URL／公開金鑰），未查詢；不顯示示範資料。',
                  key: Key('report-status'),
                ),
              ],
              ReportStatusStage.failed => [
                Text(
                  '查詢失敗：${_c.failure == null ? '請稍後重試。' : crimeReferenceFailureText(_c.failure!)}',
                  key: const Key('report-status'),
                ),
                retry,
              ],
              ReportStatusStage.timeout => [
                const Text('查詢逾時，未取得資料庫現況；請稍後重試。', key: Key('report-status')),
                retry,
              ],
              ReportStatusStage.cancelled => [
                const Text('查詢已取消。', key: Key('report-status')),
                retry,
              ],
              ReportStatusStage.answered => _answered(_c.result!),
            },
            const SizedBox(height: 8),
            ...crimeReferenceLimitations.map((l) => Text('・$l')),
          ],
        ),
      );
    },
  );

  static String _statusLabel(ReportQueryStatus s) => switch (s) {
    ReportQueryStatus.loading => '查詢狀態：查詢中',
    ReportQueryStatus.ok => '查詢狀態：正常（資料庫已回應）',
    ReportQueryStatus.empty => '查詢狀態：無紀錄（資料庫已回應，但沒有任何參考紀錄）',
    ReportQueryStatus.error => '查詢狀態：錯誤（未取得資料庫現況）',
    ReportQueryStatus.stale => '查詢狀態：資料過舊或日期待確認（資料庫已回應）',
  };

  static const _scopeText = '可信範圍：僅限已核對邊界的範圍；資料庫參考座標點不是範圍，行政區統計也不是路段分數。';
  static const _limitText = '資料限制：官方公開案件的歷史參考資料，不是即時資訊；未列出的地點不代表安全。';

  List<Widget> _answered(CrimeReferenceResult r) {
    final areas = _c.evidencedAreas;
    final updated = r.snapshot.asOfDate;
    return [
      Text(
        r.totalMatching == 0
            ? '資料庫已回應，但目前沒有任何參考紀錄（空資料）。'
            : '資料庫已回應：快照 ${r.snapshot.label}（資料截至 ${r.snapshot.asOfDate}），'
                  '共 ${r.totalMatching} 筆參考紀錄；本次取得 ${r.retrievedAt}。',
        key: const Key('report-status'),
      ),
      if (_c.snapshotIsStale)
        const Text(
          '資料已超過更新期限或日期無法確認，僅供參考，請勿當作現況。',
          key: Key('report-stale-note'),
        ),
      for (final s in r.sources)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '來源：${s.name}｜${s.license}｜更新 ${s.dataUpdatedAt ?? '來源未提供'}',
              ),
              Text('更新日期：快照資料截至 $updated'),
              const Text(_scopeText),
              const Text(_limitText),
            ],
          ),
        ),
      const SizedBox(height: 12),
      const Text('有證據的警示區域'),
      if (areas.isEmpty)
        Text(
          _c.reviewedAreas.isEmpty
              ? '目前尚無任何經審查的警示區域（本版本沒有已核對的地理範圍）。這只表示尚未審查，不代表這些地方沒有風險或安全。資料庫中的參考座標點不是範圍，不會畫成警示區域。'
              : '目前沒有帶地理範圍證據的警示區域。這不代表沒有風險或安全。',
          key: const Key('report-no-areas'),
        )
      else ...[
        for (final a in areas)
          Padding(
            key: ValueKey('report-area-${a.id}'),
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('「${a.label}」邊界來源／證據：${a.evidence}'),
                const Text('邊界資料更新日期：未提供；犯罪資料快照日期不代表邊界更新日。'),
                Text(
                  '犯罪參考資料包含：${r.sources.map((s) => s.name).join('、')}；不代表這些來源認定此範圍為危險區域。',
                ),
                Text('可信範圍：僅此已核對邊界內（${a.label}）；邊界外不作任何判斷。'),
                Text('犯罪參考資料快照截至 $updated'),
                const Text(_limitText),
              ],
            ),
          ),
        if (widget.showMap && _mapConsent)
          SizedBox(
            height: 240,
            child: SafeWalkLiveMap(areas: areas, candidates: const []),
          ),
      ],
    ];
  }
}

/// OSM map that draws the provider geometry unchanged, reviewed areas, the
/// origin and the chosen destination. No demo geometry is ever drawn.
class SafeWalkLiveMap extends StatelessWidget {
  const SafeWalkLiveMap({
    super.key,
    this.origin,
    this.destination,
    required this.candidates,
    required this.areas,
    this.onTap,
  });

  final sw.Coordinates? origin;
  final sw.Coordinates? destination;
  final List<sw.RouteCandidate> candidates;
  final List<RouteReferenceArea> areas;
  final ValueChanged<sw.Coordinates>? onTap;

  @override
  Widget build(BuildContext context) {
    LatLng at(sw.GeoJsonCoordinate c) => LatLng(c.latitude, c.longitude);
    LatLng ll(sw.Coordinates c) => LatLng(c.lat, c.lng);
    final fitPoints = [
      for (final c in candidates) ...c.geometry.coordinates.map(at),
      if (candidates.isEmpty)
        for (final a in areas) ...a.ring.map(at),
    ];
    final tap = onTap;
    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: origin == null ? const LatLng(0, 0) : ll(origin!),
            initialZoom: 16,
            initialCameraFit: fitPoints.length < 2
                ? null
                : CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints(fitPoints),
                    padding: const EdgeInsets.all(24),
                    maxZoom: 18,
                  ),
            onTap: tap == null
                ? null
                : (_, p) =>
                      tap(sw.Coordinates(lat: p.latitude, lng: p.longitude)),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'town_pass',
              maxNativeZoom: 19,
            ),
            PolygonLayer(
              polygons: [
                for (final a in areas)
                  Polygon(
                    points: a.ring.map(at).toList(),
                    color: Colors.orange.withValues(alpha: .2),
                    borderColor: Colors.orange,
                    borderStrokeWidth: 2,
                  ),
              ],
            ),
            PolylineLayer(
              polylines: [
                for (final (i, c) in candidates.indexed)
                  Polyline(
                    points: c.geometry.coordinates.map(at).toList(),
                    strokeWidth: i == 0 ? 5 : 3,
                    color: i == 0 ? Colors.blue : Colors.blueGrey,
                  ),
              ],
            ),
            MarkerLayer(
              markers: [
                if (origin != null)
                  Marker(
                    point: ll(origin!),
                    child: const Icon(Icons.my_location, color: Colors.blue),
                  ),
                if (destination != null)
                  Marker(
                    point: ll(destination!),
                    child: const Icon(Icons.place, color: Colors.red),
                  ),
              ],
            ),
          ],
        ),
        Positioned(
          right: 4,
          bottom: 2,
          child: ColoredBox(
            color: Colors.white70,
            child: TextButton(
              onPressed: () async {
                try {
                  final opened = await launchUrl(
                    Uri.parse('https://www.openstreetmap.org/copyright'),
                    mode: LaunchMode.externalApplication,
                  );
                  if (opened) return;
                } catch (_) {
                  // Display a fixed public URL when the platform cannot open it.
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        '請瀏覽 https://www.openstreetmap.org/copyright 查看地圖授權。',
                      ),
                    ),
                  );
                }
              },
              child: const Text(
                '© OpenStreetMap contributors',
                style: TextStyle(fontSize: 10),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
