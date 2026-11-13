import 'package:geolocator/geolocator.dart' as geo;
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// One foreground position stream for map ranges and optional route guidance.
/// Listen after a user-initiated map entry obtains location permission;
/// cancelling stops GPS. Reporting applies its stricter accuracy/freshness
/// checks separately from navigation. Mocked or inaccurate fixes are dropped.
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
