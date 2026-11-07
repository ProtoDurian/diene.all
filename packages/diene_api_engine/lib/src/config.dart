import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// The landscape/platform/service/module coordinate of one backend.
@immutable
class LpsmCoordinate {
  const LpsmCoordinate({
    required this.landscape,
    required this.platform,
    required this.service,
    required this.module,
  });

  factory LpsmCoordinate.fromMap(Map<String, Object?> value) => LpsmCoordinate(
    landscape: _string(value, 'landscape'),
    platform: _string(value, 'platform'),
    service: _string(value, 'service'),
    module: _string(value, 'module'),
  );

  final String landscape;
  final String platform;
  final String service;
  final String module;

  /// Stable registry key.
  String get key => '$landscape.$platform.$service.$module';

  Map<String, Object?> toMap() => <String, Object?>{
    'landscape': landscape,
    'platform': platform,
    'service': service,
    'module': module,
  };

  @override
  bool operator ==(Object other) => other is LpsmCoordinate && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => key;
}

/// One backend: one base URL host and its own auth resource.
@immutable
class BackendConfig {
  const BackendConfig({
    required this.coordinate,
    required this.baseUrl,
    this.resourceName,
    this.timeout = const Duration(seconds: 30),
    this.retryOnNetworkError = true,
  });

  factory BackendConfig.fromMap(Map<String, Object?> value) => BackendConfig(
    coordinate: LpsmCoordinate.fromMap(_map(value, 'coordinate')),
    baseUrl: Uri.parse(_string(value, 'baseUrl')),
    resourceName: value['resourceName'] as String?,
    timeout: Duration(
      seconds: (value['timeoutSeconds'] as num?)?.toInt() ?? 30,
    ),
    retryOnNetworkError: value['retryOnNetworkError'] as bool? ?? true,
  );

  final LpsmCoordinate coordinate;
  final Uri baseUrl;

  /// Resource name for the `IAuth` token; null sends no bearer token.
  final String? resourceName;
  final Duration timeout;
  final bool retryOnNetworkError;
}

/// Baked rescue settings; no document can change them.
@immutable
class RescueConfig {
  const RescueConfig({
    required this.enabled,
    required this.issuer,
    required this.catalogHosts,
    required this.endpointSuffixAllowlist,
    this.scanBudget = const Duration(seconds: 8),
    this.perCandidateTimeout = const Duration(seconds: 3),
    this.maxJitter = const Duration(milliseconds: 250),
  });

  factory RescueConfig.fromMap(Map<String, Object?> value) => RescueConfig(
    enabled: value['enabled'] as bool? ?? false,
    issuer: Uri.parse(_string(value, 'issuer')),
    catalogHosts: _stringList(value, 'catalogHosts'),
    endpointSuffixAllowlist: _stringList(value, 'endpointSuffixAllowlist'),
    scanBudget: Duration(
      milliseconds: (value['scanBudgetMs'] as num?)?.toInt() ?? 8000,
    ),
    perCandidateTimeout: Duration(
      milliseconds: (value['perCandidateTimeoutMs'] as num?)?.toInt() ?? 3000,
    ),
    maxJitter: Duration(
      milliseconds: (value['maxJitterMs'] as num?)?.toInt() ?? 250,
    ),
  );

  /// Per-context flag; when false the router never runs.
  final bool enabled;

  /// The auth issuer: always baked, never read from a document.
  final Uri issuer;

  /// Baked hosts Doc A is fetched from, spread over failure domains.
  final List<String> catalogHosts;

  /// Host suffixes every document-sourced URL must match at use time.
  final List<String> endpointSuffixAllowlist;

  final Duration scanBudget;
  final Duration perCandidateTimeout;
  final Duration maxJitter;
}

/// The engine-owned config block: backends plus rescue.
@immutable
class ApiEngineConfig {
  const ApiEngineConfig({required this.backends, required this.rescue});

  /// Parses a merged config slice; throws [FormatException] when invalid.
  factory ApiEngineConfig.fromMap(Map<String, Object?> value) {
    final List<Object?> raw = _list(value, 'backends');
    final List<BackendConfig> backends = raw
        .map(
          (Object? item) => BackendConfig.fromMap(_asMap(item, 'backends[]')),
        )
        .toList(growable: false);
    if (backends.isEmpty) {
      throw const FormatException('api-engine config needs ≥1 backend');
    }
    final Set<String> keys = <String>{};
    for (final BackendConfig backend in backends) {
      if (!keys.add(backend.coordinate.key)) {
        throw FormatException(
          'duplicate backend registration: ${backend.coordinate.key}',
        );
      }
    }
    return ApiEngineConfig(
      backends: backends,
      rescue: RescueConfig.fromMap(_map(value, 'rescue')),
    );
  }

  final List<BackendConfig> backends;
  final RescueConfig rescue;

  /// The JSON-schema-shaped description of this block, for the config lib.
  static Map<String, Object?> get schema => <String, Object?>{
    r'$id': 'urn:diene:config-block:api-engine',
    'type': 'object',
    'required': <String>['backends', 'rescue'],
    'properties': <String, Object?>{
      'backends': <String, Object?>{
        'type': 'array',
        'minItems': 1,
        'items': <String, Object?>{
          'type': 'object',
          'required': <String>['coordinate', 'baseUrl'],
          'properties': <String, Object?>{
            'coordinate': <String, Object?>{
              'type': 'object',
              'required': <String>[
                'landscape',
                'platform',
                'service',
                'module',
              ],
            },
            'baseUrl': <String, Object?>{'type': 'string', 'format': 'uri'},
            'resourceName': <String, Object?>{'type': 'string'},
            'timeoutSeconds': <String, Object?>{'type': 'integer'},
            'retryOnNetworkError': <String, Object?>{'type': 'boolean'},
          },
        },
      },
      'rescue': <String, Object?>{
        'type': 'object',
        'required': <String>[
          'enabled',
          'issuer',
          'catalogHosts',
          'endpointSuffixAllowlist',
        ],
        'properties': <String, Object?>{
          'enabled': <String, Object?>{'type': 'boolean'},
          'issuer': <String, Object?>{'type': 'string', 'format': 'uri'},
          'catalogHosts': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{'type': 'string'},
          },
          'endpointSuffixAllowlist': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{'type': 'string'},
          },
          'scanBudgetMs': <String, Object?>{'type': 'integer'},
          'perCandidateTimeoutMs': <String, Object?>{'type': 'integer'},
          'maxJitterMs': <String, Object?>{'type': 'integer'},
        },
      },
    },
  };

  static const DeepCollectionEquality _eq = DeepCollectionEquality();

  /// True when [other] equals [schema].
  static bool schemaEquals(Map<String, Object?> other) =>
      _eq.equals(schema, other);
}

Map<String, Object?> _map(Map<String, Object?> value, String key) =>
    _asMap(value[key], key);

Map<String, Object?> _asMap(Object? item, String label) {
  if (item is! Map) {
    throw FormatException('config key $label must be a map');
  }
  return item.map((Object? k, Object? v) => MapEntry(k.toString(), v));
}

List<Object?> _list(Map<String, Object?> value, String key) {
  final Object? item = value[key];
  if (item is! List) {
    throw FormatException('config key $key must be a list');
  }
  return item;
}

List<String> _stringList(Map<String, Object?> value, String key) => _list(
  value,
  key,
).map((Object? item) => item.toString()).toList(growable: false);

String _string(Map<String, Object?> value, String key) {
  final Object? item = value[key];
  if (item is! String || item.isEmpty) {
    throw FormatException('config key $key must be a non-empty string');
  }
  return item;
}
