import 'package:flutter/foundation.dart';

/// Explicit native preview build setting. The backend owns the test deadline.
/// Web builds and builds without the setting never select email test identity.
const emailLiveTestBuild =
    !kIsWeb && bool.fromEnvironment('SAFE_WALK_EMAIL_LIVE_TEST');
