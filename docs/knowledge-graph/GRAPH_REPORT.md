# 臺北安心行 知識圖（精簡版）

- 範圍：`lib/features/safe_walk/`（M1–M5 程式）、臺北通入口 `tp_route.dart` 與 `my_service_model.dart`、`docs/SAFE_WALK_*.md`、各模組 README、`AGENTS.md`。不含臺北通其他頁面、測試與圖片。
- 打開 `graph.html`（需連網載入 vis-network）。點節點看連線；顏色＝群組，群組名稱前綴是模組（M1–M5）。
- 用法：改共用參數前先看會影響哪些模組（例如 `SafeWalkFlow`）；找文件與程式對不上的地方；團隊文件的架構圖素材。
- 這是 main `0ea9979`（PR #22 合併後，11/7 21:06）的快照，程式改了要重跑 graphify。`lib/features/safe_walk/companion/README.md` 在 #22 更新後尚未重新抽取，不在圖中。

這是歷史快照與探索工具，不是功能已接線、Live 驗收或測試通過的證據。`INFERRED` 關係、群組與建議問題屬於推論，文件概念也可能保留初始化時的舊敘述，不取代模組責任規格。PR #31 合併後，現況以[逐能力 Readiness](../SAFE_WALK_LIVE_READINESS.md)、實際 main 程式及對應驗證證據為準；本圖不會自動更新。

# Graph Report - townpass-repo  (2026-11-07)

## Corpus Check
- 77 files · ~0 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1516 nodes · 1907 edges · 71 communities (64 shown, 7 thin omitted)
- Extraction: 99% EXTRACTED · 1% INFERRED · 0% AMBIGUOUS · INFERRED: 19 edges (avg confidence: 0.86)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- M3 介面｜safe_walk_map_view
- 其他｜
- M4 安全資料｜violent_crime_normalizer
- M3 介面｜safe_walk_call_view
- M3 介面｜safe_walk_ui
- M3 介面｜safe_walk_demo_data
- 共用契約與模型｜schema_validator
- M1 平台與接線｜anonymous_helper_id
- M3 介面｜safe_walk_flow
- M1 平台與接線｜safe_walk_composition_root
- M2 導航｜osm_convenience_store_source
- M2 導航｜route_follower
- M5 陪伴｜companion_controller
- M5 陪伴｜companion_tts
- M3 介面｜demo_map
- M4 安全資料｜taipei_violent_crime_repository
- M1 平台與接線｜safe_walk_navigation_controller
- M1 平台與接線｜companion_speaker_adapter
- M3 介面｜safe_walk_emergency_view
- 共用契約與模型｜safe_walk_contracts
- M3 介面｜safe_walk_map_view 2
- M1 平台與接線｜nearby_alert_transport
- M3 介面｜safe_walk_home_view
- M1 平台與接線｜supabase_connection
- M4 安全資料｜README
- M2 導航｜cancellable
- 共用契約與模型｜safe_walk_navigation_scope
- M2 導航｜nearest_point
- M1 平台與接線｜nearby_emergency_service
- M2 導航｜osrm_walking_route_provider
- M5 陪伴｜companion_service
- M1 平台與接線｜tts_safe_walk_speaker
- M4 安全資料｜contract_safety_data
- M3 介面｜safe_walk_call_view 2
- 臺北通入口｜my_service_model
- 文件｜SAFE_WALK_SCHEMA
- M2 導航｜default_route_service
- 共用契約與模型｜safe_walk_models_generated
- M2 導航｜io_json_transport
- M1 平台與接線｜townpass_platform_adapter
- 文件｜SAFE_WALK_NAVIGATION_PRESENTATION_CONTRACT
- M2 導航｜
- 文件｜AGENTS
- 文件｜SAFE_WALK_MODULES
- M3 介面｜safe_walk_speaker
- M2 導航｜consent
- M1 平台與接線｜README
- M2 導航｜walking_route_provider
- M2 導航｜README
- M2 導航｜google_maps_link
- 文件｜SAFE_WALK_INTEGRATION
- 文件｜SAFE_WALK_CI
- M2 導航｜README 2
- M1 平台與接線｜safe_walk_route_speaker
- M4 安全資料｜safety_data_service
- M4 安全資料｜get_connect_text_fetcher
- M1 平台與接線｜safe_walk_composition_root 2
- M3 介面｜safe_walk_card_assets
- 文件｜SAFE_WALK_COMPETITION_LICENSE
- 文件｜SAFE_WALK_SUPABASE
- M5 陪伴｜companion_state
- 其他｜ 2
- 共用契約與模型｜safe_walk_models_generated 2
- M3 介面｜
- 共用契約與模型｜safe_walk_models_generated 3
- 共用契約與模型｜safe_walk_models_generated 4
- 其他｜ 4
- M3 介面｜safe_walk_ui 2
- 共用契約與模型｜schema_generated

