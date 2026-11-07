import 'dart:io';

import 'package:diene_config/diene_config.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

import '../support.dart';

const String _layers = 'test/fixtures/layers';

final class ApiSettings {
  const ApiSettings({required this.baseUrl, required this.timeoutMs});

  final String baseUrl;
  final int timeoutMs;

  @override
  bool operator ==(Object other) =>
      other is ApiSettings &&
      other.baseUrl == baseUrl &&
      other.timeoutMs == timeoutMs;

  @override
  int get hashCode => Object.hash(baseUrl, timeoutMs);

  @override
  String toString() => 'ApiSettings($baseUrl, $timeoutMs)';
}

final ConfigBlock<ApiSettings> apiBlock = ConfigBlock<ApiSettings>(
  key: 'api',
  decode: (Map<String, Object?> values) => ApiSettings(
    baseUrl: values['baseUrl']! as String,
    timeoutMs: values['timeoutMs']! as int,
  ),
);

ConfigSource fileLayer(String file) =>
    YamlConfigSource(name: file, read: File('$_layers/$file').readAsString);

ConfigLoader fileLoader({
  String base = 'base.yaml',
  String? overlay,
  String? development,
  Map<String, String> defines = const <String, String>{},
}) => ConfigLoader(
  base: fileLayer(base),
  overlay: overlay == null ? null : fileLayer(overlay),
  developmentOverride: development == null ? null : fileLayer(development),
  dartDefines: DartDefineOverrides(prefix: 'ACME_', values: defines),
  schema: ConfigSchema(blocks: <ConfigBlockSchema>[appBlock, apiBlock]),
);

void main() {
  group('YAML layers read from disk', () {
    test('the base file alone loads its own values', () async {
      // Arrange
      final ConfigLoader loader = fileLoader();

      // Act
      final Result<DieneConfig> loaded = await loader.load();

      // Assert
      expect(loaded, isOk, reason: describe(loaded));
      final DieneConfig config = loaded.unwrap();
      expect(
        config.slice(appBlock),
        const AppSettings(name: 'base', retries: 1, tags: <String>['base']),
      );
      expect(
        config.slice(apiBlock),
        const ApiSettings(baseUrl: 'https://api.base.test', timeoutMs: 1000),
      );
    });

    test(
      'base, landscape, development and defines merge into the slices',
      () async {
        // Arrange
        final ConfigLoader loader = fileLoader(
          overlay: 'landscape.yaml',
          development: 'development.yaml',
          defines: <String, String>{
            'ACME_APP__RETRIES': '4',
            'ACME_API__BASE_URL': 'https://api.define.test',
          },
        );

        // Act
        final Result<DieneConfig> loaded = await loader.load();

        // Assert
        expect(loaded, isOk, reason: describe(loaded));
        final DieneConfig config = loaded.unwrap();
        expect(
          config.slice(appBlock),
          const AppSettings(
            name: 'development',
            retries: 4,
            tags: <String>['landscape'],
          ),
        );
        expect(
          config.slice(apiBlock),
          const ApiSettings(
            baseUrl: 'https://api.define.test',
            timeoutMs: 30000,
          ),
        );
        expect(config.rawSlice('api').unwrap().keys, <String>[
          'baseUrl',
          'timeoutMs',
        ]);
      },
    );

    test('a missing file is source_unreadable and names the layer', () async {
      // Arrange
      final ConfigLoader loader = fileLoader(overlay: 'absent.yaml');

      // Act
      final Result<DieneConfig> loaded = await loader.load();

      // Assert
      expect(loaded, isErr, reason: describe(loaded));
      final Problem problem = loaded.unwrapErr();
      expect(problem.data['code'], ConfigProblemCode.sourceUnreadable.wireId);
      expect(problem.data['source'], 'absent.yaml');
      expect('${problem.data['reason']}', contains('absent.yaml'));
    });
  });
}
