import 'package:diene_config/diene_config.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

import '../support.dart';

final class AuthSettings {
  const AuthSettings({required this.issuer, required this.audience});

  final String issuer;
  final String audience;

  @override
  bool operator ==(Object other) =>
      other is AuthSettings &&
      other.issuer == issuer &&
      other.audience == audience;

  @override
  int get hashCode => Object.hash(issuer, audience);
}

final class ApiSettings {
  const ApiSettings({required this.baseUrl, required this.timeoutMs});

  final Uri baseUrl;
  final int timeoutMs;

  @override
  bool operator ==(Object other) =>
      other is ApiSettings &&
      other.baseUrl == baseUrl &&
      other.timeoutMs == timeoutMs;

  @override
  int get hashCode => Object.hash(baseUrl, timeoutMs);
}

final ConfigBlock<AuthSettings> authEngineBlock = ConfigBlock<AuthSettings>(
  key: 'auth',
  decode: (Map<String, Object?> values) => AuthSettings(
    issuer: values['issuer']! as String,
    audience: values['audience']! as String,
  ),
);

final ConfigBlock<ApiSettings> apiEngineBlock = ConfigBlock<ApiSettings>(
  key: 'api',
  decode: (Map<String, Object?> values) => ApiSettings(
    baseUrl: Uri.parse(values['baseUrl']! as String),
    timeoutMs: values['timeoutMs']! as int,
  ),
);

ConfigSchema serviceSchema() => ConfigSchema(
  blocks: <ConfigBlockSchema>[authEngineBlock, apiEngineBlock, appBlock],
);

const String _validRoot = '''
auth:
  issuer: https://auth.test
  audience: service
api:
  baseUrl: https://api.test
  timeoutMs: 500
app:
  name: service
  retries: 2
''';

Future<Result<DieneConfig>> loadRoot(String yaml) => ConfigLoader(
  base: YamlConfigSource.string(yaml, name: 'base.yaml'),
  dartDefines: const DartDefineOverrides(prefix: 'ACME_'),
  schema: serviceSchema(),
).load();

void main() {
  group('a root composed from engine blocks and a service block', () {
    test('validates and exposes each typed slice', () async {
      // Arrange
      const String yaml = _validRoot;

      // Act
      final Result<DieneConfig> loaded = await loadRoot(yaml);

      // Assert
      expect(loaded, isOk, reason: describe(loaded));
      final DieneConfig config = loaded.unwrap();
      expect(
        config.slice(authEngineBlock),
        const AuthSettings(issuer: 'https://auth.test', audience: 'service'),
      );
      expect(
        config.slice(apiEngineBlock),
        ApiSettings(baseUrl: Uri.parse('https://api.test'), timeoutMs: 500),
      );
      expect(
        config.slice(appBlock),
        const AppSettings(name: 'service', retries: 2, tags: <String>[]),
      );
    });

    test('rejects a missing required engine block', () async {
      // Arrange
      const String yaml = '''
auth:
  issuer: https://auth.test
  audience: service
app:
  name: service
  retries: 2
''';

      // Act
      final Result<DieneConfig> loaded = await loadRoot(yaml);

      // Assert
      expect(loaded, isErr, reason: describe(loaded));
      final Problem problem = loaded.unwrapErr();
      expect(problem.data['code'], ConfigProblemCode.schemaInvalid.wireId);
      expect(errorsOf(problem), <String>['api: required block is missing']);
    });

    test('rejects an unknown root key', () async {
      // Arrange
      const String yaml = '${_validRoot}billing:\n  plan: free\n';

      // Act
      final Result<DieneConfig> loaded = await loadRoot(yaml);

      // Assert
      expect(loaded, isErr, reason: describe(loaded));
      expect(errorsOf(loaded.unwrapErr()), <String>[
        'billing: no composed block schema',
      ]);
    });

    test('rejects a block that is not a map', () async {
      // Arrange
      const String yaml = '''
auth: not-a-map
api:
  baseUrl: https://api.test
  timeoutMs: 500
app:
  name: service
  retries: 2
''';

      // Act
      final Result<DieneConfig> loaded = await loadRoot(yaml);

      // Assert
      expect(loaded, isErr, reason: describe(loaded));
      expect(errorsOf(loaded.unwrapErr()), <String>[
        'auth: block must be a map',
      ]);
    });

    test('rejects an engine block its own decoder refuses', () async {
      // Arrange
      final String yaml = _validRoot.replaceFirst(
        'timeoutMs: 500',
        'timeoutMs: slow',
      );

      // Act
      final Result<DieneConfig> loaded = await loadRoot(yaml);

      // Assert
      expect(loaded, isErr, reason: describe(loaded));
      expect(errorsOf(loaded.unwrapErr()).single, startsWith('api: '));
    });
  });

  group('composing a root schema', () {
    test('rejects two blocks with the same key', () {
      // Arrange
      final List<ConfigBlockSchema> blocks = <ConfigBlockSchema>[
        authEngineBlock,
        ConfigBlock<String>(key: 'AUTH', decode: (_) => 'service copy'),
      ];

      // Act
      ConfigSchema compose() => ConfigSchema(blocks: blocks);

      // Assert
      expect(compose, throwsArgumentError);
    });

    test('rejects an empty block key', () {
      // Arrange
      final List<ConfigBlockSchema> blocks = <ConfigBlockSchema>[
        apiEngineBlock,
        ConfigBlock<String>(key: '', decode: (_) => 'nameless'),
      ];

      // Act
      ConfigSchema compose() => ConfigSchema(blocks: blocks);

      // Assert
      expect(compose, throwsArgumentError);
    });
  });
}