## God Nodes (most connected - your core abstractions)
1. `SafeWalkModel` - 18 edges
2. `SafeWalkFlow` - 15 edges
3. `Safe Walk JSON Schema and Dart Contracts` - 15 edges
4. `Five-Person Module Contracts` - 12 edges
5. `M1/M2/M3 Navigation Wiring Spec` - 11 edges
6. `AGENTS.md Safe Walk Collaboration Rules` - 11 edges
7. `M1 TownPass Entry Integration` - 10 edges
8. `SafeWalkCancellation` - 9 edges
9. `Safe Walk TownPass Native Architecture Baseline` - 8 edges
10. `Safe Walk Initialization Record` - 8 edges

## Surprising Connections (you probably didn't know these)
- `Planning-Intent Generation Check` --semantically_similar_to--> `SafeWalkCancellation`  [INFERRED] [semantically similar]
  docs/SAFE_WALK_NAVIGATION_PRESENTATION_CONTRACT.md → lib/features/safe_walk/shared/contracts/cancellation.dart
- `Five-Module File Ownership (M1-M5)` --semantically_similar_to--> `Five-Person Module Contracts`  [INFERRED] [semantically similar]
  AGENTS.md → docs/SAFE_WALK_MODULES.md
- `M5 Companion Controller/Audio Adapter` --references--> `CompanionController`  [EXTRACTED]
  docs/SAFE_WALK_MODULES.md → lib/features/safe_walk/companion/companion_service.dart
- `M2 Navigation RouteService` --references--> `RouteService`  [EXTRACTED]
  docs/SAFE_WALK_MODULES.md → lib/features/safe_walk/navigation/route_service.dart
- `OSRM Walking Route Provider` --implements--> `RouteService`  [INFERRED]
  docs/SAFE_WALK_NAVIGATION_PRESENTATION_CONTRACT.md → lib/features/safe_walk/navigation/route_service.dart

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Five Safe Walk Modules Composed by M1** — docs_safe_walk_modules_m1_platform, docs_safe_walk_modules_m2_navigation, docs_safe_walk_modules_m3_presentation, docs_safe_walk_modules_m4_safety_data, docs_safe_walk_modules_m5_companion [EXTRACTED 1.00]
- **Route Planning Flow (consent -> request -> controller -> RouteResult)** — docs_safe_walk_navigation_presentation_contract_routing_consent, docs_safe_walk_schema_routerequest, docs_safe_walk_navigation_presentation_contract_navigation_controller, docs_safe_walk_schema_routeresult, docs_safe_walk_navigation_presentation_contract_osrm [INFERRED 0.85]
- **Nearest 24h Store Navigation Flow** — lib_features_safe_walk_navigation_readme_neareststoreplanner, lib_features_safe_walk_navigation_readme_osmconveniencestoresource, lib_features_safe_walk_navigation_readme_nearestpoints, lib_features_safe_walk_navigation_readme_defaultrouteservice, lib_features_safe_walk_navigation_readme_googlemapswalkinguri [EXTRACTED 1.00]
- **Safe Walk Five-Module Architecture (M1-M5)** — lib_features_safe_walk_platform_readme_m1_platform_module, lib_features_safe_walk_navigation_readme_m2_navigation_module, lib_features_safe_walk_presentation_readme_m3_presentation_module, lib_features_safe_walk_safety_data_readme_m4_safety_data_module [EXTRACTED 1.00]
- **M1 Route Wiring into M3 UI** — lib_features_safe_walk_platform_readme_safewalkcompositionroot, lib_features_safe_walk_platform_readme_safewalknavigationcontroller, lib_features_safe_walk_platform_readme_safe_walk_navigation_scope, lib_features_safe_walk_presentation_safe_walk_flow_safewalkflow [INFERRED 0.85]

