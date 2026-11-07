/// The user has not agreed to send their location to an outside service.
/// Internal signal; the route payload reports it as `provider_unavailable`.
///
/// M1 owns the consent prompt and passes the answer in as a `hasConsent`
/// callback, so it is read again on every request and can be withdrawn.
final class ConsentRequiredException implements Exception {
  const ConsentRequiredException();

  @override
  String toString() => 'User consent is required before contacting the service';
}
