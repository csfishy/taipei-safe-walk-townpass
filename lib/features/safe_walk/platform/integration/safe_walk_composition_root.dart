import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, rootBundle;
import 'package:town_pass/features/safe_walk/navigation/avoid_area.dart';
import 'package:town_pass/features/safe_walk/platform/integration/crime_reference_wiring.dart';
import 'package:town_pass/features/safe_walk/platform/integration/map_report_wiring.dart';
import 'package:town_pass/features/safe_walk/platform/supabase/safe_walk_supabase_config.dart';
import 'package:town_pass/features/safe_walk/platform/supabase/web_rpc_post.dart';
import 'package:town_pass/features/safe_walk/safety_data/crime_reference/crime_reference_models.dart';
import 'package:town_pass/features/safe_walk/safety_data/crime_reference/crime_reference_repository.dart';
import 'package:town_pass/features/safe_walk/safety_data/map_reports/map_report_repository.dart';
import 'package:town_pass/features/safe_walk/navigation/default_json_transport.dart';
import 'package:town_pass/features/safe_walk/navigation/default_route_service.dart';
import 'package:town_pass/features/safe_walk/navigation/json_transport.dart';
import 'package:town_pass/features/safe_walk/navigation/nearby_help.dart';
import 'package:town_pass/features/safe_walk/navigation/nearest_store_planner.dart';
import 'package:town_pass/features/safe_walk/navigation/osm_help_point_snapshot.dart';
import 'package:town_pass/features/safe_walk/navigation/osrm_walking_route_provider.dart';
import 'package:town_pass/features/safe_walk/navigation/route_follower.dart';
import 'package:town_pass/features/safe_walk/navigation/route_service.dart';
import 'package:town_pass/features/safe_walk/navigation/route_reference_area_check.dart';
import 'package:town_pass/features/safe_walk/navigation/valhalla_avoiding_route_planner.dart';
import 'package:town_pass/features/safe_walk/platform/integration/avoiding_route_service.dart';
import 'package:town_pass/features/safe_walk/platform/home_location/home_location_service.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_route_speaker.dart';
import 'package:town_pass/features/safe_walk/platform/integration/tts_safe_walk_speaker.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_navigation_controller.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_live_loop_controller.dart';
import 'package:town_pass/features/safe_walk/platform/integration/nearby_helper_controller.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_live_loop_pages.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_alert_transport.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_emergency_service.dart';
import 'package:town_pass/features/safe_walk/platform/platform_service.dart';
import 'package:town_pass/features/safe_walk/platform/device_heading.dart';
import 'package:town_pass/features/safe_walk/platform/position_watch.dart';
import 'package:town_pass/features/safe_walk/platform/townpass_platform_adapter.dart';
import 'package:town_pass/features/safe_walk/presentation/mock/safe_walk_demo_data.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_flow.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_nearby_broadcast.dart';
import 'package:town_pass/features/safe_walk/safety_data/contract_safety_data.dart';
import 'package:town_pass/features/safe_walk/safety_data/safety_data_service.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/semantics.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/safe_walk_navigation_scope.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// M1's composition boundary for independently consented routing and reference
/// queries. The product's 50 m buffer does not describe an official crime area.
class SafeWalkCompositionRoot extends StatefulWidget {
  const SafeWalkCompositionRoot({
    super.key,
    this.platform,
    this.safetyData,
    this.speaker,
    this.routeService,
    this.routeTransport,
    this.homeLocationStore,
    this.crimeRepository,
    this.mapReportRepository,
    this.crimeServiceHost,
    this.onExit,
    this.liveRoutes = false,
    this.watchPosition,
    this.watchHeading,
    this.reviewedAreas = const [],
    this.showLiveMap = true,
    this.findStores,
    this.consentGranted = false,
    this.nearbyAlerts,
    this.allowEmergencyDialer = false,
    this.onOpenOfficialReport,
  });

  /// Official entry (2026-11-08 team decision): route and crime queries run
  /// without a consent dialog and the query settings are hidden. Tests keep
  /// the consent flow by leaving this false.
  final bool consentGranted;

  /// Backend for the emergency page's "notify people nearby" button. Defaults
  /// to the unavailable transport, so the button only shows why it cannot be
  /// used. Supplying an authenticated transport (a verified session) is the
  /// Level C step that turns the feature on; nothing else here does.
  final NearbyAlertTransport? nearbyAlerts;

  /// When true (and live), choosing 110 or 119 on the emergency page opens the
  /// phone's dialer with the number filled in. Only the person's own tap does
  /// this and they still press call; nothing is dialled, reported or
  /// dispatched by the app. Defaults to false so tests and previews never reach
  /// a phone; the official entry turns it on.
  final bool allowEmergencyDialer;

  /// Opens TownPass's own online reporting service from the emergency page.
  /// Null hides the button. Opening it is not a report and not acceptance.
  final VoidCallback? onOpenOfficialReport;

  /// Nearby help points; defaults to the bundled OpenStreetMap snapshot of
  /// convenience stores and police (opening hours read at lookup time).
  /// Tests inject a fake so nothing leaves the device.
  final NearbyPointFinder? findStores;

  /// Continuous positions while the map is open; defaults to the device GPS.
  final Stream<sw.Position> Function()? watchPosition;

  /// Phone heading (degrees from north) while following; defaults to the
  /// device compass. Tests pass an empty stream.
  final Stream<double> Function()? watchHeading;

  /// Real walking routes: opening the map reads the device position (after the
  /// user agrees to share it with the routing service). Unconfigured points
  /// and emergency handoffs remain unavailable; they never use Mock data.
  final bool liveRoutes;

  /// Independently reviewed boundaries for the reference-information page.
  final List<RouteReferenceArea> reviewedAreas;

  /// Tests can disable map tiles without changing route/reference consent checks.
  final bool showLiveMap;

  final PlatformService? platform;
  final SafetyDataRepository? safetyData;

  /// Injectable route service; mode follows the selected composition.
  final RouteService? routeService;

  /// Optional transport for provider verification without public requests.
  final JsonTransport? routeTransport;

  /// Ownership transfers to this route, which disposes the speaker once.
  /// Defaults to on-device TTS; it stays text-only until a voice is confirmed.
  final SafeWalkRouteSpeaker? speaker;

  /// 「家」的裝置儲存；預設用 SharedPreferences，測試可注入 fake。
  final HomeLocationStore? homeLocationStore;

  /// Optional read-only dependency for isolated integration verification.
  final CrimeReferenceRepository? crimeRepository;