## Communities (71 total, 7 thin omitted)

### Community 0 - "M3 介面｜safe_walk_map_view"
Cohesion: 0.02
Nodes (78): anomalies, arrive, _at, best, build, _category, child, configured (+70 more)

### Community 1 - "其他｜"
Cohesion: 0.03
Nodes (27): account, activityDetail, activityList, basicInfo, basicInfoEdit, feedback, home, invoiceReceipt (+19 more)

### Community 2 - "M4 安全資料｜violent_crime_normalizer"
Cohesion: 0.03
Nodes (73): aggregation, breakdown, buildViolentCrimeSource, caseCount, category, cell, city, cityCrimeProblems (+65 more)

### Community 3 - "M3 介面｜safe_walk_call_view"
Cohesion: 0.03
Nodes (59): _active, _answer, answered, build, _button, _buzz, caller, createState (+51 more)

### Community 4 - "M3 介面｜safe_walk_ui"
Cohesion: 0.03
Nodes (58): actionLabel, bg, body, bodyStrong, border, brand, brandDeep, brandSoft (+50 more)

### Community 5 - "M3 介面｜safe_walk_demo_data"
Cohesion: 0.04
Nodes (52): Anomaly, AnomalyCategory, anomalyCategoryLabel, anomalyStatusLabel, at, avoidedCount, category, demoAnomalies (+44 more)

### Community 6 - "共用契約與模型｜schema_validator"
Cohesion: 0.04
Nodes (47): a, _bundle, ContractViolation, _copy, copyJsonObject, current, day, days (+39 more)

### Community 7 - "M1 平台與接線｜anonymous_helper_id"
Cohesion: 0.05
Nodes (36): distanceMeters, dLat, dLng, earthRadiusMeters, fromGeoJson, geoJsonDistanceMeters, h, _haversine (+28 more)

### Community 8 - "M3 介面｜safe_walk_flow"
Cohesion: 0.05
Nodes (35): SafeWalkCallSession, allowRealCalls, _anomalies, _back, build, _call, _callKey, _channel (+27 more)

### Community 9 - "M1 平台與接線｜safe_walk_composition_root"
Cohesion: 0.05
Nodes (34): build, cancel, _cancelled, _closeNavigation, _createRouteRequest, createState, _deviceSpeaker, didChangeAppLifecycleState (+26 more)

### Community 10 - "M2 導航｜osm_convenience_store_source"
Cohesion: 0.05
Nodes (32): IoJsonTransport, failure, getJson, JsonTransport, JsonTransportException, postFormJson, toString, TransportFailure (+24 more)

### Community 11 - "M2 導航｜route_follower"
Cohesion: 0.05
Nodes (36): along, arrivalMeters, _arrived, backtrackToleranceMeters, bearing, bearingDegrees, cameraCenter, crossTrack (+28 more)

### Community 12 - "M5 陪伴｜companion_controller"
Cohesion: 0.05
Nodes (36): _activeInterruption, _audio, _cancelOperation, _clock, CompanionAssetResolver, CompanionClock, CompanionDelay, _delay (+28 more)

### Community 13 - "M5 陪伴｜companion_tts"
Cohesion: 0.06
Nodes (30): available, _blocked, CompanionSpeechEngine, _deviceDriver, dispose, _disposed, _driver, _engine (+22 more)

### Community 14 - "M3 介面｜demo_map"
Cohesion: 0.06
Nodes (29): active, anomalies, _AnomalyMark, back, build, compact, _dashed, dy (+21 more)

