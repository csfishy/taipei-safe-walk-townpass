import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:town_pass/features/safe_walk/navigation/avoid_area.dart';
import 'package:town_pass/features/safe_walk/platform/integration/crime_reference_wiring.dart';
import 'package:town_pass/features/safe_walk/platform/supabase/safe_walk_supabase_config.dart';
import 'package:town_pass/features/safe_walk/platform/supabase/web_rpc_post.dart';
import 'package:town_pass/features/safe_walk/safety_data/crime_reference/crime_reference_models.dart';
import 'package:town_pass/features/safe_walk/safety_data/crime_reference/crime_reference_repository.dart';
import 'package:town_pass/features/safe_walk/navigation/default_json_transport.dart';
import 'package:town_pass/features/safe_walk/navigation/default_route_service.dart';
import 'package:town_pass/features/safe_walk/navigation/json_transport.dart';
import 'package:town_pass/features/safe_walk/navigation/osrm_walking_route_provider.dart';
import 'package:town_pass/features/safe_walk/navigation/route_follower.dart';
import 'package:town_pass/features/safe_walk/navigation/route_service.dart';
import 'package:town_pass/features/safe_walk/navigation/valhalla_avoiding_route_planner.dart';
import 'package:town_pass/features/safe_walk/platform/integration/avoiding_route_service.dart';
import 'package:town_pass/features/safe_walk/platform/home_location/home_location_service.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_route_speaker.dart';
import 'package:town_pass/features/safe_walk/platform/integration/tts_safe_walk_speaker.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_navigation_controller.dart';
import 'package:town_pass/features/safe_walk/platform/platform_service.dart';
import 'package:town_pass/features/safe_walk/platform/position_watch.dart';
import 'package:town_pass/features/safe_walk/platform/townpass_platform_adapter.dart';
import 'package:town_pass/features/safe_walk/presentation/mock/safe_walk_demo_data.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_flow.dart';
import 'package:town_pass/features/safe_walk/safety_data/contract_safety_data.dart';
import 'package:town_pass/features/safe_walk/safety_data/safety_data_service.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/cancellation.dart';
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
    this.crimeServiceHost,
    this.onExit,
    this.liveRoutes = false,
    this.watchPosition,
  });

  /// Continuous positions while the map is open; defaults to the device GPS.
  final Stream<sw.Position> Function()? watchPosition;

  /// Real walking routes: opening the map reads the device position (after the
  /// user agrees to share it with the OSM routing service) and asks OSRM for a
  /// route to the chosen place. Points, SOS and companion stay in Mock.
  final bool liveRoutes;

  final PlatformService? platform;
  final SafetyDataRepository? safetyData;

  /// Defaults to M2's service. Injection never changes the route's Mock mode.
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
  late final SafetyDataRepository _safetyData;
  late final SafeWalkRouteSpeaker _speaker;
  late final SafeWalkNavigationController _navigation;
  int _routeSequence = 0;
  bool _navigationActive = false;
  bool _foreground = true;
  _RouteCancellation? _operation;
  int _boundaryRevision = 0;
  List<sw.AssistancePoint> _points = const [];
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

  /// Product-defined buffers around reference positions; not incident bounds.
  late final CrimeReferenceRepository _crime =
      widget.crimeRepository ?? _crimeRepository();

  /// Local web preview only (`--dart-define=SAFE_WALK_WEB_ROUTES=true`).
  static const _webPreview = bool.fromEnvironment('SAFE_WALK_WEB_ROUTES');

  /// Phones use M1's dart:io client. The local web preview posts the same
  /// reviewed read-only RPC through browser fetch; default web stays off.
  static CrimeReferenceRepository _crimeRepository() {
    if (!kIsWeb || !_webPreview) {
      return CrimeReferenceWiring.fromEnvironment().repository;
    }
    final SafeWalkSupabaseConfig config;
    try {
      config = SafeWalkSupabaseConfig.fromEnvironment();
    } on SupabaseConfigurationException {
      return CrimeReferenceRepository(transport: null);
    }
    return CrimeReferenceRepository(
      transport: (arguments) async {
        final (status, body) = await webRpcPost(
          config.url.resolve('/rest/v1/rpc/$crimeReferenceRpcFunction'),
          {
            ...config.requestHeaders,
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          jsonEncode(arguments),
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
    _RouteCancellation operation,
  ) async {
    if (!_isCurrent(operation) || !_hasCrimeConsent) return;
    if (!_crime.isConfigured) {
      setState(() => _crimeQueryStatus = '犯罪參考資料尚未配置；本次路線未套用犯罪參考避讓。');
      return;
    }
    const m = 0.006; // ~600 m margin around the start/destination box
    setState(() => _crimeQueryStatus = '犯罪參考資料查詢中…');
    try {
      // Consent and operation state are checked immediately before the effect.
      if (!_isCurrent(operation) || !_hasCrimeConsent) return;
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
      if (!_isCurrent(operation) || !_hasCrimeConsent) return;
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
    } catch (_) {
      if (!_isCurrent(operation) || !_hasCrimeConsent) return;
      setState(() => _crimeQueryStatus = '犯罪參考資料查詢失敗；本次路線未套用犯罪參考避讓，請重試。');
    }
  }

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
  List<RouteFollower> _followers = const [];
  StreamSubscription<sw.Position>? _watch;
  sw.Position? _livePosition;
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
    if (!_crime.isConfigured) {
      _crimeQueryStatus = '犯罪參考資料尚未配置；路線未套用犯罪參考避讓。';
    }
    _platform =
        widget.platform ??
        TownPassPlatformAdapter(
          mockPosition: sw.Position.fromJson({
            'schemaVersion': '1.0.0',
            'coordinates': {'lat': DemoGeo.start.lat, 'lng': DemoGeo.start.lng},
            'source': 'mock',
            'accuracyMeters': null,
            'observedAt': null,
          }),
        );
    _safetyData =
        widget.safetyData ??
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
    _navigation = SafeWalkNavigationController(
      routeService:
          widget.routeService ??
          (widget.liveRoutes
              ? AvoidingRouteService(
                  planner: ValhallaAvoidingRoutePlanner(
                    hasConsent: hasConsent,
                  ),
                  fallback: osrm,
                  areas: () => [..._areas, ..._crimeAreas],
                )
              : osrm),
      mode: widget.liveRoutes ? sw.DataMode.live : sw.DataMode.mock,
      livePresentationReady: widget.liveRoutes,
      liveProviderReady: widget.liveRoutes,
    );
    _navigation.addListener(_syncFollowing);
    if (widget.liveRoutes) {
      _pointsLoading = false;
    } else {
      unawaited(_loadPoints());
    }
  }

  /// Replace route followers during a replan, retaining the one foreground GPS
  /// subscription. Cancellation, failure and leaving navigation still stop it.
  void _syncFollowing() {
    final result = _navigation.routeResult;
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
  }

  void _onPosition(sw.Position position) {
    if (!mounted ||
        !_foreground ||
        !_navigationActive ||
        !_navigation.hasRoutingConsent ||
        _followers.isEmpty) {
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
    _followers = const [];
    _livePosition = null;
  }

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
    if (!consent) _invalidateOperation();
    _navigation.setRoutingConsent(consent);
  }

  void _setCrimeConsent(bool consent) {
    _hasCrimeConsent = consent;
    _crimeConsentAsked = true;
    if (!consent) _invalidateOperation();
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
    final prompt = _routingConsentPrompt ??= _askRoutingConsent();
    final agreed = await prompt;
    if (identical(_routingConsentPrompt, prompt)) _routingConsentPrompt = null;
    if (!mounted || !_foreground || _lifetime.isCancelled || agreed == null) {
      return;
    }
    _setRoutingConsent(agreed);
  }

  Future<void> _manageCrimeConsent() async {
    if (!mounted || !_foreground || _lifetime.isCancelled) return;
    if (!_crime.isConfigured) {
      setState(() => _crimeQueryStatus = '犯罪參考資料尚未配置；路線未套用犯罪參考避讓。');
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
    if (!_navigation.hasRoutingConsent) {
      final prompt = _routingConsentPrompt ??= _askRoutingConsent();
      final agreed = await prompt;
      if (identical(_routingConsentPrompt, prompt)) {
        _routingConsentPrompt = null;
      }
      if (!_isCurrent(operation) || agreed != true) return;
      _setRoutingConsent(true);
    }
    if (!_isCurrent(operation) || !_navigation.hasRoutingConsent) return;
    if (_crime.isConfigured && !_crimeConsentAsked) {
      final prompt = _crimeConsentPrompt ??= _askCrimeConsent();
      final agreed = await prompt;
      if (identical(_crimeConsentPrompt, prompt)) _crimeConsentPrompt = null;
      if (!_isCurrent(operation)) return;
      _hasCrimeConsent = agreed == true;
      _crimeConsentAsked = true;
      setState(
        () => _crimeQueryStatus = _hasCrimeConsent
            ? '已同意犯罪參考查詢。'
            : '未同意犯罪參考查詢；本次路線不套用犯罪參考避讓。',
      );
    }
    if (!_isCurrent(operation) || !_navigation.hasRoutingConsent) return;
    final manual = _manualOrigin;
    if (manual != null) {
      await _loadCrime(manual, destination, operation);
      if (!_isCurrent(operation) || !_navigation.hasRoutingConsent) return;
      await _planRoute(
        _createRouteRequest(
          origin: sw.Position(
            coordinates: manual,
            source: sw.PositionSource.manual,
            accuracyMeters: null,
            observedAt: DateTime.now().toUtc().toIso8601String(),
          ),
          destination: destination,
        ),
      );
      return;
    }
    final sw.LocationResult located;
    try {
      located = await _platform.getCurrentPosition(
        mode: _navigation.mode,
        userInitiated: true,
        cancellation: operation,
      );
    } on SafeWalkCancelledException {
      return;
    } catch (_) {
      if (!mounted || !_isCurrent(operation)) return;
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(const SnackBar(content: Text('暫時無法取得位置，請重新定位或選擇起點。')));
      return;
    }
    if (!mounted || !_isCurrent(operation) || !_navigation.hasRoutingConsent) {
      return;
    }
    if (located is! sw.LocationSuccess) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text((located as sw.LocationFailure).message)),
      );
      return;
    }
    await _loadCrime(located.position.coordinates, destination, operation);
    if (!_isCurrent(operation) || !_navigation.hasRoutingConsent) return;
    await _planRoute(
      _createRouteRequest(origin: located.position, destination: destination),
    );
  }

  Future<bool?> _askRoutingConsent() => showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('規劃路線需要你的位置'),
      content: const Text(
        '會把起點、目的地及要避開的 50 公尺緩衝區傳給路線服務'
        '（valhalla1.openstreetmap.de、routing.openstreetmap.de）計算步行路線。'
        '導航期間會在前景持續更新位置，用於路線跟隨與偏離後重新規劃；離開導航或進入背景即停止。'
        '系統定位權限與犯罪參考資料查詢會分別取得同意；可在地圖撤回路線查詢同意。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(false),
          child: const Text('不要'),
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
        '拒絕仍可規劃步行路線；可隨時由地圖的犯罪查詢同意入口撤回。',
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

  void _closeNavigation() {
    _navigationActive = false;
    _destination = null;
    _invalidateOperation();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    _speaker.setLifecycleActive(active);
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
    _pointsRequest?.cancel();
    final request = _pointsRequest = _RouteCancellation();
    setState(() {
      _points = const [];
      _pointsLoading = true;
      _pointsError = null;
    });
    try {
      final points = await _safetyData.getAssistancePoints(
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
          result.position.source == sw.PositionSource.mock) {
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

  Future<sw.EmergencyActionResult> _emergency(
    sw.EmergencyChannel channel,
  ) async {
    _closeNavigation();
    // Issue the stop before platform work; a broken audio adapter cannot leave
    // the emergency page waiting indefinitely.
    try {
      await _speaker.stopForEmergency().timeout(const Duration(seconds: 1));
    } catch (_) {
      // The mock action remains available even if cleanup fails.
    }
    try {
      if (_lifetime.isCancelled) throw const SafeWalkCancelledException();
      return await _platform.requestEmergency(
        mode: sw.DataMode.mock,
        channel: channel,
        userInitiated: true,
        allowRealCalls: false,
      );
    } catch (_) {
      return sw.EmergencyActionResult.fromJson({
        'schemaVersion': '1.0.0',
        'channel': channel.wireValue,
        'action': 'failed',
        'officialReceipt': null,
        'message': '示範求助暫時無法完成；未撥號、未傳送，也未通知任何人。',
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
        allowRealCalls: false,
        // Live mode shows no demo help points; real nearby places come later.
        points: widget.liveRoutes ? const [] : _points,
        pointsLoading: !widget.liveRoutes && _pointsLoading,
        pointsError: widget.liveRoutes ? null : _pointsError,
        onRetryPoints: () => unawaited(_loadPoints()),
        route: widget.liveRoutes ? _navigation.routeResult : null,
        livePosition: _livePosition,
        onLeaveMap: _closeNavigation,
        crimeSpots: _crimeSpots,
        crimeQueryStatus: widget.liveRoutes ? _crimeQueryStatus : null,
        onManageCrimeConsent: widget.liveRoutes
            ? () => unawaited(_manageCrimeConsent())
            : null,
        routingConsent: _navigation.hasRoutingConsent,
        crimeConsent: _hasCrimeConsent,
        onManageRoutingConsent: widget.liveRoutes
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
        speaker: _speaker,
        onLocate: _locate,
        onEmergency: _emergency,
        homeLocation: _home,
        onHomeChanged: _changeHome,
        onExit: _exit,
      ),
    ),
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopFollowing();
    _navigation.removeListener(_syncFollowing);
    _operation?.cancel();
    _locationRequest?.cancel();
    _lifetime.cancel();
    _pointsRequest?.cancel();
    _navigation.dispose();
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
