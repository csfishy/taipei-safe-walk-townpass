import 'dart:convert';

enum SupabaseConfigurationFailure {
  missingUrl,
  invalidUrl,
  missingKey,
  invalidKey,
}

/// Configuration errors never retain the rejected URL or credential.
final class SupabaseConfigurationException implements Exception {
  const SupabaseConfigurationException(this.failure);

  final SupabaseConfigurationFailure failure;

  @override
  String toString() => 'Supabase configuration failed: ${failure.name}';
}

enum SupabaseClientKeyKind { publishable, legacyAnon }

/// Public client configuration, independent of TownPass login or data mode.
/// A legacy JWT's role is inspected locally; Supabase verifies its signature.
final class SafeWalkSupabaseConfig {
  factory SafeWalkSupabaseConfig({
    required Uri url,
    required String apiKey,
    bool allowInsecureLocalhost = false,
  }) {
    _validateUrl(url, allowInsecureLocalhost);
    final key = apiKey.trim();
    if (key.isEmpty) {
      throw const SupabaseConfigurationException(
        SupabaseConfigurationFailure.missingKey,
      );
    }
    return SafeWalkSupabaseConfig._(url.replace(path: ''), key, _keyKind(key));
  }

  const SafeWalkSupabaseConfig._(this.url, this.apiKey, this.keyKind);

  /// Reads compile-time dart-defines by default. An explicit map supports
  /// deterministic configuration tests without changing process globals.
  factory SafeWalkSupabaseConfig.fromEnvironment({
    Map<String, String>? environment,
  }) {
    final values =
        environment ??
        const {
          'SUPABASE_URL': String.fromEnvironment('SUPABASE_URL'),
          'SUPABASE_PUBLISHABLE_KEY': String.fromEnvironment(
            'SUPABASE_PUBLISHABLE_KEY',
          ),
          'SUPABASE_ANON_KEY': String.fromEnvironment('SUPABASE_ANON_KEY'),
        };
    final rawUrl = (values['SUPABASE_URL'] ?? '').trim();
    if (rawUrl.isEmpty) {
      throw const SupabaseConfigurationException(
        SupabaseConfigurationFailure.missingUrl,
      );
    }
    final url = Uri.tryParse(rawUrl);
    if (url == null) {
      throw const SupabaseConfigurationException(
        SupabaseConfigurationFailure.invalidUrl,
      );
    }
    final publishable = (values['SUPABASE_PUBLISHABLE_KEY'] ?? '').trim();
    final config = SafeWalkSupabaseConfig(
      url: url,
      apiKey: publishable.isNotEmpty
          ? publishable
          : (values['SUPABASE_ANON_KEY'] ?? ''),
    );
    // The preferred variable accepts only the new publishable key format.
    if (publishable.isNotEmpty &&
        config.keyKind != SupabaseClientKeyKind.publishable) {
      throw const SupabaseConfigurationException(
        SupabaseConfigurationFailure.invalidKey,
      );
    }
    // The compatibility variable accepts only an anon JWT, never a secret key.
    if (publishable.isEmpty &&
        config.keyKind != SupabaseClientKeyKind.legacyAnon) {
      throw const SupabaseConfigurationException(
        SupabaseConfigurationFailure.invalidKey,
      );
    }
    return config;
  }

  final Uri url;
  final String apiKey;
  final SupabaseClientKeyKind keyKind;

  /// Publishable keys are API keys, not bearer JWTs.
  Map<String, String> get requestHeaders => {
    'apikey': apiKey,
    if (keyKind == SupabaseClientKeyKind.legacyAnon)
      'Authorization': 'Bearer $apiKey',
  };

  @override
  String toString() => 'SafeWalkSupabaseConfig(configured)';

  static void _validateUrl(Uri url, bool allowInsecureLocalhost) {
    const loopbackHosts = {'localhost', '127.0.0.1', '::1'};
    try {
      final permittedScheme =
          url.scheme == 'https' ||
          (allowInsecureLocalhost &&
              url.scheme == 'http' &&
              loopbackHosts.contains(url.host));
      if (!permittedScheme ||
          !url.hasAuthority ||
          url.host.isEmpty ||
          url.userInfo.isNotEmpty ||
          (url.path.isNotEmpty && url.path != '/') ||
          url.hasQuery ||
          url.hasFragment ||
          url.port < 1 ||
          url.port > 65535) {
        throw const SupabaseConfigurationException(
          SupabaseConfigurationFailure.invalidUrl,
        );
      }
    } on FormatException {
      throw const SupabaseConfigurationException(
        SupabaseConfigurationFailure.invalidUrl,
      );
    }
  }

  static SupabaseClientKeyKind _keyKind(String key) {
    if (RegExp(r'^sb_publishable_[A-Za-z0-9_-]+$').hasMatch(key)) {
      return SupabaseClientKeyKind.publishable;
    }
    try {
      final parts = key.split('.');
      if (parts.length == 3 &&
          parts.every(
            (part) =>
                part.isNotEmpty && RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(part),
          )) {
        final header = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[0]))),
        );
        final payload = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
        );
        if (header is Map &&
            header['alg'] == 'HS256' &&
            payload is Map &&
            payload['role'] == 'anon') {
          return SupabaseClientKeyKind.legacyAnon;
        }
      }
    } on FormatException {
      // The fixed error below deliberately discards rejected credential text.
    }
    throw const SupabaseConfigurationException(
      SupabaseConfigurationFailure.invalidKey,
    );
  }
}
