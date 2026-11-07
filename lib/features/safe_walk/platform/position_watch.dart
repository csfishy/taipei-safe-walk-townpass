import 'package:geolocator/geolocator.dart' as geo;
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// Continuous device positions for route following. Only listen while the map
/// is open in the foreground, after the user has already shared a position;
/// cancelling the subscription stops the GPS. Mocked or inaccurate fixes are
/// dropped here; RouteFollower applies the finer checks.
Stream<sw.Position> watchDevicePosition() =>
    geo.Geolocator.getPositionStream(
          locationSettings: const geo.LocationSettings(
            accuracy: geo.LocationAccuracy.high,
            distanceFilter: 5,
          ),
        )
        .where((p) => !p.isMocked && p.hasAccuracy && p.accuracy <= 100)
        .map(
          (p) => sw.Position(
            coordinates: sw.Coordinates(lat: p.latitude, lng: p.longitude),
            source: sw.PositionSource.gps,
            accuracyMeters: p.accuracy,
            observedAt: p.timestamp.toUtc().toIso8601String(),
          ),
        );