### Community 15 - "M4 安全資料｜taipei_violent_crime_repository"
Cohesion: 0.06
Nodes (29): _acceptCsvUri, _cached, cacheTtl, converted, _csvHost, csvUri, declaredRows, defaultCsvUri (+21 more)

### Community 16 - "M1 平台與接線｜safe_walk_navigation_controller"
Cohesion: 0.06
Nodes (29): cancel, _cancelled, cancelRoute, _clearRoute, dispose, _disposed, _failure, _generation (+21 more)

### Community 17 - "M1 平台與接線｜companion_speaker_adapter"
Cohesion: 0.06
Nodes (28): _active, available, cancel, _cancelled, CompanionTextPreviewMapper, _controller, dispose, _disposed (+20 more)

### Community 18 - "M3 介面｜safe_walk_emergency_view"
Cohesion: 0.07
Nodes (23): allowRealCalls, build, _CallButton, createState, icon, locating, mode, nearbyPointName (+15 more)

### Community 19 - "共用契約與模型｜safe_walk_contracts"
Cohesion: 0.07
Nodes (22): all, appEvent, areaStatistics, assistancePoint, companionEvent, companionScenario, ContractType, coordinates (+14 more)

### Community 20 - "M3 介面｜safe_walk_map_view 2"
Cohesion: 0.07
Nodes (27): DemoMap, _HomeMark, _PointMark, _StartMark, _Bubble, _AvoidBadge, _BottomBar, _Fact (+19 more)

### Community 21 - "M1 平台與接線｜nearby_alert_transport"
Cohesion: 0.08
Nodes (22): alertId, anonKey, baseUrl, _client, close, _closed, _config, createdAt (+14 more)

### Community 22 - "M3 介面｜safe_walk_home_view"
Cohesion: 0.08
Nodes (17): avoided, build, _ContextCard, createState, desc, destination, _FeatureRow, icon (+9 more)

### Community 23 - "M1 平台與接線｜supabase_connection"
Cohesion: 0.08
Nodes (21): SafeWalkSupabaseConfig, _activeClients, checkConnection, close, _closed, config, failure, _get (+13 more)

### Community 24 - "M4 安全資料｜README"
Cohesion: 0.09
Nodes (21): M2 Navigation Module (RouteService), M1 Platform Module (location, emergency, integration), Five-person Module Contract (SAFE_WALK_MODULES.md), safe_walk_navigation_scope (M3 wiring boundary), Supabase Setup (SAFE_WALK_SUPABASE.md), M3 Safe Walk UI/UX Module, SAFE_WALK_COLOR_SPEC.md, safe_walk_demo_data (mock) (+13 more)

### Community 25 - "M2 導航｜cancellable"
Cohesion: 0.10
Nodes (17): cancel, _cancelled, completer, isCancelled, ManualCancellation, pending, whenCancelled, _SpeechCancellation (+9 more)

### Community 26 - "共用契約與模型｜safe_walk_navigation_scope"
Cohesion: 0.09
Nodes (18): createRouteRequest, hasRoutingConsent, liveNavigationAvailable, maybeOf, mode, of, onCancelRoute, onDestinationChanged (+10 more)

### Community 27 - "M2 導航｜nearest_point"
Cohesion: 0.12
Nodes (15): age, checkedAt, clock, defaultMaxAvailabilityAge, distanceMeters, found, _isOpenNow, kinds (+7 more)

### Community 28 - "M1 平台與接線｜nearby_emergency_service"
Cohesion: 0.13
Nodes (14): fetchPendingAlerts, message, NearbyEmergencyBlock, NearbyEmergencyNotSent, NearbyEmergencyResult, NearbyEmergencySent, NearbyEmergencyService, _platform (+6 more)

### Community 29 - "M2 導航｜osrm_walking_route_provider"
Cohesion: 0.12
Nodes (14): _candidate, defaultEndpoint, distanceMeters, durationSeconds, endpoint, _fetch, findRoutes, _Leg (+6 more)

