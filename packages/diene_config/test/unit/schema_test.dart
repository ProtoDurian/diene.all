import 'package:diene_config/diene_config.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

import '../support.dart';

final class ApiSettings {
  const ApiSettings(this.baseUrl);

  final String baseUrl;

  @override
  bool operator ==(Object other) =>
      other is ApiSettings && other.baseUrl == baseUrl;

  @override
  int get hashCode => baseUrl.hashCode;

  @override
  String toString() => 'ApiSettings($baseUrl)';
}

final ConfigBlock<ApiSettings> apiBlock = ConfigBlock<ApiSettings>(
  key: 'api',
  decode: (Map<String, Object?> values) =>
      ApiSettings(values['baseUrl']! as String),
);

final ConfigBlock<ApiSettings> optionalApiBlock = ConfigBlock<ApiSettings>(
  key: 'api',
  required: false,
  decode: (Map<String, Object?> values) =>
      ApiSettings(values['baseUrl']! as String),
);

Map<String, Object?> validApp() => <String, Object?>{
  'app': <String, Object?>{
    'name': 'service',
    'retries': 2,
    'tags': <Object?>['alpha'],
  },
};

void main() {
  group('ConfigSchema construction', () {
    test('rejects an empty block key as programmer misuse', () {
      // Arrange
      final List<ConfigBlockSchema> blocks = <ConfigBlockSchema>[
        ConfigBlock<int>(key: '', decode: (_) => 0),
      ];

      // Act
      ConfigSchema compose() => ConfigSchema(blocks: blocks);

      // Assert
      expect(compose, throwsA(isA<ArgumentError>()));
    });

    test(r'rejects the reserved $schema key', () {
      // Arrange
      final List<ConfigBlockSchema> blocks = <ConfigBlockSchema>[
        ConfigBlock<int>(key: r'$schema', decode: (_) => 0),
      ];

      // Act
      ConfigSchema compose() => ConfigSchema(blocks: blocks);

      // Assert
      expect(compose, throwsA(isA<ArgumentError>()));
    });

    test('rejects two blocks whose keys canonicalise together', () {
      // Arrange
      final List<ConfigBlockSchema> blocks = <ConfigBlockSchema>[
        ConfigBlock<int>(key: 'app-settings', decode: (_) => 0),
        ConfigBlock<int>(key: 'appSettings', decode: (_) => 1),
      ];

      // Act
      ConfigSchema compose() => ConfigSchema(blocks: blocks);

      // Assert
      expect(compose, throwsA(isA<ArgumentError>()));
    });

    test('exposes its composed blocks, unmodifiably', () {
      // Arrange
      final ConfigSchema schema = appSchema();

      // Act
      final List<ConfigBlockSchema> blocks = schema.blocks;

      // Assert
      expect(blocks, hasLength(1));
      expect(blocks.single.key, 'app');
      expect(schema.rejectUnknownBlocks, isTrue);
      expect(blocks.clear, throwsUnsupportedError);
    });

    test('accepts an empty block list against an empty configuration', () {
      // Arrange
      final ConfigSchema schema = ConfigSchema(
        blocks: const <ConfigBlockSchema>[],
      );

      // Act
      final Result<DieneConfig> validated = schema.validate(
        <String, Object?>{},
      );

      // Assert
      expect(validated, isOk, reason: describe(validated));
      expect(validated.unwrap().raw, isEmpty);
    });
  });

  group('ConfigSchema.validate', () {
    test('decodes a valid configuration into a typed slice', () {
      // Arrange
      final ConfigSchema schema = appSchema();

      // Act
      final Result<DieneConfig> validated = schema.validate(validApp());

      // Assert
      expect(validated, isOk, reason: describe(validated));
      expect(
        validated.unwrap().slice(appBlock),
        const AppSettings(name: 'service', retries: 2, tags: <String>['alpha']),
      );
    });

    test('matches a block key case- and separator-insensitively', () {
      // Arrange
      final ConfigBlock<String> settingsBlock = ConfigBlock<String>(
        key: 'app-settings',
        decode: (Map<String, Object?> values) =>
            values['displayName']! as String,
      );
      final ConfigSchema schema = ConfigSchema(
        blocks: <ConfigBlockSchema>[settingsBlock],
      );

      // Act
      final Result<DieneConfig> validated = schema.validate(<String, Object?>{
        'AppSettings': <String, Object?>{'displayName': 'matched'},
      });

      // Assert
      expect(validated, isOk, reason: describe(validated));
      expect(validated.unwrap().slice(settingsBlock), 'matched');
    });

    test(r'ignores the reserved $schema root key', () {
      // Arrange
      final Map<String, Object?> values = validApp()
        ..[r'$schema'] = 'https://example.test/config.json';

      // Act
      final Result<DieneConfig> validated = appSchema().validate(values);

      // Assert
      expect(validated, isOk, reason: describe(validated));
    });

    test('reports a missing required block', () {
      // Arrange
      final ConfigSchema schema = appSchema();

      // Act
      final Result<DieneConfig> validated = schema.validate(
        <String, Object?>{},
      );

      // Assert
      expect(validated, isErr, reason: describe(validated));
      final Problem problem = validated.unwrapErr();
      expect(problem.data['code'], ConfigProblemCode.schemaInvalid.wireId);
      expect(problem.status, 422);
      expect(errorsOf(problem), <String>['app: required block is missing']);
    });

    test('accepts an absent optional block', () {
      // Arrange
      final ConfigSchema schema = ConfigSchema(
        blocks: <ConfigBlockSchema>[appBlock, optionalApiBlock],
      );

      // Act
      final Result<DieneConfig> validated = schema.validate(validApp());

      // Assert
      expect(validated, isOk, reason: describe(validated));
      final DieneConfig config = validated.unwrap();
      expect(config.hasSlice(optionalApiBlock), isFalse);
      expect(config.optionalSlice(optionalApiBlock).isNone, isTrue);
    });

    test('decodes an optional block that is present', () {
      // Arrange
      final ConfigSchema schema = ConfigSchema(
        blocks: <ConfigBlockSchema>[appBlock, optionalApiBlock],
      );
      final Map<String, Object?> values = validApp()
        ..['api'] = <String, Object?>{'baseUrl': 'https://api.test'};

      // Act
      final DieneConfig config = schema.validate(values).unwrap();

      // Assert
      expect(config.hasSlice(optionalApiBlock), isTrue);
      expect(
        config.optionalSlice(optionalApiBlock).unwrap(),
        const ApiSettings('https://api.test'),
      );
    });

    test('reports a block whose value is not a map', () {
      // Arrange
      final ConfigSchema schema = appSchema();

      // Act
      final Result<DieneConfig> validated = schema.validate(<String, Object?>{
        'app': 'not a map',
      });

      // Assert
      expect(errorsOf(validated.unwrapErr()), <String>[
        'app: block must be a map',
      ]);
    });

    test('reports a block whose value is a list', () {
      // Arrange
      final ConfigSchema schema = appSchema();

      // Act
      final Result<DieneConfig> validated = schema.validate(<String, Object?>{
        'app': <Object?>['nope'],
      });

      // Assert
      expect(errorsOf(validated.unwrapErr()), <String>[
        'app: block must be a map',
      ]);
    });

    test('folds a throwing decoder into the aggregate problem', () {
      // Arrange
      final ConfigSchema schema = appSchema();

      // Act
      final Result<DieneConfig> validated = schema.validate(<String, Object?>{
        'app': <String, Object?>{'name': '', 'retries': 1},
      });

      // Assert
      final List<String> errors = errorsOf(validated.unwrapErr());
      expect(errors, hasLength(1));
      expect(errors.single, startsWith('app: '));
      expect(errors.single, contains('non-empty string'));
    });

    test('rejects an unknown root key by default', () {
      // Arrange
      final Map<String, Object?> values = validApp()
        ..['aap'] = <String, Object?>{'typo': true};

      // Act
      final Result<DieneConfig> validated = appSchema().validate(values);

      // Assert
      expect(errorsOf(validated.unwrapErr()), <String>[
        'aap: no composed block schema',
      ]);
    });

    test('tolerates an unknown root key when told to', () {
      // Arrange
      final Map<String, Object?> values = validApp()
        ..['extra'] = <String, Object?>{'ok': true};

      // Act
      final Result<DieneConfig> validated = appSchema(
        rejectUnknownBlocks: false,
      ).validate(values);

      // Assert
      expect(validated, isOk, reason: describe(validated));
      expect(validated.unwrap().raw.containsKey('extra'), isTrue);
    });

    test('reports two root keys that collide under canonicalisation', () {
      // Arrange
      final ConfigSchema schema = appSchema();

      // Act
      final Result<DieneConfig> validated = schema.validate(<String, Object?>{
        'app': <String, Object?>{'name': 'a', 'retries': 0},
        'A_P_P': <String, Object?>{'name': 'b', 'retries': 0},
      });

      // Assert
      final List<String> errors = errorsOf(validated.unwrapErr());
      expect(errors.first, 'root keys app and A_P_P collide');
    });

    test('reports every problem in one pass, not just the first', () {
      // Arrange
      final ConfigSchema schema = ConfigSchema(
        blocks: <ConfigBlockSchema>[appBlock, apiBlock],
      );

      // Act
      final Result<DieneConfig> validated = schema.validate(<String, Object?>{
        'app': <String, Object?>{'name': 'service', 'retries': -1},
        'unknown': <String, Object?>{},
      });

      // Assert
      final List<String> errors = errorsOf(validated.unwrapErr());
      expect(errors, hasLength(3));
      expect(errors, contains('api: required block is missing'));
      expect(errors, contains('unknown: no composed block schema'));
      expect(errors.any((String e) => e.startsWith('app: ')), isTrue);
    });

    test('carries an unmodifiable error list', () {
      // Arrange
      final ConfigSchema schema = appSchema();

      // Act
      final Problem problem = schema.validate(<String, Object?>{}).unwrapErr();

      // Assert
      expect(
        (problem.data['errors']! as List<Object?>).clear,
        throwsUnsupportedError,
      );
    });
  });

  group('DieneConfig', () {
    test('exposes a deeply immutable raw tree', () {
      // Arrange
      final DieneConfig config = appSchema().validate(validApp()).unwrap();

      // Act
      final Map<String, Object?> app =
          config.raw['app']! as Map<String, Object?>;

      // Assert
      expect(() => config.raw['app'] = null, throwsUnsupportedError);
      expect(() => app['name'] = 'mutated', throwsUnsupportedError);
      expect(
        () => (app['tags']! as List<Object?>).add('mutated'),
        throwsUnsupportedError,
      );
    });

    test('rawSlice returns an untyped view, matched insensitively', () {
      // Arrange
      final DieneConfig config = appSchema().validate(validApp()).unwrap();

      // Act
      final Result<Map<String, Object?>> slice = config.rawSlice('A-P-P');

      // Assert
      expect(slice, isOk, reason: describe(slice));
      expect(slice.unwrap()['name'], 'service');
    });

    test('rawSlice reports a block that was not loaded', () {
      // Arrange
      final DieneConfig config = appSchema().validate(validApp()).unwrap();

      // Act
      final Result<Map<String, Object?>> slice = config.rawSlice('absent');

      // Assert
      expect(slice, isErr, reason: describe(slice));
      expect(
        slice.unwrapErr().data['code'],
        ConfigProblemCode.schemaInvalid.wireId,
      );
      expect(slice.unwrapErr().data['block'], 'absent');
    });

    test('rawSlice reports a root key that is not a map', () {
      // Arrange
      final DieneConfig config = appSchema(
        rejectUnknownBlocks: false,
      ).validate(validApp()..['scalar'] = 7).unwrap();

      // Act
      final Result<Map<String, Object?>> slice = config.rawSlice('scalar');

      // Assert
      expect(slice, isErr, reason: describe(slice));
      expect(slice.unwrapErr().title, contains('is not a map'));
    });

    test('slice throws for a block that was never composed', () {
      // Arrange
      final DieneConfig config = appSchema().validate(validApp()).unwrap();

      // Act
      ApiSettings read() => config.slice(apiBlock);

      // Assert
      expect(read, throwsStateError);
    });

    test('slice throws for an absent optional block', () {
      // Arrange
      final DieneConfig config = ConfigSchema(
        blocks: <ConfigBlockSchema>[appBlock, optionalApiBlock],
      ).validate(validApp()).unwrap();

      // Act
      ApiSettings read() => config.slice(optionalApiBlock);

      // Assert
      expect(read, throwsStateError);
    });

    test('slice refuses a same-key block with an incompatible type', () {
      // Arrange
      final DieneConfig config = appSchema().validate(validApp()).unwrap();
      final ConfigBlock<int> impostor = ConfigBlock<int>(
        key: 'APP',
        decode: (Map<String, Object?> values) => values['retries']! as int,
      );

      // Act
      final bool hasImpostor = config.hasSlice(impostor);

      // Assert
      expect(hasImpostor, isFalse);
      expect(config.optionalSlice(impostor).isNone, isTrue);
      expect(() => config.slice(impostor), throwsStateError);
      expect(config.slice(appBlock).name, 'service');
    });

    test('slice refuses a same-key, same-type lookalike block', () {
      // Arrange
      final Map<String, Object?> values = validApp()
        ..['api'] = <String, Object?>{'baseUrl': 'https://api.test'};
      final DieneConfig config = ConfigSchema(
        blocks: <ConfigBlockSchema>[appBlock, apiBlock],
      ).validate(values).unwrap();
      final ConfigBlock<ApiSettings> lookalike = ConfigBlock<ApiSettings>(
        key: 'api',
        decode: (Map<String, Object?> values) =>
            ApiSettings(values['baseUrl']! as String),
      );

      // Act
      final bool hasLookalike = config.hasSlice(lookalike);

      // Assert
      expect(hasLookalike, isFalse);
      expect(config.optionalSlice(lookalike).isNone, isTrue);
      expect(() => config.slice(lookalike), throwsStateError);
      expect(config.slice(apiBlock), const ApiSettings('https://api.test'));
    });

    test('two schemas over the same block keys keep their slices apart', () {
      // Arrange
      final ConfigBlock<String> nameBlock = ConfigBlock<String>(
        key: 'app',
        decode: (Map<String, Object?> values) => values['name']! as String,
      );
      final ConfigBlock<int> retriesBlock = ConfigBlock<int>(
        key: 'app',
        decode: (Map<String, Object?> values) => values['retries']! as int,
      );

      // Act
      final DieneConfig byName = ConfigSchema(
        blocks: <ConfigBlockSchema>[nameBlock],
      ).validate(validApp()).unwrap();
      final DieneConfig byRetries = ConfigSchema(
        blocks: <ConfigBlockSchema>[retriesBlock],
      ).validate(validApp()).unwrap();

      // Assert
      expect(byName.slice(nameBlock), 'service');
      expect(byRetries.slice(retriesBlock), 2);
      expect(byName.hasSlice(retriesBlock), isFalse);
      expect(byRetries.hasSlice(nameBlock), isFalse);
      expect(() => byName.slice(retriesBlock), throwsStateError);
      expect(() => byRetries.slice(nameBlock), throwsStateError);
    });

    test(
      'optionalSlice is None for a same-key block that was not composed',
      () {
        // Arrange
        final Map<String, Object?> values = validApp()
          ..['api'] = <String, Object?>{'baseUrl': 'https://api.test'};
        final DieneConfig config = ConfigSchema(
          blocks: <ConfigBlockSchema>[appBlock, optionalApiBlock],
        ).validate(values).unwrap();
        final ConfigBlock<int> uncomposed = ConfigBlock<int>(
          key: 'a-p-i',
          required: false,
          decode: (_) => 0,
        );

        // Act
        final Option<int> slice = config.optionalSlice(uncomposed);

        // Assert
        expect(config.optionalSlice(optionalApiBlock).isSome, isTrue);
        expect(slice.isNone, isTrue);
        expect(config.hasSlice(uncomposed), isFalse);
      },
    );

    test('stableProjection sorts keys at every depth', () {
      // Arrange
      final DieneConfig config = appSchema(rejectUnknownBlocks: false).validate(
        <String, Object?>{
          'zeta': <String, Object?>{'b': 1, 'a': 2},
          'app': <String, Object?>{'name': 'service', 'retries': 0},
        },
      ).unwrap();

      // Act
      final Result<Object?> projected = config.stableProjection();

      // Assert
      expect(projected, isOk, reason: describe(projected));
      final Map<String, Object?> tree =
          projected.unwrap()! as Map<String, Object?>;
      expect(tree.keys, <String>['app', 'zeta']);
      expect((tree['zeta']! as Map<String, Object?>).keys, <String>['a', 'b']);
    });
  });

  group('ConfigBlock', () {
    test('decodeUntyped erases the static type without changing the value', () {
      // Arrange
      final Map<String, Object?> values = <String, Object?>{
        'name': 'erased',
        'retries': 3,
      };

      // Act
      final Object? decoded = appBlock.decodeUntyped(values);

      // Assert
      expect(
        decoded,
        const AppSettings(name: 'erased', retries: 3, tags: <String>[]),
      );
    });

    test('is required by default', () {
      // Arrange
      final ConfigBlock<int> plain = ConfigBlock<int>(
        key: 'plain',
        decode: (_) => 0,
      );

      // Act
      final bool required = plain.required;

      // Assert
      expect(required, isTrue);
      expect(appBlock.required, isTrue);
      expect(optionalApiBlock.required, isFalse);
    });
  });
}
