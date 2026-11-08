import 'dart:io';

import 'package:town_pass/features/safe_walk/platform/supabase/safe_walk_supabase_config.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// An alert that a trusted backend has authorized this recipient to read.
/// Sender consent alone does not establish recipient eligibility or ownership.
final class NearbyAlert {
  const NearbyAlert({
    required this.alertId,
    this.senderId,
    required this.location,
    required this.radiusMeters,
    required this.createdAt,
    this.fromContact = false,
    this.senderName,
  });

  final String alertId;

  /// True when this came from someone who paired with this person as a trusted
  /// contact; [senderName] is then the name that person chose. For a nearby
  /// helper both stay empty: the sender is never revealed.
  final bool fromContact;
  final String? senderName;

  /// The authenticated backend never reveals who sent an alert, so this is
  /// null there. Only legacy/fake transports may supply a value.
  final String? senderId;
  final sw.Coordinates location;
  final int radiusMeters;
  final DateTime createdAt;
}

final class NearbyAlertException implements Exception {
  const NearbyAlertException(this.message);
  final String message;
  @override
  String toString() => 'NearbyAlertException: $message';
}

/// Backend seam for nearby helper alerts. Implementations must never log or
/// put coordinates in a URL.
abstract interface class NearbyAlertTransport {
  Future<void> setHelperOptIn({
    required String helperId,
    required bool enabled,
    sw.Coordinates? location,
  });

  /// Returns the backend's accepted recipient count, not proof of delivery.
  Future<int> sendEmergencyAlert({
    required String senderId,
    required sw.Coordinates location,
    required int radiusMeters,
  });

  /// Returns alerts addressed to the caller that are still valid. Results may
  /// repeat across calls; callers de-duplicate by [NearbyAlert.alertId].
  Future<List<NearbyAlert>> fetchPendingAlerts(String helperId);
}

/// Marks a backend that must be rejected before collecting location.
/// This exposes a failure reason, never a client-controlled authorization flag.
abstract interface class UnavailableNearbyAlertBackend {
  String get unavailableReason;
}

/// For transports whose readiness depends on runtime state, such as a signed-in
/// session. Returns null only when the backend can currently be used. It is
/// derived from verified state and is never a client-settable flag.
abstract interface class NearbyAlertAvailability {
  String? get currentUnavailableReason;
}

/// How an invite code was received.
enum NearbyInviteResult {
  /// Paired: this person is now the other's trusted contact.
  paired,

  /// Wrong, expired or already used.
  invalid,

  /// It was this person's own code.
  self,

  /// The inviter already has the most contacts allowed.
  ownerFull,

  /// This person already follows the most people allowed.
  followingFull,
}

/// A one-time code for pairing a trusted contact. Shown once; the backend keeps
/// only a hash.
final class NearbyContactInvite {
  const NearbyContactInvite({required this.code, required this.expiresAt});
  final String code;
  final DateTime expiresAt;
}

/// One of this person's own trusted contacts. Who they are is not revealed.
final class NearbyContactLink {
  const NearbyContactLink({required this.id, required this.since});
  final String id;
  final DateTime since;
}

/// Someone this person is a trusted contact of, by the name they chose.
final class NearbyFollowing {
  const NearbyFollowing({
    required this.id,
    required this.name,
    required this.since,
  });
  final String id;
  final String name;
  final DateTime since;
}

/// At most this many trusted contacts per person.
const nearbyContactMax = 5;

/// The longest name a person can show their contacts, in characters.
const nearbyContactNameMax = 20;

/// Normalizes a typed invite code (case, spaces and dashes are ignored). Null
/// when it cannot be a code, so nothing is sent to the backend.
String? normalizeNearbyInviteCode(String raw) {
  final code = raw.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
  return RegExp(r'^[A-HJKMNP-Z2-9]{8}$').hasMatch(code) ? code : null;
}

/// Optional capability: transports that can pair trusted contacts. When a person
/// sends an SOS their contacts are notified in the app whatever the distance.
abstract interface class NearbyTrustedContacts {
  Future<NearbyContactInvite> createContactInvite(String displayName);
  Future<NearbyInviteResult> acceptContactInvite(String code);
  Future<List<NearbyContactLink>> listMyContacts();
  Future<void> removeContact(String linkId);
  Future<List<NearbyFollowing>> listFollowing();
  Future<void> unfollow(String linkId);
}

/// Optional capability: bring back an identity that already exists on this
/// phone, without ever creating one. True when one is ready to use.
abstract interface class NearbyIdentityRestore {
  Future<bool> restoreExistingIdentity();
}

/// Optional capability for transports that must do async work (such as
/// creating an anonymous identity) before they can be used. The service awaits
/// it before reading the person's location, so a backend that turns out to be
/// unusable never costs a location read.
abstract interface class NearbyAlertPreparation {
  /// Null when ready, otherwise why the backend cannot be used.
  Future<String?> prepare();
}