### Community 30 - "M5 陪伴｜companion_service"
Cohesion: 0.13
Nodes (13): LocalCompanionController, CompanionAudioAdapter, CompanionController, CompanionPlayback, completed, dispose, events, pause (+5 more)

### Community 31 - "M1 平台與接線｜tts_safe_walk_speaker"
Cohesion: 0.13
Nodes (12): CompanionTtsSpeaker, available, device, dispose, _emergencyStopped, _foreground, prepare, setForeground (+4 more)

### Community 32 - "M4 安全資料｜contract_safety_data"
Cohesion: 0.13
Nodes (10): m5CompanionScenarios, getAreaStatistics, getAssistancePoints, parseAreaStatistics, parseAssistancePoint, _points, _requireMock, _requireSemantics (+2 more)

### Community 33 - "M3 介面｜safe_walk_call_view 2"
Cohesion: 0.17
Nodes (11): _Incoming, _IncomingState, SafeWalkCallView, SafeWalkCallViewState, _SmsReportCard, _SmsReportCardState, _SafeWalkFlowState, _GoHomeCard (+3 more)

### Community 34 - "臺北通入口｜my_service_model"
Cohesion: 0.15
Nodes (11): category, description, destinationUrl, forceWebViewTitle, icon, MyServiceCategory, MyServiceCategoryExt, MyServiceIdExt (+3 more)

### Community 35 - "文件｜SAFE_WALK_SCHEMA"
Cohesion: 0.21
Nodes (13): GeoLocatorService.position(), Official Touchpoints Minimal-Intrusion Plan, M1 Platform (location, emergency, integration), M2 Navigation RouteService, contracts.schema.json (v1.0.0 canonical), Safe Walk JSON Schema and Dart Contracts, EmergencyActionResult (officialReceipt null), generate_safe_walk_contracts.dart Generator (+5 more)

### Community 36 - "M2 導航｜default_route_service"
Cohesion: 0.14
Nodes (9): _endpointProblem, _inputProblem, _latestCall, liveProvider, _lookupPoints, maxEndpointSnapMeters, mockProvider, planRoute (+1 more)

### Community 37 - "共用契約與模型｜safe_walk_models_generated"
Cohesion: 0.14
Nodes (14): AreaStatistics, AssistancePoint, CompanionEvent, CompanionScenario, CompanionStep, Coordinates, EmergencyActionResult, EmergencyOpenedPayload (+6 more)

### Community 38 - "M2 導航｜io_json_transport"
Cohesion: 0.15
Nodes (9): allowInsecureHttp, createDefaultJsonTransport, _exchange, getJson, maxBytes, postFormJson, _send, timeout (+1 more)

### Community 39 - "M1 平台與接線｜townpass_platform_adapter"
Cohesion: 0.15
Nodes (9): _failure, getCurrentPosition, locationTimeout, mockPosition, _readFromTownPass, _readPosition, requestEmergency, TownPassPositionReader (+1 more)

### Community 40 - "文件｜SAFE_WALK_NAVIGATION_PRESENTATION_CONTRACT"
Cohesion: 0.23
Nodes (10): M1/M2/M3 Navigation Wiring Spec, Planning-Intent Generation Check, Navigation Lifecycle Callbacks (opened/closed/emergencyOpened/destinationChanged), Live Entry Pre-open Acceptance, SafeWalkNavigationController, OSRM Walking Route Provider, Overpass Nearby Query, DefaultRouteService (+2 more)

### Community 41 - "M2 導航｜"
Cohesion: 0.20
Nodes (5): findRoutes, providerId, planRoute, getCurrentPosition, requestEmergency

### Community 42 - "文件｜AGENTS"
Cohesion: 0.22
Nodes (8): AGENTS.md Safe Walk Collaboration Rules, Git and Verification Rules, M1 TownPass Entry Integration Phase, Safe Walk TownPass Native Architecture Baseline, Legacy React Repo (csfishy/taipei-safe-walk), safe_walk Module Boundaries (platform/navigation/presentation/safety_data/companion/shared), Readable Contrast Pairs, Safe Walk Color Spec

