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
  SafeWalkReportStatusController get _c => widget.controller;
  bool _mapConsent = false;

  @override
  void initState() {
    super.initState();
    unawaited(_c.load());
  }

  @override
  void dispose() {
    _c.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _c,
    builder: (context, _) {
      final retry = TextButton(
        key: const Key('report-retry'),
        onPressed: () => unawaited(_c.load()),
        child: const Text('再試一次'),
      );
      return Scaffold(
        appBar: AppBar(
          title: const Text('回報狀況・資料庫現況'),
          leading: BackButton(
            onPressed: () {
              _c.cancel();
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

  List<Widget> _answered(CrimeReferenceResult r) {
    final areas = _c.evidencedAreas;
    return [
      Text(
        r.totalMatching == 0
            ? '資料庫已回應，但目前沒有任何參考紀錄（空資料）。'
            : '資料庫已回應：快照 ${r.snapshot.label}（資料截至 ${r.snapshot.asOfDate}），'
                  '共 ${r.totalMatching} 筆參考紀錄；本次取得 ${r.retrievedAt}。',
        key: const Key('report-status'),
      ),
      for (final s in r.sources)
        Text('來源：${s.name}｜${s.license}｜更新 ${s.dataUpdatedAt ?? '來源未提供'}'),
      const SizedBox(height: 12),
      const Text('有證據的警示區域'),
      if (areas.isEmpty)
        const Text(
          '目前沒有經核對地理範圍的警示區域。資料庫中的參考座標點不是範圍，不會畫成警示區域。',
          key: Key('report-no-areas'),
        )
      else ...[
        for (final a in areas)
          Text(
            '「${a.label}」：${a.evidence}',
            key: ValueKey('report-area-${a.id}'),
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
