import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:town_pass/features/safe_walk/navigation/coordinate_math.dart';
import 'package:town_pass/features/safe_walk/navigation/route_reference_area_check.dart';
import 'package:town_pass/features/safe_walk/navigation/route_service.dart';
import 'package:town_pass/features/safe_walk/platform/integration/crime_reference_live_check_page.dart';
import 'package:town_pass/features/safe_walk/platform/integration/crime_route_alert_service.dart';
import 'package:town_pass/features/safe_walk/platform/platform_service.dart';
import 'package:town_pass/features/safe_walk/safety_data/crime_reference/crime_reference_models.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// In-app check of P0-2: real GPS origin -> real OSRM walking candidates ->
/// reviewed crime reference query -> route notice with its limits.
///
/// Live only. There is no demo route, no demo record and no straight-line
/// fallback; every unavailable state is shown as such. Candidate geometry is
/// drawn exactly as the provider returned it. Not wired into the mock Safe
/// Walk flow; used by `crime_route_alert_live_check_main.dart`.
class CrimeRouteAlertLiveCheckPage extends StatefulWidget {
  const CrimeRouteAlertLiveCheckPage({
    super.key,
    required this.platform,
    required this.createRouteService,
    required this.alertService,
    this.showMap = true,
    this.clock,
  });

  final PlatformService platform;

  /// Builds the live route service; `hasConsent` must be read on every call.
  final RouteService Function(bool Function() hasConsent) createRouteService;
  final CrimeRouteAlertService alertService;

  /// Tests disable OSM tiles to avoid network access.
  final bool showMap;
  final DateTime Function()? clock;

  @override
  State<CrimeRouteAlertLiveCheckPage> createState() =>
      _CrimeRouteAlertLiveCheckPageState();
}