/// A place where a helper asks to be notified about an SOS even when their live
/// position is unknown. The backend rounds [center] to about 100 m.
final class NearbyGuardArea {
  const NearbyGuardArea({required this.center, required this.radiusMeters});
  final sw.Coordinates center;
  final int radiusMeters;
}

/// Radii a helper can choose for a guard area, in metres.
const nearbyGuardAreaRadii = [500, 1000];

/// At most this many guard areas per helper.
const nearbyGuardAreaMax = 3;

/// Optional capability: transports whose backend stores guard areas.
abstract interface class NearbyHelperAreas {
  Future<List<NearbyGuardArea>> fetchGuardAreas();

  /// Replaces all of the caller's guard areas with [areas] (at most
  /// [nearbyGuardAreaMax]).
  Future<void> replaceGuardAreas(List<NearbyGuardArea> areas);
}

/// Why [transport] cannot be used right now, or null when it can. Callers use
/// this to refuse before collecting location.
String? nearbyBackendUnavailableReason(NearbyAlertTransport transport) {
  if (transport is UnavailableNearbyAlertBackend) {
    return (transport as UnavailableNearbyAlertBackend).unavailableReason;
  }
  if (transport is NearbyAlertAvailability) {
    return (transport as NearbyAlertAvailability).currentUnavailableReason;
  }
  return null;
}

/// Production placeholder with no credentials, identity, or network client.
final class UnavailableNearbyAlertTransport
    implements NearbyAlertTransport, UnavailableNearbyAlertBackend {
  const UnavailableNearbyAlertTransport();

  @override
  String get unavailableReason =>
      SupabaseNearbyAlertTransport.backendUnavailableReason;

  @override
  Future<void> setHelperOptIn({
    required String helperId,
    required bool enabled,
    sw.Coordinates? location,
  }) async => throw NearbyAlertException(unavailableReason);

  @override
  Future<int> sendEmergencyAlert({
    required String senderId,
    required sw.Coordinates location,
    required int radiusMeters,
  }) async => throw NearbyAlertException(unavailableReason);

  @override
  Future<List<NearbyAlert>> fetchPendingAlerts(String helperId) async =>
      throw NearbyAlertException(unavailableReason);
}

/// Retired anonymous RPC transport, retained for configuration compatibility.
///
/// A publishable/anonymous key and a caller-supplied UUID do not authenticate a
/// person or establish recipient eligibility. All operations fail closed until
/// a separately reviewed authenticated backend replaces this implementation.
/// No environment flag, API key, or consent boolean enables network requests.
final class SupabaseNearbyAlertTransport
    implements NearbyAlertTransport, UnavailableNearbyAlertBackend {
  SupabaseNearbyAlertTransport({
    required Uri baseUrl,
    required String anonKey,
    HttpClient? client,
    bool allowInsecureLocalhost = false,
  }) : this.fromConfig(
         SafeWalkSupabaseConfig(
           url: baseUrl,
           apiKey: anonKey,
           allowInsecureLocalhost: allowInsecureLocalhost,
         ),
         client: client,
       );

  SupabaseNearbyAlertTransport.fromConfig(this._config, {this._client});

  factory SupabaseNearbyAlertTransport.fromEnvironment() =>
      SupabaseNearbyAlertTransport.fromConfig(
        SafeWalkSupabaseConfig.fromEnvironment(),
      );

  final SafeWalkSupabaseConfig _config;
  Uri get baseUrl => _config.url;
  String get anonKey => _config.apiKey;
  final HttpClient? _client;
  bool _closed = false;

  static const backendUnavailableReason =
      '附近通知尚未具備可信身分與接收資格驗證，目前無法使用；請使用電話或緊急聯絡人求助';

  @override
  String get unavailableReason => backendUnavailableReason;

  @override
  Future<void> setHelperOptIn({
    required String helperId,
    required bool enabled,
    sw.Coordinates? location,
  }) async {
    _rejectUnavailable();
  }

  @override
  Future<int> sendEmergencyAlert({
    required String senderId,
    required sw.Coordinates location,
    required int radiusMeters,
  }) async {
    _rejectUnavailable();
  }

  @override
  Future<List<NearbyAlert>> fetchPendingAlerts(String helperId) async {
    _rejectUnavailable();
  }

  Never _rejectUnavailable() {
    if (_closed) {
      throw const NearbyAlertException('Backend transport is closed');
    }
    throw const NearbyAlertException(backendUnavailableReason);
  }

  /// The creator owns this transport and must close it after use.
  void close() {
    if (_closed) return;
    _closed = true;
    _client?.close(force: true);
  }
}
