import 'dart:convert';

/// Reads JWT payload claims; it never verifies signatures.
abstract final class Claims {
  /// The home landscape claim name.
  static const String homeLandscape = 'home_landscape';

  /// Decodes a JWT payload; an invalid token gives an empty map.
  static Map<String, Object?> decode(String jwt) {
    final List<String> parts = jwt.split('.');
    if (parts.length < 2) {
      return const <String, Object?>{};
    }
    try {
      final String normalized = base64Url.normalize(parts[1]);
      final Object? decoded = jsonDecode(
        utf8.decode(base64Url.decode(normalized)),
      );
      if (decoded is! Map) {
        return const <String, Object?>{};
      }
      return decoded.map<String, Object?>(
        (Object? key, Object? value) => MapEntry(key.toString(), value),
      );
    } on Object {
      return const <String, Object?>{};
    }
  }

  /// The registration claim key: `<platform>_<service>`, lowercased, `-` as `_`.
  static String registrationKey({
    required String platform,
    required String service,
  }) {
    String normalize(String label) => label.toLowerCase().replaceAll('-', '_');
    return '${normalize(platform)}_${normalize(service)}';
  }

  /// Whether [claims] hold the registration claim as the string `"true"`.
  static bool hasRegistration(
    Map<String, Object?> claims, {
    required String platform,
    required String service,
  }) {
    final Object? value =
        claims[registrationKey(platform: platform, service: service)];
    return value is String && value == 'true';
  }

  /// The `home_landscape` claim value, or `null` when absent/blank.
  static String? home(Map<String, Object?> claims) {
    final Object? value = claims[homeLandscape];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    return null;
  }
}
