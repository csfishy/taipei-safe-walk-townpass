import 'package:flutter/widgets.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// In-process M1 -> M3 wiring; all route payloads remain canonical shared models.
/// Creating a request neither reads GPS nor sends coordinates to a provider.
typedef SafeWalkRouteRequestBuilder = sw.RouteRequest Function({
  required sw.Position origin,
  required sw.Coordinates destination,
  sw.RouteKind? preference,
  int? maxExtraDistanceMeters,
  List<String>? assistancePointIds,
});

/// M1 publishes this boundary around M3's existing flow without changing its UI.
/// M3 must consume the state and invoke lifecycle callbacks before Live is ready.
class SafeWalkNavigationScope extends InheritedWidget {
  const SafeWalkNavigationScope({
    super.key,
    required this.mode,
    required this.liveNavigationAvailable,
    required this.hasRoutingConsent,
    required this.routeResult,
    required this.routeLoading,
    required this.routeError,
    required this.createRouteRequest,
    required this.onPlanRoute,
    required this.onCancelRoute,
    required this.onRoutingConsentChanged,
    required this.onDestinationChanged,
    required this.onNavigationOpened,
    required this.onNavigationClosed,
    required this.onEmergencyOpened,
    required super.child,
  });

  final sw.DataMode mode;
  final bool liveNavigationAvailable;
  final bool hasRoutingConsent;
  final sw.RouteResult? routeResult;
  final bool routeLoading;
  final String? routeError;
  final SafeWalkRouteRequestBuilder createRouteRequest;
  final Future<void> Function(sw.RouteRequest request) onPlanRoute;
  final VoidCallback onCancelRoute;
  final ValueChanged<bool> onRoutingConsentChanged;

  /// Invoke before changing selection, including selecting an assistance point.
  final VoidCallback onDestinationChanged;

  /// Invoke only on an explicit user entry to navigation; never auto-resume.
  final VoidCallback onNavigationOpened;

  /// Invoke when leaving navigation, including entering call/home screens.
  final VoidCallback onNavigationClosed;

  /// Invoke on entering SOS, before any asynchronous work or channel selection.
  final VoidCallback onEmergencyOpened;

  static SafeWalkNavigationScope of(BuildContext context) {
    final scope = maybeOf(context);
    assert(scope != null, 'SafeWalkNavigationScope requires M1 composition');
    return scope!;
  }

  /// Standalone M3 previews can remain explicitly Mock without M1 composition.
  static SafeWalkNavigationScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SafeWalkNavigationScope>();

  @override
  bool updateShouldNotify(SafeWalkNavigationScope oldWidget) =>
      mode != oldWidget.mode ||
      liveNavigationAvailable != oldWidget.liveNavigationAvailable ||
      hasRoutingConsent != oldWidget.hasRoutingConsent ||
      routeResult != oldWidget.routeResult ||
      routeLoading != oldWidget.routeLoading ||
      routeError != oldWidget.routeError ||
      createRouteRequest != oldWidget.createRouteRequest ||
      onPlanRoute != oldWidget.onPlanRoute ||
      onCancelRoute != oldWidget.onCancelRoute ||
      onRoutingConsentChanged != oldWidget.onRoutingConsentChanged ||
      onDestinationChanged != oldWidget.onDestinationChanged ||
      onNavigationOpened != oldWidget.onNavigationOpened ||
      onNavigationClosed != oldWidget.onNavigationClosed ||
      onEmergencyOpened != oldWidget.onEmergencyOpened;
}