### Community 43 - "文件｜SAFE_WALK_MODULES"
Cohesion: 0.20
Nodes (8): Five-Module File Ownership (M1-M5), DataMode mock/live Explicit Passing, Five-Person Module Contracts, M3 Presentation (sole UI/UX owner), M4 Safety Data Parser/Repository, M5 Companion Controller/Audio Adapter, AssistancePoint, CompanionEvent / CompanionScenario

### Community 44 - "M3 介面｜safe_walk_speaker"
Cohesion: 0.24
Nodes (7): available, PreviewSpeaker, SafeWalkSpeaker, speak, stop, _timer, UnavailableSpeaker

### Community 45 - "M2 導航｜consent"
Cohesion: 0.20
Nodes (8): ConsentRequiredException, toString, NearbyAlertException, SupabaseConfigurationException, SupabaseConnectionException, SafeWalkDataUnavailable, ViolentCrimeSourceUnavailable, ViolentCrimeFormatException

### Community 46 - "M1 平台與接線｜README"
Cohesion: 0.22
Nodes (10): GeoLocatorService (official TownPass), PlatformService, requestEmergency(), Shared safe_walk_models (sw), TownPassPlatformAdapter, companion_scenarios (generated from M5 JSON), Simulated Call View, Emergency View (110/119, SMS report) (+2 more)

### Community 47 - "M2 導航｜walking_route_provider"
Cohesion: 0.22
Nodes (8): MockWalkingRouteProvider, OsrmWalkingRouteProvider, AssistancePointLookup, findRoutes, toString, WalkingRouteNotFound, WalkingRouteProvider, WalkingRouteProviderUnavailable

### Community 48 - "M2 導航｜README"
Cohesion: 0.28
Nodes (8): DefaultRouteService, JSON Transport (HTTPS only, no new packages), MockWalkingRouteProvider, OsmConvenienceStoreSource, OsrmWalkingRouteProvider, RouteService.planRoute, SafeWalkCompositionRoot, SafeWalkNavigationController

### Community 49 - "M2 導航｜google_maps_link"
Cohesion: 0.25
Nodes (5): googleMapsWalkingUri, https, _pair, _requireValid, startNavigation

### Community 50 - "文件｜SAFE_WALK_INTEGRATION"
Cohesion: 0.29
Nodes (7): TPRoute / openUri, M1 TownPass Entry Integration, iPhone Device Acceptance Checklist, local://safe_walk -> TPRoute.safeWalk, Module Status Table (all Mock / unconfigured), MyServiceItemId.safeWalk, TownPass-self Home Card Alignment

### Community 51 - "文件｜SAFE_WALK_CI"
Cohesion: 0.25
Nodes (6): Codemagic Unsigned iOS Workflow, Safe Walk CI and Optional Cloud Builds, Safe Walk CI Workflow (safe_walk.yml), Safe Walk Initialization Record, Five Module Branches Pending, Initialization Verification Results (119/119 tests)

### Community 52 - "M2 導航｜README 2"
Cohesion: 0.29
Nodes (6): coordinate_math (haversine, lat/lng <-> GeoJSON), nearestPoints(), NearestStorePlanner, RouteFollower, RouteState, Map View (safe_walk_map_view / DemoMap)

### Community 53 - "M1 平台與接線｜safe_walk_route_speaker"
Cohesion: 0.29
Nodes (5): CompanionSpeakerAdapter, dispose, SafeWalkRouteSpeaker, stopForEmergency, TtsSafeWalkSpeaker

### Community 54 - "M4 安全資料｜safety_data_service"
Cohesion: 0.29
Nodes (6): ContractSafetyDataParser, getAreaStatistics, getAssistancePoints, parseAreaStatistics, parseAssistancePoint, SafetyDataParser

### Community 55 - "M4 安全資料｜get_connect_text_fetcher"
Cohesion: 0.33
Nodes (3): connect, getConnectTextFetcher, redecodeLatin1AsUtf8

