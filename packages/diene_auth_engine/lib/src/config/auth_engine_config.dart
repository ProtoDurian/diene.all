import 'package:meta/meta.dart';

/// Fixed app-handoff constants; not config knobs.
abstract final class AppHandoffConstants {
  /// Nonce lifetime: 15 minutes.
  static const Duration nonceTtl = Duration(minutes: 15);

  /// Logto one-time token lifetime: exactly 120 seconds.
  static const int oneTimeTokenExpiresInSeconds = 120;

  /// The default mount; hosts may configure another.
  static const String defaultMount = '/app-handoff';
}

/// The engine-owned `authEngine` config block and its schema.
///
/// The issuer is baked build-time config, never read from a document.
@immutable
final class AuthEngineConfig {
  const AuthEngineConfig({
    required this.issuer,
    required this.endpoint,
    required this.appId,
    required this.redirectUri,
    required this.scopes,
    this.postLogoutRedirectUri,
    this.appHandoffMount = AppHandoffConstants.defaultMount,
    this.endpointSuffixAllowlist = const <String>['cluster.atomi.cloud'],
  });

  /// Parses and validates the merged `authEngine` block.
  factory AuthEngineConfig.fromBlock(Map<String, Object?> block) {
    Uri uri(String key) {
      final Object? value = block[key];
      if (value == null) {
        throw FormatException('authEngine.$key is required');
      }
      if (value is! String || value.isEmpty) {
        throw FormatException('authEngine.$key must be a non-empty URI string');
      }
      final Uri parsed = Uri.parse(value);
      if (!parsed.hasScheme) {
        throw FormatException('authEngine.$key must be an absolute URI', value);
      }
      return parsed;
    }

    String str(String key) {
      final Object? value = block[key];
      if (value is! String || value.isEmpty) {
        throw FormatException('authEngine.$key must be a non-empty string');
      }
      return value;
    }

    final Object? rawScopes = block['scopes'];
    final List<String> scopes = rawScopes is List
        ? rawScopes.map((Object? s) => s.toString()).toList(growable: false)
        : const <String>['openid', 'offline_access'];

    final Object? rawAllow = block['endpointSuffixAllowlist'];
    final List<String> allow = rawAllow is List && rawAllow.isNotEmpty
        ? rawAllow.map((Object? s) => s.toString()).toList(growable: false)
        : const <String>['cluster.atomi.cloud'];

    final Object? mount = block['appHandoffMount'];
    final String mountPath = mount is String && mount.isNotEmpty
        ? mount
        : AppHandoffConstants.defaultMount;
    if (!mountPath.startsWith('/')) {
      throw FormatException('authEngine.appHandoffMount must begin with "/"');
    }

    final Object? postLogout = block['postLogoutRedirectUri'];

    return AuthEngineConfig(
      issuer: uri('issuer'),
      endpoint: uri('endpoint'),
      appId: str('appId'),
      redirectUri: uri('redirectUri'),
      postLogoutRedirectUri: postLogout is String && postLogout.isNotEmpty
          ? Uri.parse(postLogout)
          : null,
      scopes: scopes,
      appHandoffMount: mountPath,
      endpointSuffixAllowlist: allow,
    );
  }

  final Uri issuer;

  final Uri endpoint;

  final String appId;

  final Uri redirectUri;

  final Uri? postLogoutRedirectUri;

  final List<String> scopes;

  /// The app-handoff mount, default `/app-handoff`.
  final String appHandoffMount;

  /// Host suffixes every document-sourced URL must end with.
  final List<String> endpointSuffixAllowlist;

  /// `{mount}/redeem`, never a doubled `app-handoff` segment.
  String get redeemPath => '$appHandoffMount/redeem';

  /// Whether the host of [url] matches the suffix allowlist.
  bool allowsUrl(Uri url) {
    final String host = url.host;
    return endpointSuffixAllowlist.any(
      (String suffix) => host == suffix || host.endsWith('.$suffix'),
    );
  }

  /// The block schema the `config` package composes into the root schema.
  static Map<String, Object?> get blockSchema => <String, Object?>{
    r'$id': 'authEngine',
    'type': 'object',
    'required': <String>['issuer', 'endpoint', 'appId', 'redirectUri'],
    'properties': <String, Object?>{
      'issuer': <String, Object?>{'type': 'string', 'format': 'uri'},
      'endpoint': <String, Object?>{'type': 'string', 'format': 'uri'},
      'appId': <String, Object?>{'type': 'string'},
      'redirectUri': <String, Object?>{'type': 'string', 'format': 'uri'},
      'postLogoutRedirectUri': <String, Object?>{
        'type': 'string',
        'format': 'uri',
      },
      'scopes': <String, Object?>{
        'type': 'array',
        'items': <String, Object?>{'type': 'string'},
      },
      'appHandoffMount': <String, Object?>{
        'type': 'string',
        'default': AppHandoffConstants.defaultMount,
      },
      'endpointSuffixAllowlist': <String, Object?>{
        'type': 'array',
        'items': <String, Object?>{'type': 'string'},
      },
    },
  };
}