class _CrimeRouteAlertLiveCheckPageState
    extends State<CrimeRouteAlertLiveCheckPage>
    with WidgetsBindingObserver {
  late final RouteService _routes = widget.createRouteService(
    () => _routingConsent && _foreground && mounted,
  );
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  bool _routingConsent = false;
  bool _referenceConsent = false;
  bool _busy = false;
  bool _foreground = true;
  sw.Position? _origin;
  String? _message;
  sw.RouteSuccess? _route;
  CrimeRouteAlert? _alert;
  int _sequence = 0;
  _Cancellation? _request;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _foreground = state == AppLifecycleState.resumed;
      if (!_foreground) {
        final hadWork = _busy || _origin != null || _route != null;
        _invalidate();
        _origin = null;
        if (hadWork) _message = '已停止定位與比對；回到畫面後請重新取得目前位置。';
      }
    });
  }

  void _finishCancelled(int sequence) {
    if (!mounted || sequence != _sequence) return;
    setState(() {
      _invalidate();
      _message = '作業已取消，請重試。';
    });
  }

  void _invalidate() {
    _sequence++;
    _request?.cancel();
    _request = null;
    _route = null;
    _alert = null;
    _busy = false;
  }

  Future<void> _locate() async {
    if (!_foreground) return;
    setState(() {
      _invalidate();
      _origin = null;
      _message = null;
      _busy = true;
    });
    final sequence = _sequence;
    final request = _request = _Cancellation();
    sw.LocationResult result;
    try {
      result = await widget.platform.getCurrentPosition(
        mode: sw.DataMode.live,
        userInitiated: true,
        cancellation: request,
      );
    } on SafeWalkCancelledException {
      _finishCancelled(sequence);
      return;
    } catch (_) {
      result = sw.LocationFailure(
        status: sw.LocationFailureStatus.unavailable,
        message: '未能取得位置。',
      );
    }
    if (!mounted || sequence != _sequence) return;
    setState(() {
      _busy = false;
      _request = null;
      switch (result) {
        case sw.LocationSuccess(:final position):
          _origin = position;
          _message = null;
        case sw.LocationFailure(:final message):
          _message = message;
      }
    });
  }

  sw.Coordinates? _destination() {
    final lat = double.tryParse(_lat.text.trim());
    final lng = double.tryParse(_lng.text.trim());
    if (lat == null || lng == null || !isValidLatLng(lat, lng)) return null;
    return sw.Coordinates(lat: lat, lng: lng);
  }

  Future<void> _plan() async {
    final origin = _origin;
    final destination = _destination();
    if (!_foreground ||
        origin == null ||
        destination == null ||
        !_routingConsent) {
      return;
    }
    setState(() {
      _invalidate();
      _message = null;
      _busy = true;
    });
    final sequence = _sequence;
    final request = _request = _Cancellation();
    final sw.RouteResult routeResult;
    try {
      routeResult = await _routes.planRoute(
        sw.RouteRequest(
          requestId: 'p0-2-route-$sequence',
          mode: sw.DataMode.live,
          origin: origin,
          destination: destination,
          departAt: _now().toUtc().toIso8601String(),
          preference: sw.RouteKind.direct,
          maxExtraDistanceMeters: 500,
          assistancePointIds: const [],
        ),
        cancellation: request,
      );
    } on SafeWalkCancelledException {
      _finishCancelled(sequence);
      return;
    } catch (_) {
      if (!mounted || sequence != _sequence) return;
      setState(() {
        _busy = false;
        _request = null;
        _message = '步行路線規劃失敗，請重試；本次未查詢犯罪參考資料。';
      });
      return;
    }
    if (!mounted || sequence != _sequence) return;
    if (routeResult is! sw.RouteSuccess) {
      setState(() {
        _busy = false;
        _request = null;
        _message = (routeResult as sw.RouteFailure).reason;
      });
      return;
    }
    final route = routeResult;
    setState(() => _route = route);
    if (!_referenceConsent) {
      setState(() {
        _busy = false;
        _request = null;
        _message = '未同意以路線範圍查詢犯罪參考資料；本次未比對。';
      });
      return;
    }
    CrimeRouteAlert? alert;
    String? error;
    try {
      alert = await widget.alertService.assess(
        route,
        cancellation: request,
      );
    } on SafeWalkCancelledException {
      _finishCancelled(sequence);
      return;
    } catch (_) {
      error = '犯罪參考資料比對失敗；未產生提示。';
    }
    if (!mounted || sequence != _sequence) return;
    setState(() {
      _busy = false;
      _request = null;
      _alert = alert;
      _message = error;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _request?.cancel();
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final route = _route;
    final alert = _alert;
    final canPlan =
        _foreground &&
        !_busy &&
        _origin != null &&
        _routingConsent &&
        _destination() != null;
    return Scaffold(
      appBar: AppBar(title: const Text('步行路線與犯罪參考資料比對')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '真實定位與 OSRM 步行路線；犯罪資料為歷史參考，不是即時道路風險，'
            '比對結果不代表路線安全。',
          ),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('crime-route-locate'),
            onPressed: _busy || !_foreground ? null : _locate,
            child: const Text('取得目前位置'),
          ),
          Text(
            _origin == null
                ? '尚未取得起點。'
                : '已取得起點（精度約 '
                      '${_origin!.accuracyMeters?.round() ?? '未知'} 公尺）。',
            key: const Key('crime-route-origin'),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('crime-route-dest-lat'),
                  controller: _lat,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(labelText: '目的地緯度'),
                  onChanged: (_) => setState(_invalidate),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  key: const Key('crime-route-dest-lng'),
                  controller: _lng,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(labelText: '目的地經度'),
                  onChanged: (_) => setState(_invalidate),
                ),
              ),
            ],
          ),
          CheckboxListTile(
            key: const Key('crime-route-routing-consent'),
            contentPadding: EdgeInsets.zero,
            value: _routingConsent,
            onChanged: (v) => setState(() {
              _invalidate();
              _routingConsent = v ?? false;
            }),
            title: const Text('同意將起訖座標傳送至第三方 OSRM 步行路線服務'),
          ),
          CheckboxListTile(
            key: const Key('crime-route-reference-consent'),
            contentPadding: EdgeInsets.zero,
            value: _referenceConsent,
            onChanged: (v) => setState(() {
              _invalidate();
              _referenceConsent = v ?? false;
            }),
            title: const Text('同意以路線外框（約加 200 公尺）查詢犯罪參考資料'),
          ),
          FilledButton(
            key: const Key('crime-route-plan'),
            onPressed: canPlan ? _plan : null,
            child: const Text('規劃步行路線並比對'),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(_message!, key: const Key('crime-route-message')),
            ),
          if (route != null) ..._routeView(route, alert),
        ],
      ),
    );
  }

  List<Widget> _routeView(sw.RouteSuccess route, CrimeRouteAlert? alert) {
    final candidates = route.routes;
    final checks = {
      for (final c
          in alert?.comparison.candidates ?? <RouteAreaCandidateCheck>[])
        c.candidateId: c,
    };
    return [
      if (widget.showMap)
        SizedBox(
          height: 260,
          child: _RouteMap(
            candidates: candidates,
            areas: alert?.comparison.areas ?? const [],
          ),
        ),
      const SizedBox(height: 8),
      for (final c in candidates)
        Text(
          '${c.id}：約 ${c.distanceMeters.round()} 公尺'
          '${checks[c.id] == null
              ? ''
              : checks[c.id]!.crossesArea
              ? '，經過已核對參考範圍'
              : '，未經過已核對參考範圍'}'
          '（${c.provider}）',
        ),
      for (final w in {for (final c in candidates) ...c.warnings}) Text('・$w'),
      if (alert != null) ...crimeRouteAlertLines(alert).map(Text.new),
    ];
  }
}