### Community 56 - "M1 平台與接線｜safe_walk_composition_root 2"
Cohesion: 0.33
Nodes (6): SafeWalkCompositionRoot, _SafeWalkCompositionRootState, PlatformService, TownPassPlatformAdapter, MockSafetyDataRepository, SafetyDataRepository

### Community 57 - "M3 介面｜safe_walk_card_assets"
Cohesion: 0.33
Nodes (5): d, id, opacity, swCardArtSvg, swCardNavigationSvg

### Community 58 - "文件｜SAFE_WALK_COMPETITION_LICENSE"
Cohesion: 0.40
Nodes (5): TPWebView flutterObject {name,data} Bridge, 2026 Fall Codefest Rules (115.08.27), Delivery Form Unconfirmed (native vs WebView), Competition Delivery and License Pending Items, GPLv3 Upstream vs AGPLv3 Team Results

### Community 59 - "文件｜SAFE_WALK_SUPABASE"
Cohesion: 0.60
Nodes (4): SafeWalkSupabaseConfig, SupabaseConnection.checkConnection probe, TownPass Supabase Connection Setup, SupabaseNearbyAlertTransport

### Community 60 - "M5 陪伴｜companion_state"
Cohesion: 0.40
Nodes (3): CompanionAction, current, nextCompanionState

### Community 62 - "共用契約與模型｜safe_walk_models_generated 2"
Cohesion: 0.40
Nodes (5): AppEvent, CompanionChangedEvent, EmergencyOpenedEvent, LocationUpdatedEvent, RouteCompletedEvent

### Community 65 - "共用契約與模型｜safe_walk_models_generated 3"
Cohesion: 0.67
Nodes (3): ConfirmedRecognition, Recognition, UnconfirmedRecognition

### Community 66 - "共用契約與模型｜safe_walk_models_generated 4"
Cohesion: 0.67
Nodes (3): LocationFailure, LocationResult, LocationSuccess

## Knowledge Gaps
- **1040 isolated node(s):** `_MilestoneResult`, `CompanionAssetResolver`, `CompanionClock`, `CompanionDelay`, `_audio` (+1035 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 1189 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **7 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `SafeWalkFlow` connect `M1 平台與接線｜README` to `M3 介面｜safe_walk_call_view 2`, `文件｜SAFE_WALK_SCHEMA`, `文件｜SAFE_WALK_NAVIGATION_PRESENTATION_CONTRACT`, `M3 介面｜safe_walk_flow`, `M2 導航｜README`, `文件｜SAFE_WALK_INTEGRATION`, `M2 導航｜README 2`, `M1 平台與接線｜safe_walk_composition_root 2`?**
  _High betweenness centrality (0.095) - this node is a cross-community bridge._
- **What connects `_MilestoneResult`, `CompanionAssetResolver`, `CompanionClock` to the rest of the system?**
  _1040 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `M3 介面｜safe_walk_map_view` be split into smaller, more focused modules?**
  _Cohesion score 0.02197802197802198 - nodes in this community are weakly interconnected._
- **Why does `SafeWalkModel` connect `共用契約與模型｜safe_walk_models_generated` to `共用契約與模型｜safe_walk_models_generated 3`, `共用契約與模型｜safe_walk_models_generated 4`, `M1 平台與接線｜townpass_platform_adapter`, `M1 平台與接線｜safe_walk_navigation_controller`, `共用契約與模型｜safe_walk_models_generated 2`?**
  _High betweenness centrality (0.043) - this node is a cross-community bridge._
- **Should `其他｜` be split into smaller, more focused modules?**
  _Cohesion score 0.02564102564102564 - nodes in this community are weakly interconnected._
- **Why does `Five-Person Module Contracts` connect `文件｜SAFE_WALK_MODULES` to `文件｜SAFE_WALK_SCHEMA`, `文件｜AGENTS`, `文件｜SAFE_WALK_CI`, `M2 導航｜cancellable`?**
  _High betweenness centrality (0.031) - this node is a cross-community bridge._
- **Should `M4 安全資料｜violent_crime_normalizer` be split into smaller, more focused modules?**
  _Cohesion score 0.02702702702702703 - nodes in this community are weakly interconnected._
