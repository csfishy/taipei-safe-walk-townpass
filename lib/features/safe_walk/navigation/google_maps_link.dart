import 'package:town_pass/features/safe_walk/navigation/coordinate_math.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// A Google Maps "Maps URL" that starts walking directions to [destination].
///
/// On a phone with Google Maps installed an `https://www.google.com/maps/dir/`
/// link opens the app; otherwise it opens the website. Open it from an
/// explicit user tap, with an external-application launch mode (M3/M1 own the
/// button and `url_launcher`).
///
/// By default there is no `origin`: Google Maps then starts from the user's
/// current location at the moment they open it, which is more accurate than
/// the position we had when we built the link, and our URL never contains the
/// user's location. Pass [origin] only when the route must start somewhere
/// else; that puts the coordinates in a link that leaves the app.
///
/// `dir_action=navigate` asks Google Maps to start turn-by-turn straight away
/// instead of showing the route preview.
Uri googleMapsWalkingUri({
  required sw.Coordinates destination,
  sw.Coordinates? origin,
  bool startNavigation = true,
}) {
  _requireValid(destination, 'destination');
  if (origin != null) _requireValid(origin, 'origin');
  return Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'destination': _pair(destination),
    'origin': ?(origin == null ? null : _pair(origin)),
    'travelmode': 'walking',
    if (startNavigation) 'dir_action': 'navigate',
  });
}

String _pair(sw.Coordinates c) =>
    '${c.lat.toStringAsFixed(6)},${c.lng.toStringAsFixed(6)}';

void _requireValid(sw.Coordinates c, String name) {
  if (!isValidLatLng(c.lat, c.lng)) {
    throw ArgumentError.value(name, name, 'is not a valid coordinate');
  }
}