  /// Public map reports are persisted separately from historical crime data.
  /// Tests inject a repository transport without contacting external services.
  final MapReportRepository? mapReportRepository;

  /// Public recipient hostname shown in the query consent. Never a credential.
  final String? crimeServiceHost;
  final VoidCallback? onExit;

  @override
  State<SafeWalkCompositionRoot> createState() =>
      _SafeWalkCompositionRootState();
}

class _SafeWalkCompositionRootState extends State<SafeWalkCompositionRoot>
    with WidgetsBindingObserver {
  final _lifetime = _RouteCancellation();
  _RouteCancellation? _pointsRequest;
  _RouteCancellation? _locationRequest;
  late final PlatformService _platform;
  late final NearbyEmergencyService _nearbyService;
  NearbyHelperController? _helper;
  SafetyDataRepository? _safetyData;
  late final SafeWalkRouteSpeaker _speaker;
  late final SafeWalkNavigationController _navigation;
  SafeWalkReportStatusController? _report;
  int _routeSequence = 0;
  bool _navigationActive = false;
  bool _foreground = true;
  _RouteCancellation? _operation;
  int _boundaryRevision = 0;
  List<sw.AssistancePoint> _points = const [];

  /// Live: up to three open convenience stores with their avoiding routes,
  /// safest then fastest first. Only after the walker asks for them.
  List<NearbyHelpOption> _nearby = const [];
  bool _nearbyLoading = false;
  String? _nearbyError;
  _RouteCancellation? _nearbyOperation;

  /// Read once, on the first nearby lookup.
  late final Future<OsmHelpPointSnapshot> _snapshot = rootBundle
      .loadString('assets/safe_walk/osm_help_points_taipei.json')
      .then(OsmHelpPointSnapshot.parse);

  Future<List<sw.AssistancePoint>> _snapshotNear(
    sw.Coordinates origin, {
    SafeWalkCancellation? cancellation,
  }) async => (await _snapshot).near(origin);

  /// Its own instance so store routes and the destination route do not
  /// cancel each other (each service keeps only its newest call).
  late final RouteService _storeRoutes;
  bool _pointsLoading = true;
  String? _pointsError;
  late final HomeLocationService _homeService;
  sw.Coordinates? _home;
  int _homeRevision = 0;

  Future<void> _loadHome() async {
    final revision = _homeRevision;
    final home = await _homeService.load();
    if (!mounted || home == null || revision != _homeRevision) return;
    setState(() => _home = sw.Coordinates(lat: home.lat, lng: home.lng));
  }

  /// 使用者按儲存／移除時才寫入裝置；失敗會往上丟，由設定畫面顯示錯誤。
  Future<void> _changeHome(sw.Coordinates? home) async {
    _invalidateOperation();
    ++_homeRevision;
    if (home == null) {
      await _homeService.clear();
    } else {
      await _homeService.save(home.lat, home.lng);
    }
    if (mounted) setState(() => _home = home);
  }

  /// Unresolved reports to route around (50 m circles), sent by the map.
  List<AvoidArea> _areas = const [];

  late final MapReportWiring _mapReports = widget.mapReportRepository == null
      ? MapReportWiring.fromEnvironment()
      : MapReportWiring(widget.mapReportRepository!);
  final _mapReportRequests = <_RouteCancellation>{};

  Future<T> _mapReportOperation<T>(
    Future<T> Function(SafeWalkCancellation cancellation) action,
  ) async {
    if (!mounted || !_foreground || _lifetime.isCancelled) {
      throw const SafeWalkCancelledException();
    }
    final operation = _RouteCancellation();
    _mapReportRequests.add(operation);
    try {
      final result = await action(operation);
      operation.throwIfCancelled();
      return result;
    } finally {
      _mapReportRequests.remove(operation);
    }
  }

  void _cancelMapReports() {
    for (final operation in _mapReportRequests) {
      operation.cancel();
    }
    _mapReportRequests.clear();
  }

  Future<Anomaly> _saveMapReport(Anomaly draft) => _mapReportOperation(
    (cancellation) => _mapReports.save(draft, cancellation: cancellation),
  );

  Future<List<Anomaly>> _loadMapReports() => _mapReportOperation(
    (cancellation) => _mapReports.load(cancellation: cancellation),
  );

  /// Product-defined buffers around reference positions; not incident bounds.
  late final CrimeReferenceRepository _crime =
      widget.crimeRepository ?? _crimeRepository();

  /// Local web preview only (`--dart-define=SAFE_WALK_WEB_ROUTES=true`).
  static const _webPreview = bool.fromEnvironment('SAFE_WALK_WEB_ROUTES');

  /// Phones use M1's dart:io client. The local web preview posts the same
  /// reviewed read-only RPC through browser fetch; default web stays off.
  static CrimeReferenceRepository _crimeRepository() {
    if (!kIsWeb) {
      return CrimeReferenceWiring.fromEnvironment().repository;
    }
    if (!_webPreview) return CrimeReferenceRepository(transport: null);
    final SafeWalkSupabaseConfig config;
    try {
      config = SafeWalkSupabaseConfig.fromEnvironment();
    } on SupabaseConfigurationException {
      return CrimeReferenceRepository(transport: null);
    }
    return CrimeReferenceRepository(
      transport: (arguments, {cancellation}) async {
        final (status, body) = await webRpcPost(
          config.url.resolve('/rest/v1/rpc/$crimeReferenceRpcFunction'),
          {
            ...config.requestHeaders,
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          jsonEncode(arguments),
          cancellation: cancellation,
        );
        return CrimeReferenceHttpResponse(status, body);
      },
    );
  }

  List<AvoidArea> _crimeAreas = const [];
  List<CrimeSpot> _crimeSpots = const [];
  bool _hasCrimeConsent = false;
  bool _crimeConsentAsked = false;
  Future<bool?>? _routingConsentPrompt;
  Future<bool?>? _crimeConsentPrompt;
  String _crimeQueryStatus = '犯罪參考資料：尚未同意查詢。';

  String get _crimeServiceHost {
    final host =
        widget.crimeServiceHost ??
        Uri.tryParse(const String.fromEnvironment('SUPABASE_URL'))?.host;
    return host == null || host.isEmpty ? '已設定的 Supabase 犯罪資料服務' : host;
  }

  bool _isCurrent(_RouteCancellation operation) =>
      mounted &&
      _foreground &&
      _navigationActive &&
      !_lifetime.isCancelled &&
      identical(_operation, operation) &&
      !operation.isCancelled;

  Future<void> _loadCrime(
    sw.Coordinates a,
    sw.Coordinates b,
    _RouteCancellation operation, {
    bool Function()? current,
  }) async {
    bool isCurrent() => current?.call() ?? _isCurrent(operation);
    if (!isCurrent() || !_hasCrimeConsent) return;
    if (!_crime.isConfigured) {
      setState(() => _crimeQueryStatus = '犯罪參考資料尚未配置；本次路線未套用犯罪參考避讓。');
      return;
    }
    const m = 0.006; // ~600 m margin around the start/destination box
    setState(() => _crimeQueryStatus = '犯罪參考資料查詢中…');
    try {
      // Consent and operation state are checked immediately before the effect.
      if (!isCurrent() || !_hasCrimeConsent) return;
      final result = await _crime.query(
        mode: sw.DataMode.live,
        query: CrimeReferenceQuery(
          bounds: CrimeReferenceBounds(
            minLat: (a.lat < b.lat ? a.lat : b.lat) - m,
            minLng: (a.lng < b.lng ? a.lng : b.lng) - m,
            maxLat: (a.lat > b.lat ? a.lat : b.lat) + m,
            maxLng: (a.lng > b.lng ? a.lng : b.lng) + m,
          ),
          limit: crimeReferenceMaxLimit,
        ),
        cancellation: operation,
      );
      final located = [
        for (final r in result.records)
          if (r.latitude != null && r.longitude != null) r,
      ];
      if (!isCurrent() || !_hasCrimeConsent) return;
      setState(() {
        _crimeSpots = [
          for (final r in located)
            (
              id: 'crime-${r.source.sourceKey}-${r.sourceRecordId}',
              at: LatLng(r.latitude!, r.longitude!),
              label:
                  '${r.category}・${r.eventDate}・${r.locationText}\n'
                  '來源：${r.source.name}（${r.source.sourceUrl}）\n'
                  '位置精度：${_precisionLabel(r.spatialPrecision)}；'
                  '更新：${r.source.dataUpdatedAt ?? '來源未提供'}\n'
                  '50 公尺為產品避讓緩衝，並非精確案發範圍。',
            ),
        ];
        _crimeAreas = [
          for (final r in located)
            AvoidArea(
              id: 'crime-${r.source.sourceKey}-${r.sourceRecordId}',
              center: sw.Coordinates(lat: r.latitude!, lng: r.longitude!),
              radiusMeters: AvoidArea.reportRadiusMeters,
              source: 'crime',
            ),
        ];
        _crimeQueryStatus = located.isEmpty
            ? '查詢成功，沒有可定位的犯罪參考紀錄；不代表沿途安全。'
            : '已取得 ${located.length} 筆歷史參考位置，套用產品設定的 50 公尺避讓緩衝。'
                  '${result.totalMatching > result.records.length ? '僅顯示本頁資料，尚有其他紀錄。' : ''}'
                  '參考位置非精確案發點，不代表即時風險。';
      });
    } on SafeWalkCancelledException {
      return;
    } on CrimeReferenceQueryException catch (error) {
      if (!isCurrent() || !_hasCrimeConsent) return;
      setState(
        () => _crimeQueryStatus =
            '犯罪參考資料查詢失敗：${_crimeFailureMessage(error.failure)}'
            '本次路線未套用犯罪參考避讓。',
      );
    } on ArgumentError {
      if (!isCurrent() || !_hasCrimeConsent) return;
      setState(
        () => _crimeQueryStatus =
            '犯罪參考資料查詢失敗：查詢範圍過大或條件不適用，請縮短行程後重新規劃。'
            '本次路線未套用犯罪參考避讓。',
      );
    } catch (_) {
      if (!isCurrent() || !_hasCrimeConsent) return;
      setState(
        () => _crimeQueryStatus = '犯罪參考資料查詢失敗；請重新規劃路線以重試。本次路線未套用犯罪參考避讓。',
      );
    }
  }

  static String _crimeFailureMessage(
    CrimeReferenceFailure failure,
  ) => switch (failure) {
    CrimeReferenceFailure.network => '網路連線失敗，請確認網路後重新規劃路線。',
    CrimeReferenceFailure.timeout => '查詢逾時，請稍後重新規劃路線。',
    CrimeReferenceFailure.unauthorized => '資料服務拒絕存取，請更新 App；若仍無法使用，請向服務維護者回報。',
    CrimeReferenceFailure.interfaceMissing => '資料查詢服務尚未開放，請稍後再試或向服務維護者回報。',
    CrimeReferenceFailure.invalidArgument => '查詢條件不適用，請調整起點與目的地後重新規劃。',
    CrimeReferenceFailure.snapshotUnavailable => '犯罪參考資料暫時無法取得，請稍後再試或向服務維護者回報。',
    CrimeReferenceFailure.serverUnavailable => '資料服務忙碌或暫時中斷，請稍後重新規劃路線。',
    CrimeReferenceFailure.invalidResponse =>
      '資料內容無法驗證，已停止顯示；請更新 App 或向服務維護者回報。',
  };

  String _precisionLabel(CrimeSpatialPrecision precision) =>
      switch (precision) {
        CrimeSpatialPrecision.publicPlaceReference => '公共場所參考位置',
        CrimeSpatialPrecision.roadSegmentReference => '路段參考位置',
        CrimeSpatialPrecision.addressRangeReference => '門牌範圍參考位置',
        CrimeSpatialPrecision.addressReference => '門牌參考位置',
        CrimeSpatialPrecision.districtOnly => '僅行政區',
        CrimeSpatialPrecision.blurredText => '模糊地點',
        CrimeSpatialPrecision.unresolved => '未解析',
      };

  /// Start point the user picked on the map; null = device GPS.
  sw.Coordinates? _manualOrigin;

  // Route following: one follower per option; re-plan only when off all of them.
  sw.Coordinates? _destination;
  sw.RouteResult? _followed;
  sw.RouteSuccess? _guidancePreview;
  List<RouteFollower> _followers = const [];
  StreamSubscription<sw.Position>? _watch;
  sw.Position? _livePosition;
  StreamSubscription<double>? _headingSub;

  /// Which way the phone points (degrees from north) for the map arrow.
  double? _heading;
  DateTime? _lastReplan;
  static const _replanGap = Duration(seconds: 15);

  @override
  void initState() {
    super.initState();
    _homeService = HomeLocationService(
      widget.homeLocationStore ?? SharedPreferencesHomeLocationStore(),
    );
    unawaited(_loadHome());
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    if (!_crime.isConfigured) {
      _crimeQueryStatus = '犯罪參考資料尚未配置；路線未套用犯罪參考避讓。';
    }
    _platform =
        widget.platform ??
        TownPassPlatformAdapter(
          mockPosition: widget.liveRoutes
              ? null
              : sw.Position.fromJson({
                  'schemaVersion': '1.0.0',
                  'coordinates': {
                    'lat': DemoGeo.start.lat,
                    'lng': DemoGeo.start.lng,
                  },
                  'source': 'mock',
                  'accuracyMeters': null,
                  'observedAt': null,
                }),
        );
    _nearbyService = NearbyEmergencyService(
      platform: _platform,
      transport: widget.nearbyAlerts ?? const UnavailableNearbyAlertTransport(),
    );
    // Demo never joins or polls; Live shows the real backend state.
    _helper = widget.liveRoutes
        ? NearbyHelperController(
            service: _nearbyService,
            onAlertArrived: () => unawaited(HapticFeedback.heavyImpact()),
          )
        : null;
    _safetyData = widget.liveRoutes
        ? null
        : widget.safetyData ??
              MockSafetyDataRepository(
                assistancePoints: demoAssistancePoints(),
                areaStatistics: const [],
              );
    _speaker = widget.speaker ?? _deviceSpeaker();
    final transport = widget.routeTransport ?? createDefaultJsonTransport();
    bool hasConsent() =>
        _navigation.hasRoutingConsent &&
        _navigation.liveNavigationAvailable &&
        _navigationActive &&
        _foreground &&
        !_lifetime.isCancelled;
    final osrm = DefaultRouteService(
      pointLookup: _lookupRoutePoints,
      liveProvider: OsrmWalkingRouteProvider(
        transport: transport,
        hasConsent: hasConsent,
        pointLookup: _lookupRoutePoints,
      ),
    );
    final planner = ValhallaAvoidingRoutePlanner(hasConsent: hasConsent);
    RouteService avoiding() => widget.liveRoutes
        ? AvoidingRouteService(
            planner: planner,
            fallback: osrm,
            areas: () => [..._areas, ..._crimeAreas],
          )
        : osrm;
    _storeRoutes = widget.routeService ?? avoiding();
    _navigation = SafeWalkNavigationController(
      routeService: widget.routeService ?? avoiding(),
      mode: widget.liveRoutes ? sw.DataMode.live : sw.DataMode.mock,
      livePresentationReady: widget.liveRoutes,
      liveProviderReady: widget.liveRoutes,
    );
    _navigation.addListener(_syncFollowing);
    if (widget.liveRoutes && widget.consentGranted) {
      _navigation.setRoutingConsent(true);
      _hasCrimeConsent = _crime.isConfigured;
      _crimeConsentAsked = true;
    }
    if (widget.liveRoutes) {
      _report = SafeWalkReportStatusController(
        repository: _crime,
        reviewedAreas: widget.reviewedAreas,
      )..setForeground(_foreground);
      _pointsLoading = false;
    } else {
      unawaited(_loadPoints());
    }
  }

  /// Replace route followers during a replan, retaining the one foreground GPS
  /// subscription. Cancellation, failure and leaving navigation still stop it.
  void _syncFollowing() {
    final result = _navigation.routeResult;
    if (result is sw.RouteSuccess) _guidancePreview = result;
    if (!widget.liveRoutes ||
        _manualOrigin != null ||
        !_navigationActive ||
        !_foreground ||
        !_navigation.hasRoutingConsent) {
      _followed = result;
      _stopFollowing();
      return;
    }
    if (result == null) {
      _followed = null;
      _followers = const [];
      if (!_navigation.routeLoading) _stopFollowing();
      return;
    }
    if (identical(result, _followed)) return;
    _followed = result;
    if (result is! sw.RouteSuccess || result.mode != sw.DataMode.live) {
      _stopFollowing();
      return;
    }
    _followers = [for (final r in result.routes) RouteFollower(r)];
    _watch ??= (widget.watchPosition ?? watchDevicePosition)().listen(
      _onPosition,
      onError: (_) => _stopFollowing(),
    );
    _headingSub ??= (widget.watchHeading ?? watchDeviceHeading)().listen(
      (h) {
        // Redraw only for a visible turn; the sensors report ~15 times/s.
        final old = _heading;
        if (!mounted ||
            (old != null && ((h - old + 540) % 360 - 180).abs() < 3)) {
          return;
        }
        setState(() => _heading = h);
      },
      // No compass on this device: keep the plain dot.
      onError: (_) {},
    );
  }

  void _onPosition(sw.Position position) {
    if (!mounted ||
        !_foreground ||
        !_navigationActive ||
        !_navigation.hasRoutingConsent ||
        _followers.isEmpty ||
        !_usableLiveFix(position)) {
      return;
    }
    setState(() => _livePosition = position);
    final updates = [for (final f in _followers) f.update(position)];
    final offAll = updates.every((u) => u.shouldReroute);
    final destination = _destination;
    final now = DateTime.now();
    if (!offAll ||
        destination == null ||
        _navigation.routeLoading ||
        (_lastReplan != null && now.difference(_lastReplan!) < _replanGap)) {
      return;
    }
    _lastReplan = now;
    unawaited(
      _planRoute(
        _createRouteRequest(origin: position, destination: destination),
      ),
    );
  }

  void _stopFollowing() {
    unawaited(_watch?.cancel());
    _watch = null;
    unawaited(_headingSub?.cancel());
    _headingSub = null;
    _heading = null;
    _followers = const [];
    _livePosition = null;
  }

  bool _usableLiveFix(sw.Position position) =>
      position.source == sw.PositionSource.gps &&
      position.accuracyMeters != null &&
      position.accuracyMeters!.isFinite &&
      position.accuracyMeters! >= 0 &&
      position.accuracyMeters! <= 100 &&
      positionProblems(position).isEmpty;

  Future<List<sw.AssistancePoint>> _lookupRoutePoints(
    List<String> ids, {
    SafeWalkCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    _lifetime.throwIfCancelled();
    // Only the already validated, same-mode M4 snapshot is available here.
    // No additional lookup, GPS request or Overpass query is started.
    return _points
        .where((point) => ids.contains(point.id))
        .toList(growable: false);
  }

  Future<void> _planRoute(sw.RouteRequest request) async {
    if (_lifetime.isCancelled || !_foreground || !_navigationActive) return;
    if (widget.liveRoutes && !_navigation.hasRoutingConsent) return;
    await _navigation.planRoute(request);
  }

  void _invalidateOperation() {
    ++_boundaryRevision;
    _operation?.cancel();
    _operation = null;
    _guidancePreview = null;
    _locationRequest?.cancel();
    _locationRequest = null;
    _stopFollowing();
    _navigation.cancelRoute();
    _crimeAreas = const [];
    _crimeSpots = const [];
    _crimeQueryStatus = !_crime.isConfigured
        ? '犯罪參考資料尚未配置；路線未套用犯罪參考避讓。'
        : _hasCrimeConsent
        ? '犯罪參考查詢已清除；重新規劃路線時才會查詢。'
        : '未同意犯罪參考查詢；路線不套用犯罪參考避讓。';
  }

  void _setRoutingConsent(bool consent) {
    if (!consent) {
      _clearNearby();
      _invalidateOperation();
    }
    _navigation.setRoutingConsent(consent);
  }

  void _setCrimeConsent(bool consent) {
    _hasCrimeConsent = consent;
    _crimeConsentAsked = true;
    if (!consent) {
      _clearNearby();
      _invalidateOperation();
    }
    if (mounted) {
      setState(() {
        _crimeQueryStatus = consent
            ? '已同意犯罪參考查詢；重新規劃路線時才會查詢。'
            : '未同意犯罪參考查詢；路線不套用犯罪參考避讓。';
      });
    }
  }

  /// Same pattern as the crime setting: a dialog to agree or decline.
  /// Declining cancels any route work in flight.
  Future<void> _manageRoutingConsent() async {
    if (!mounted || !_foreground || _lifetime.isCancelled) return;
    // Changing the setting stops route work in flight; it resumes only after
    // the walker agrees and plans again.
    _invalidateOperation();
    final revision = _boundaryRevision;
    final prompt = _routingConsentPrompt ??= _askRoutingConsent();
    final agreed = await prompt;
    if (identical(_routingConsentPrompt, prompt)) _routingConsentPrompt = null;
    if (!mounted ||
        !_foreground ||
        _lifetime.isCancelled ||
        revision != _boundaryRevision ||
        agreed == null) {
      return;
    }
    _setRoutingConsent(agreed);
  }

  Future<void> _manageCrimeConsent() async {
    if (!mounted || !_foreground || _lifetime.isCancelled) return;
    if (!_crime.isConfigured) {
      setState(() => _crimeQueryStatus = '犯罪參考資料尚未配置；路線未套用犯罪參考避讓。');
      await showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('犯罪資料查詢暫時無法使用'),
          content: const Text(
            '這個版本尚未啟用犯罪參考資料服務。請更新至最新版本；'
            '若仍無法使用，請向服務維護者回報。'
            '你仍可規劃步行路線，但路線不會套用犯罪參考避讓。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialog).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }
    _openNavigation();
    final revision = _boundaryRevision;
    final prompt = _crimeConsentPrompt ??= _askCrimeConsent();
    final agreed = await prompt;
    if (identical(_crimeConsentPrompt, prompt)) _crimeConsentPrompt = null;
    if (!mounted ||
        !_foreground ||
        !_navigationActive ||
        _lifetime.isCancelled ||
        revision != _boundaryRevision ||
        agreed == null) {
      return;
    }
    _setCrimeConsent(agreed);
  }

  /// Each explicit plan owns GPS, reference query and route work. A newer
  /// destination or lifecycle boundary invalidates every later continuation.
  Future<void> _planTo(sw.Coordinates destination) async {
    if (!mounted || !_foreground || _lifetime.isCancelled) return;
    _invalidateOperation();
    _openNavigation();
    _destination = destination;
    final operation = _operation = _RouteCancellation();
    bool current() => _isCurrent(operation) && _navigation.hasRoutingConsent;
    final origin = await _consentedOrigin(operation);
    if (origin == null || !current()) return;
    await _loadCrime(origin.coordinates, destination, operation);
    if (!current()) return;
    await _planRoute(
      _createRouteRequest(origin: origin, destination: destination),
    );
  }

  /// Asks for route consent (and, once, the crime query), then reads the
  /// start: the picked origin or a fresh GPS fix. Null when declined,
  /// unavailable or no longer current; the walker is told why.
  Future<sw.Position?> _consentedOrigin(
    _RouteCancellation operation, {
    bool Function()? isCurrent,
  }) async {
    bool current() => isCurrent?.call() ?? _isCurrent(operation);
    if (!await _askConsents(current)) return null;
    final manual = _manualOrigin;
    if (manual != null) {
      return sw.Position(
        coordinates: manual,
        source: sw.PositionSource.manual,
        accuracyMeters: null,
        observedAt: DateTime.now().toUtc().toIso8601String(),
      );
    }
    final sw.LocationResult located;
    try {
      located = await _platform.getCurrentPosition(
        mode: _navigation.mode,
        userInitiated: true,
        cancellation: operation,
      );
    } on SafeWalkCancelledException {
      return null;
    } catch (_) {
      if (!mounted || !current()) return null;
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(const SnackBar(content: Text('暫時無法取得位置，請重新定位或選擇起點。')));
      return null;
    }
    if (!mounted || !current() || !_navigation.hasRoutingConsent) {
      return null;
    }
    if (located is! sw.LocationSuccess || !_usableLiveFix(located.position)) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('無法取得新鮮且精確的 GPS 位置，請檢查定位權限或重新定位。')),
      );
      return null;
    }
    return located.position;
  }

  /// Route consent, then (once) the crime query consent: one dialog at a
  /// time. True when routing is allowed and the caller is still current.
  Future<bool> _askConsents(bool Function() current) async {
    if (!_navigation.hasRoutingConsent) {
      final prompt = _routingConsentPrompt ??= _askRoutingConsent();
      final agreed = await prompt;
      if (identical(_routingConsentPrompt, prompt)) {
        _routingConsentPrompt = null;
      }
      if (!current() || agreed != true) return false;
      _setRoutingConsent(true);
    }
    if (!current() || !_navigation.hasRoutingConsent) return false;
    if (_crime.isConfigured && !_crimeConsentAsked) {
      final prompt = _crimeConsentPrompt ??= _askCrimeConsent();
      final agreed = await prompt;
      if (identical(_crimeConsentPrompt, prompt)) _crimeConsentPrompt = null;
      if (!current()) return false;
      _hasCrimeConsent = agreed == true;
      _crimeConsentAsked = true;
      setState(
        () => _crimeQueryStatus = _hasCrimeConsent
            ? '已同意犯罪參考查詢。'
            : '未同意犯罪參考查詢；本次路線不套用犯罪參考避讓。',
      );
    }
    return current() && _navigation.hasRoutingConsent;
  }

  static const _nearbyCount = 3;

  /// 最近求助地點: convenience stores and police near the start from the
  /// bundled OSM snapshot, only those recorded as open now. Each is routed
  /// like a destination with the same avoiding routes. The three nearest are
  /// shown nearest first: the nearest one's route options as soon as they
  /// are ready, the others as they finish.
  Future<void> _planNearby() async {
    if (!widget.liveRoutes ||
        !mounted ||
        !_foreground ||
        _lifetime.isCancelled) {
      return;
    }
    _nearbyOperation?.cancel();
    _openNavigation();
    final operation = _nearbyOperation = _RouteCancellation();
    bool alive() =>
        mounted &&
        _foreground &&
        _navigationActive &&
        !_lifetime.isCancelled &&
        identical(_nearbyOperation, operation) &&
        !operation.isCancelled;
    bool current() => alive() && _navigation.hasRoutingConsent;
    setState(() {
      _nearby = const [];
      _nearbyLoading = true;
      _nearbyError = null;
    });
    void fail(String message) {
      if (!alive()) return;
      setState(() {
        _nearbyLoading = false;
        _nearbyError = message;
      });
    }

    final origin = await _consentedOrigin(operation, isCurrent: alive);
    if (origin == null || !current()) {
      return fail(
        _navigation.hasRoutingConsent
            ? '取得不到夠精確的位置（需 100 公尺內）。可以在地圖上選起點，再找附近營業中的店家。'
            : '需要同意路線查詢並取得位置，才能找附近營業中的店家。',
      );
    }
    final List<sw.AssistancePoint> stores;
    try {
      final points = await (widget.findStores ?? _snapshotNear)(
        origin.coordinates,
        cancellation: operation,
      );
      if (!current()) return;
      // Closed ones are dropped; at most one with unknown hours; one spare in
      // case a place cannot be routed to.
      stores = pickNearbyCandidates(
        origin.coordinates,
        points,
        count: _nearbyCount,
        // Only places recorded as open now; unknown hours are left out.
        maxUnknown: 0,
      );
    } on SafeWalkCancelledException {
      return;
    } catch (_) {
      return fail('暫時查不到附近的求助地點，請稍後再試。');
    }
    if (stores.isEmpty) {
      return fail(
        '附近 2 公里內沒有資料標示營業中的便利商店或派出所（資料不完整，不代表附近沒有）。可以改走回家路線，或直接按緊急求助。',
      );
    }
    final all = [origin.coordinates, for (final s in stores) s.coordinates];
    await _loadCrime(
      sw.Coordinates(
        lat: all.map((c) => c.lat).reduce(math.min),
        lng: all.map((c) => c.lng).reduce(math.min),
      ),
      sw.Coordinates(
        lat: all.map((c) => c.lat).reduce(math.max),
        lng: all.map((c) => c.lng).reduce(math.max),
      ),
      operation,
      current: current,
    );
    if (!current()) return;
    final options = <NearbyHelpOption>[];
    for (final store in stores) {
      if (options.length == _nearbyCount) break;
      try {
        final result = await _storeRoutes.planRoute(
          _createRouteRequest(origin: origin, destination: store.coordinates),
          cancellation: operation,
        );
        if (!current()) return;
        if (result is sw.RouteSuccess &&
            result.mode == sw.DataMode.live &&
            result.routes.isNotEmpty) {
          options.add(NearbyHelpOption(point: store, route: result));
          // Show each place as soon as its route is ready (nearest first);
          // the others keep loading behind it.
          setState(() => _nearby = List.unmodifiable(options));
        }
      } on SafeWalkCancelledException {
        return;
      } catch (_) {
        // One store that cannot be routed must not hide the others.
        if (!current()) return;
      }
    }
    if (options.isEmpty) {
      return fail('找到附近營業中的求助地點，但暫時無法規劃步行路線，請稍後再試。');
    }
    setState(() {
      // Nearest first; the walker picks among the three.
      _nearby = List.unmodifiable(options);
      _nearbyLoading = false;
    });
  }

  /// The walker chose a store: it becomes the navigation target. Its route,
  /// planned with the same analysis, goes to the same navigation controller,
  /// so following and re-planning now head for the store.
  void _selectPoint(String id) {
    final option = _nearby.where((o) => o.point.id == id).firstOrNull;
    if (option == null || !_foreground || _lifetime.isCancelled) return;
    // A destination route still in flight must not replace the store's.
    _operation?.cancel();
    _operation = null;
    _openNavigation();
    _destination = option.point.coordinates;
    _navigation.showRoute(option.route);
  }

  /// Stops store work and forgets its results (leaving, background, consent).
  void _clearNearby() {
    _nearbyOperation?.cancel();
    _nearbyOperation = null;
    _nearby = const [];
    _nearbyLoading = false;
    _nearbyError = null;
  }

  Future<bool?> _askRoutingConsent() => showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('規劃路線需要你的位置'),
      content: const Text(
        '會把起點、目的地及要避開的 50 公尺緩衝區傳給路線服務'
        '（valhalla1.openstreetmap.de、routing.openstreetmap.de）計算步行路線；'
        '附近求助地點用 App 內建的 OpenStreetMap 快照查詢，不另外傳送位置。'
        '導航期間會在前景持續更新位置，用於路線跟隨與偏離後重新規劃；離開導航或進入背景即停止。'
        '系統定位權限與犯罪參考資料查詢會分別取得同意；可在首頁「資料來源與授權」撤回路線查詢同意。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(false),
          child: Text(_navigation.hasRoutingConsent ? '撤回同意' : '不要'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(true),
          child: const Text('同意'),
        ),
      ],
    ),
  );

  Future<bool?> _askCrimeConsent() => showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('犯罪參考資料查詢同意'),
      content: Text(
        '將起點與目的地周圍的查詢外框傳給 Supabase（$_crimeServiceHost），'
        '讀取附近歷史犯罪參考資料。這會透露大致行程範圍，與路線查詢同意分開。'
        '50 公尺是產品設定的避讓緩衝，並非官方案發範圍或安全保證。'
        '拒絕仍可規劃步行路線；可隨時在首頁「資料來源與授權」撤回。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(false),
          child: Text(_hasCrimeConsent ? '撤回同意' : '不要查詢'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(true),
          child: const Text('同意查詢'),
        ),
      ],
    ),
  );

  void _openNavigation() {
    if (!_lifetime.isCancelled && _foreground) _navigationActive = true;
  }

  /// Ending guidance stops all work but keeps the last route as a preview.
  /// A fresh explicit start may resume following that route.
  void _endGuidance() {
    final preview = _guidancePreview;
    _navigationActive = false;
    ++_boundaryRevision;
    _operation?.cancel();
    _operation = null;
    _locationRequest?.cancel();
    _locationRequest = null;
    _nearbyOperation?.cancel();
    _nearbyOperation = null;
    _nearbyLoading = false;
    _stopFollowing();
    _navigation.cancelRoute();
    if (preview != null) _navigation.showRoute(preview);
    if (mounted) setState(() {});
  }

  void _startGuidance() {
    if (!mounted || !_foreground || _lifetime.isCancelled) return;
    _openNavigation();
    _followed = null;
    _syncFollowing();
  }

  void _closeNavigation() {
    _cancelMapReports();
    _navigationActive = false;
    _destination = null;
    _clearNearby();
    _invalidateOperation();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    _speaker.setLifecycleActive(active);
    _report?.setForeground(active);
    _helper?.setForeground(active);
    // `inactive` is transient (a system dialog, or the browser window losing
    // focus on web); only really leaving the app clears the route.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _foreground = false;
      _closeNavigation();
    } else if (state == AppLifecycleState.resumed) {
      _foreground = true;
    }
    if (mounted) setState(() {});
  }

  SafeWalkRouteSpeaker _deviceSpeaker() {
    final speaker = TtsSafeWalkSpeaker.device();
    // Rebuild once the device answers, so the view's voice notice is accurate.
    unawaited(
      speaker.prepare().then((_) {
        if (mounted) setState(() {});
      }),
    );
    return speaker;
  }

  sw.RouteRequest _createRouteRequest({
    required sw.Position origin,
    required sw.Coordinates destination,
    sw.RouteKind? preference,
    int? maxExtraDistanceMeters,
    List<String>? assistancePointIds,
  }) => sw.RouteRequest(
    requestId: 'm1-route-${++_routeSequence}',
    mode: _navigation.mode,
    origin: origin,
    destination: destination,
    departAt: DateTime.now().toUtc().toIso8601String(),
    preference: preference ?? sw.RouteKind.direct,
    maxExtraDistanceMeters: maxExtraDistanceMeters ?? 500,
    assistancePointIds: assistancePointIds ?? const [],
  );

  void _exit() {
    _closeNavigation();
    _report?.cancel();
    _lifetime.cancel();
    _pointsRequest?.cancel();
    _speaker.stop();
    if (widget.onExit != null) {
      widget.onExit!();
    } else {
      unawaited(Navigator.of(context).maybePop());
    }
  }

  Future<void> _loadPoints() async {
    if (widget.liveRoutes) return;
    _pointsRequest?.cancel();
    final request = _pointsRequest = _RouteCancellation();
    setState(() {
      _points = const [];
      _pointsLoading = true;
      _pointsError = null;
    });
    try {
      final points = await _safetyData!.getAssistancePoints(
        mode: sw.DataMode.mock,
        cancellation: request,
      );
      request.throwIfCancelled();
      const parser = ContractSafetyDataParser();
      final checked = points
          .map((point) {
            if (point.source.dataMode != sw.DataMode.mock) {
              throw const FormatException(
                'Live points cannot enter the mock demo',
              );
            }
            return parser.parseAssistancePoint(point.toJson());
          })
          .toList(growable: false);
      if (!mounted || request.isCancelled) return;
      setState(() => _points = List.unmodifiable(checked));
    } on SafeWalkCancelledException {
      return;
    } catch (_) {
      if (!mounted || request.isCancelled) return;
      setState(() => _pointsError = '求助地點暫時無法載入，請稍後重試。');
    } finally {
      if (mounted && !request.isCancelled) {
        setState(() => _pointsLoading = false);
      }
    }
  }

  Future<sw.LocationResult> _locate() async {
    _locationRequest?.cancel();
    final request = _locationRequest = _RouteCancellation();
    try {
      if (!_foreground || _lifetime.isCancelled) {
        throw const SafeWalkCancelledException();
      }
      final result = await _platform.getCurrentPosition(
        mode: widget.liveRoutes ? sw.DataMode.live : sw.DataMode.mock,
        userInitiated: true,
        cancellation: request,
      );
      _lifetime.throwIfCancelled();
      request.throwIfCancelled();
      if (!_foreground || !mounted) throw const SafeWalkCancelledException();
      if (!widget.liveRoutes &&
          result is sw.LocationSuccess &&
          result.position.source != sw.PositionSource.mock) {
        return _locationFailure('示範模式未取得示範位置，請重試。');
      }
      if (widget.liveRoutes &&
          result is sw.LocationSuccess &&
          !_usableLiveFix(result.position)) {
        return _locationFailure('未取得真實位置，請重新定位。');
      }
      return result;
    } on SafeWalkCancelledException {
      return _locationFailure('定位操作已取消。');
    } on TimeoutException {
      return sw.LocationFailure(
        status: sw.LocationFailureStatus.timeout,
        message: '定位逾時，請重試或說出附近地標。',
      );
    } catch (_) {
      return _locationFailure('暫時無法取得位置，請重試或說出附近地標。');
    }
  }

  sw.LocationFailure _locationFailure(String message) => sw.LocationFailure(
    status: sw.LocationFailureStatus.unavailable,
    message: message,
  );

  bool get _dialerEnabled => widget.liveRoutes && widget.allowEmergencyDialer;

  Future<void> _openOfficialReport() async {
    await _stopForEmergency();
    if (!mounted || _lifetime.isCancelled) return;
    widget.onOpenOfficialReport?.call();
  }

  /// Navigation and speech stop first, so an emergency action never competes
  /// with them. A broken audio adapter cannot keep the page waiting.
  Future<void> _stopForEmergency() async {
    _closeNavigation();
    try {
      await _speaker.stopForEmergency().timeout(const Duration(seconds: 1));
    } catch (_) {
      // The action remains available even if cleanup fails.
    }
  }

  SafeWalkNearbyBroadcast get _nearbyBroadcast => SafeWalkNearbyBroadcast(
    // Demo never notifies anyone; Live shows the real backend state.
    unavailableReason: widget.liveRoutes
        ? _nearbyService.unavailableReason
        : '示範模式不會通知任何人',
    onBroadcast: _broadcastNearby,
  );

  Future<NearbyBroadcastOutcome> _broadcastNearby(
    SafeWalkCancellation cancellation,
  ) async {
    await _stopForEmergency();
    if (_lifetime.isCancelled || cancellation.isCancelled) {
      return const NearbyBroadcastNotSent('已取消', cancelled: true);
    }
    // The backend identifies the sender from the verified session; this value
    // is ignored by the authenticated transport and never sent.
    final result = await _nearbyService.triggerEmergency(
      mode: sw.DataMode.live,
      senderId: '',
      userInitiated: true,
      cancellation: cancellation,
    );
    return switch (result) {
      NearbyEmergencySent(:final recipientCount) => NearbyBroadcastSent(
        recipientCount,
      ),
      NearbyEmergencyNotSent(:final reason, :final message) =>
        NearbyBroadcastNotSent(
          message,
          cancelled: reason == NearbyEmergencyBlock.cancelled,
        ),
    };
  }

  Future<sw.EmergencyActionResult> _emergency(
    sw.EmergencyChannel channel,
  ) async {
    await _stopForEmergency();
    try {
      if (_lifetime.isCancelled) throw const SafeWalkCancelledException();
      return await _platform.requestEmergency(
        mode: widget.liveRoutes ? sw.DataMode.live : sw.DataMode.mock,
        channel: channel,
        userInitiated: true,
        allowRealCalls: _dialerEnabled,
      );
    } catch (_) {
      return sw.EmergencyActionResult.fromJson({
        'schemaVersion': '1.0.0',
        'channel': channel.wireValue,
        'action': 'failed',
        'officialReceipt': null,
        'message': widget.liveRoutes
            ? '求助交接尚未完成；未確認撥號或通報，請使用手機電話功能。'
            : '示範求助暫時無法完成；未撥號、未傳送，也未通知任何人。',
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _navigation,
    builder: (context, child) => SafeWalkNavigationScope(
      mode: _navigation.mode,
      liveNavigationAvailable: _navigation.liveNavigationAvailable,
      hasRoutingConsent: _navigation.hasRoutingConsent,
      routeResult: _navigation.routeResult,
      routeLoading: _navigation.routeLoading,
      routeError: _navigation.routeError,
      createRouteRequest: _createRouteRequest,
      onPlanRoute: _planRoute,
      onCancelRoute: _invalidateOperation,
      onRoutingConsentChanged: _setRoutingConsent,
      onDestinationChanged: _invalidateOperation,
      onNavigationOpened: _openNavigation,
      onNavigationClosed: _closeNavigation,
      onEmergencyOpened: _closeNavigation,
      // Built here so route results, loading and live position reach the map.
      child: SafeWalkFlow(
        mode: widget.liveRoutes ? sw.DataMode.live : sw.DataMode.mock,
        allowRealCalls: _dialerEnabled,
        // Live: real open stores, only after the walker asks for them.
        points: widget.liveRoutes
            ? [for (final o in _nearby) o.point]
            : _points,
        pointRoutes: {for (final o in _nearby) o.point.id: o.route},
        onSelectPoint: widget.liveRoutes ? _selectPoint : null,
        pointsLoading: widget.liveRoutes ? _nearbyLoading : _pointsLoading,
        pointsError: widget.liveRoutes ? _nearbyError : _pointsError,
        onRetryPoints: widget.liveRoutes
            ? () => unawaited(_planNearby())
            : () => unawaited(_loadPoints()),
        showMapTiles: widget.showLiveMap,
        reportBuilder: _report == null
            ? null
            : (context, onBack) => SafeWalkReportStatusPage(
                controller: _report!,
                onBack: onBack,
                showMap: widget.showLiveMap,
              ),
        onLeaveReport: () => _report?.cancel(),
        route: widget.liveRoutes ? _navigation.routeResult : null,
        livePosition: _livePosition,
        liveHeading: _livePosition == null ? null : _heading,
        onLeaveMap: _closeNavigation,
        onStartNavigation: _startGuidance,
        onEndNavigation: _endGuidance,
        crimeSpots: _crimeSpots,
        crimeQueryStatus: widget.liveRoutes ? _crimeQueryStatus : null,
        onManageCrimeConsent: widget.liveRoutes && !widget.consentGranted
            ? () => unawaited(_manageCrimeConsent())
            : null,
        routingConsent: _navigation.hasRoutingConsent,
        crimeConsent: _hasCrimeConsent,
        onManageRoutingConsent: widget.liveRoutes && !widget.consentGranted
            ? () => unawaited(_manageRoutingConsent())
            : null,
        onStartChanged: widget.liveRoutes
            ? (origin) {
                _invalidateOperation();
                _manualOrigin = origin;
              }
            : null,
        routeLoading: widget.liveRoutes && _navigation.routeLoading,
        onPlanRoute: widget.liveRoutes
            ? (destination) => unawaited(_planTo(destination))
            : null,
        onReportsChanged: (spots) => _areas = [
          for (final spot in spots)
            AvoidArea(
              id: spot.id,
              center: spot.center,
              radiusMeters: AvoidArea.reportRadiusMeters,
              source: 'report',
            ),
        ],
        onSaveReport: widget.liveRoutes ? _saveMapReport : null,
        onLoadReports: widget.liveRoutes ? _loadMapReports : null,
        speaker: _speaker,
        onLocate: _locate,
        onEmergency: _emergency,
        onOfficialReport:
            widget.liveRoutes && widget.onOpenOfficialReport != null
            ? () => unawaited(_openOfficialReport())
            : null,
        nearbyBroadcast: _nearbyBroadcast,
        nearbyHelper: _helper,
        homeLocation: _home,
        onHomeChanged: _changeHome,
        onExit: _exit,
      ),
    ),
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelMapReports();
    _stopFollowing();
    _navigation.removeListener(_syncFollowing);
    _operation?.cancel();
    _nearbyOperation?.cancel();
    _locationRequest?.cancel();
    _lifetime.cancel();
    _pointsRequest?.cancel();
    _navigation.dispose();
    _helper?.dispose();
    _report?.dispose();
    unawaited(_speaker.dispose());
    super.dispose();
  }
}

final class _RouteCancellation implements SafeWalkCancellation {
  final _cancelled = Completer<void>();

  @override
  bool get isCancelled => _cancelled.isCompleted;

  @override
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }
}