/// User-facing lines for [alert]. Never claims a route is safe or avoids
/// danger; always keeps the reference data limits.
List<String> crimeRouteAlertLines(CrimeRouteAlert alert) {
  final comparison = alert.comparison;
  final lines = <String>[
    switch (comparison.status) {
      RouteAreaComparisonStatus.noReliableArea =>
        '沒有經核對的可靠地理範圍可與路線比對，未做避開判斷；'
            '路線維持 OSRM 原樣，這不代表路線安全。',
      RouteAreaComparisonStatus.noCandidateCrosses =>
        '候選路線未經過已核對的參考範圍；這只是與已知範圍的幾何比對，不代表路線安全。',
      RouteAreaComparisonStatus.noAlternativeRoute =>
        '所有候選路線都經過已核對的參考範圍，目前沒有可替代的真實路線；'
            '不會改寫路線來假裝避開。',
      RouteAreaComparisonStatus.alternativeAvailable =>
        '有候選路線經過已核對的參考範圍，另有未經過的真實替代路線可自行選擇；'
            '兩者都不代表安全。',
    },
  ];
  for (final area in comparison.areas) {
    lines.add('參考範圍「${area.label}」：${area.evidence}');
  }
  switch (alert.referenceOutcome) {
    case CrimeRouteReferenceOutcome.answered:
      final g = alert.geography!;
      final r = alert.reference!;
      lines.add(
        '路線外框內有 ${g.totalMatching} 筆犯罪參考紀錄；'
        '這些只是地址／捷運出入口等參考座標點，不是精確案發點也不是範圍，'
        '因此不用於路線比對。',
      );
      lines.add(
        '資料快照 ${r.snapshot.label}（資料截至 ${r.snapshot.asOfDate}），'
        '本次取得 ${r.retrievedAt}',
      );
      for (final s in r.sources) {
        lines.add('來源：${s.name}｜${s.license}｜更新 ${s.dataUpdatedAt ?? '來源未提供'}');
      }
    case CrimeRouteReferenceOutcome.notConfigured:
      lines.add('犯罪參考資料未設定（SUPABASE_URL／公開金鑰），未查詢；不顯示示範資料。');
    case CrimeRouteReferenceOutcome.failed:
      lines.add('犯罪參考資料查詢失敗：${crimeReferenceFailureText(alert.failure!)}');
    case CrimeRouteReferenceOutcome.routeExtentTooLarge:
      lines.add('路線範圍超過查詢上限，未查詢犯罪參考資料。');
  }
  lines.addAll(crimeReferenceLimitations.map((l) => '・$l'));
  return lines;
}

class _RouteMap extends StatelessWidget {
  const _RouteMap({required this.candidates, required this.areas});

  final List<sw.RouteCandidate> candidates;
  final List<RouteReferenceArea> areas;

  @override
  Widget build(BuildContext context) {
    LatLng at(sw.GeoJsonCoordinate c) => LatLng(c.latitude, c.longitude);
    final points = [
      for (final c in candidates) ...c.geometry.coordinates.map(at),
    ];
    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCameraFit: CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(points),
              padding: const EdgeInsets.all(24),
              maxZoom: 18,
            ),
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
          ],
        ),
        const Positioned(
          right: 4,
          bottom: 2,
          child: ColoredBox(
            color: Colors.white70,
            child: Text(
              '© OpenStreetMap contributors',
              style: TextStyle(fontSize: 10),
            ),
          ),
        ),
      ],
    );
  }
}

final class _Cancellation implements SafeWalkCancellation {
  final _cancelled = Completer<void>();

  @override
  bool get isCancelled => _cancelled.isCompleted;

  @override
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }
}
