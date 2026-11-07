import 'package:diene_config/diene_config.dart';
import 'package:diene_config/test_helper.dart';
import 'package:diene_core_utils/diene_core_utils.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

import '../support.dart';

const String _baseYaml = '''
app:
  name: base
  retries: 1
  tags: [base]
''';

const String _ladderBaseYaml = '''
app:
  name: base
  retries: 1
  first: base
  second: base
  third: base
  fourth: base
''';

const String _ladderOverlayYaml = '''
app:
  second: overlay
  third: overlay
  fourth: overlay
''';

const String _ladderDevelopmentYaml = '''
app:
  third: development
  fourth: development
''';

const Map<String, String> _ladderDefines = <String, String>{
  'ACME_APP__FOURTH': 'define',
};

ConfigLoader loaderOf({
  String base = _baseYaml,
  String? overlay,
  String? development,
  Map<String, String> defines = const <String, String>{},
  String prefix = 'ACME_',
  bool rejectUnknownBlocks = true,
  ConfigSchema? schema,
}) => ConfigLoader(
  base: YamlConfigSource.string(base, name: 'base.yaml'),
  overlay: overlay == null
      ? null
      : YamlConfigSource.string(overlay, name: 'overlay.yaml'),
  developmentOverride: development == null
      ? null
      : YamlConfigSource.string(development, name: 'development.yaml'),
  dartDefines: DartDefineOverrides(prefix: prefix, values: defines),
  schema: schema ?? appSchema(rejectUnknownBlocks: rejectUnknownBlocks),
);

Future<JsonObject> _layerOf(String yaml) async =>
    (await YamlConfigSource.string(yaml).load()).unwrap();

void main() {
  group('layer precedence', () {
    test('base alone produces the base values', () async {
      // Arrange
      final ConfigLoader loader = loaderOf();

      // Act
      final Result<DieneConfig> loaded = await loader.load();

      // Assert
      expect(loaded, isOk, reason: describe(loaded));
      expect(
        loaded.unwrap().slice(appBlock),
        const AppSettings(name: 'base', retries: 1, tags: <String>['base']),
      );
    });

    test('overlay beats base', () async {
      // Arrange
      final ConfigLoader loader = loaderOf(overlay: 'app:\n  name: overlay\n');

      // Act
      final Result<DieneConfig> loaded = await loader.load();

      // Assert
      expect(loaded, isOk, reason: describe(loaded));
      final AppSettings app = loaded.unwrap().slice(appBlock);
      expect(app.name, 'overlay');
      expect(app.retries, 1, reason: 'a sparse overlay leaves other keys');
    });

    test('development beats overlay', () async {
      // Arrange
      final ConfigLoader loader = loaderOf(
        overlay: 'app:\n  name: overlay\n',
        development: 'app:\n  name: development\n',
      );

      // Act
      final Result<DieneConfig> loaded = await loader.load();

      // Assert
      expect(loaded.unwrap().slice(appBlock).name, 'development');
    });

    test('defines beat every YAML layer', () async {
      // Arrange
      final ConfigLoader loader = loaderOf(
        overlay: 'app:\n  name: overlay\n',
        development: 'app:\n  name: development\n',
        defines: <String, String>{'ACME_APP__NAME': 'define'},
      );

      // Act
      final Result<DieneConfig> loaded = await loader.load();

      // Assert
      expect(loaded.unwrap().slice(appBlock).name, 'define');
    });

    test('each layer wins exactly one key in base, overlay, development, '
        'define order', () async {
      // Arrange
      final ConfigLoader loader = loaderOf(
        base: 'app:\n  name: base\n  retries: 1\n  tags: [base]\n',
        overlay: 'app:\n  retries: 2\n',
        development: 'app:\n  tags: [development]\n',
        defines: <String, String>{'ACME_APP__NAME': 'define'},
      );

      // Act
      final Result<DieneConfig> loaded = await loader.load();

      // Assert
      expect(
        loaded.unwrap().slice(appBlock),
        const AppSettings(
          name: 'define',
          retries: 2,
          tags: <String>['development'],
        ),
      );
    });

    test('a later layer wins on a shared key and earlier values survive '
        'where no later layer sets the key', () async {
      // Arrange
      final ConfigLoader loader = loaderOf(
        base: _ladderBaseYaml,
        overlay: _ladderOverlayYaml,
        development: _ladderDevelopmentYaml,
        defines: _ladderDefines,
      );

      // Act
      final Result<DieneConfig> loaded = await loader.load();

      // Assert
      expect(loaded, isOk, reason: describe(loaded));
      final Map<String, Object?> app = loaded.unwrap().rawSlice('app').unwrap();
      expect(app['first'], 'base');
      expect(app['second'], 'overlay');
      expect(app['third'], 'development');
      expect(app['fourth'], 'define');
      expect(app['name'], 'base');
      expect(app['retries'], 1);
    });

    test('a reversed layer order gives a different tree', () async {
      // Arrange
      final List<JsonObject> layers = <JsonObject>[
        await _layerOf(_ladderBaseYaml),
        await _layerOf(_ladderOverlayYaml),
        await _layerOf(_ladderDevelopmentYaml),
        const DartDefineOverrides(
          prefix: 'ACME_',
          values: _ladderDefines,
        ).layer().unwrap(),
      ];
      final ConfigLoader loader = loaderOf(
        base: _ladderBaseYaml,
        overlay: _ladderOverlayYaml,
        development: _ladderDevelopmentYaml,
        defines: _ladderDefines,
      );

      // Act
      final Map<String, Object?> loaded = (await loader.load()).unwrap().raw;
      final JsonObject forward = deepMergeAll(layers);
      final JsonObject reversed = deepMergeAll(layers.reversed);

      // Assert
      expect(loaded, equals(forward));
      expect(loaded, isNot(equals(reversed)));
      expect((reversed['app']! as JsonObject)['fourth'], 'base');
    });

    test('reads each layer exactly once', () async {
      // Arrange
      final FakeConfigSource base = FakeConfigSource(<String, Object?>{
        'app': <String, Object?>{'name': 'base', 'retries': 0},
      });
      final FakeConfigSource overlay = FakeConfigSource(<String, Object?>{
        'app': <String, Object?>{'name': 'overlay'},
      });
      final ConfigLoader loader = ConfigLoader(
        base: base,
        overlay: overlay,
        dartDefines: const DartDefineOverrides(prefix: 'ACME_'),
        schema: appSchema(),
      );

      // Act
      await loader.load();

      // Assert
      expect(base.loadCount, 1);
      expect(overlay.loadCount, 1);
    });

    test('a null overlay and development source are skipped', () async {
      // Arrange
      final FakeConfigSource base = FakeConfigSource(<String, Object?>{
        'app': <String, Object?>{'name': 'base', 'retries': 0},
      });
      final ConfigLoader loader = ConfigLoader(
        base: base,
        dartDefines: const DartDefineOverrides(prefix: 'ACME_'),
        schema: appSchema(),
      );

      // Act
      final Result<DieneConfig> loaded = await loader.load();

      // Assert
      expect(loaded, isOk, reason: describe(loaded));
      expect(loaded.unwrap().slice(appBlock).name, 'base');
    });

    test('merges nested maps rather than replacing them', () async {
      // Arrange
      final ConfigLoader loader = loaderOf(
        base:
            'app:\n'
            '  name: base\n'
            '  retries: 0\n'
            '  nested:\n'
            '    kept: yes\n'
            '    replaced: no\n',
        overlay: 'app:\n  nested:\n    replaced: yes\n',
        rejectUnknownBlocks: false,
      );

      // Act
      final Result<DieneConfig> loaded = await loader.load();

      // Assert
      expect(loaded, isOk, reason: describe(loaded));
      final Map<String, Object?> nested =
          (loaded.unwrap().rawSlice('app').unwrap()['nested']!
              as Map<String, Object?>);
      expect(nested['kept'], 'yes');
      expect(nested['replaced'], 'yes');
    });

    test('replaces a list wholesale, with no append', () async {
      // Arrange
      final ConfigLoader loader = loaderOf(overlay: 'app:\n  tags: [only]\n');

      // Act
      final Result<DieneConfig> loaded = await loader.load();

      // Assert
      expect(loaded.unwrap().slice(appBlock).tags, <String>['only']);
    });
  });

  group('development override hook', () {
    test(
      'a present hook applies after the overlay and before the defines',
      () async {
        // Arrange
        final FakeConfigSource development = FakeConfigSource(<String, Object?>{
          'app': <String, Object?>{'name': 'development', 'retries': 3},
        });
        final ConfigLoader loader = ConfigLoader(
          base: YamlConfigSource.string(_baseYaml),
          overlay: YamlConfigSource.string('app:\n  name: overlay\n'),
          developmentOverride: development,
          dartDefines: const DartDefineOverrides(
            prefix: 'ACME_',
            values: <String, String>{'ACME_APP__RETRIES': '9'},
          ),
          schema: appSchema(),
        );

        // Act
        final Result<DieneConfig> loaded = await loader.load();

        // Assert
        expect(loaded, isOk, reason: describe(loaded));
        expect(development.loadCount, 1);
        expect(
          loaded.unwrap().slice(appBlock),
          const AppSettings(
            name: 'development',
            retries: 9,
            tags: <String>['base'],
          ),
        );
      },
    );

    test('an absent hook is skipped', () async {
      // Arrange
      final ConfigLoader loader = ConfigLoader(
        base: YamlConfigSource.string(_baseYaml),
        overlay: YamlConfigSource.string('app:\n  name: overlay\n'),
        dartDefines: const DartDefineOverrides(
          prefix: 'ACME_',
          values: <String, String>{'ACME_APP__RETRIES': '9'},
        ),
        schema: appSchema(),
      );

      // Act
      final Result<DieneConfig> loaded = await loader.load();

      // Assert
      expect(loader.developmentOverride, isNull);
      expect(loaded, isOk, reason: describe(loaded));
      expect(
        loaded.unwrap().slice(appBlock),
        const AppSettings(name: 'overlay', retries: 9, tags: <String>['base']),
      );
    });
  });

  group('final-only validation', () {
    test(
      'accepts a base that is invalid alone but completed by a define',
      () async {
        // Arrange
        final ConfigLoader loader = loaderOf(
          base: 'app:\n  name: base\n  retries: -1\n  tags: []\n',
          defines: <String, String>{'ACME_APP__RETRIES': '3'},
        );

        // Act
        final Result<DieneConfig> loaded = await loader.load();

        // Assert
        expect(loaded, isOk, reason: describe(loaded));
        expect(loaded.unwrap().slice(appBlock).retries, 3);
      },
    );

    test('accepts a base missing a required key an overlay supplies', () async {
      // Arrange
      final ConfigLoader loader = loaderOf(
        base: 'app:\n  name: base\n',
        overlay: 'app:\n  retries: 4\n',
      );

      // Act
      final Result<DieneConfig> loaded = await loader.load();

      // Assert
      expect(loaded, isOk, reason: describe(loaded));
      expect(loaded.unwrap().slice(appBlock).retries, 4);
    });

    test(
      'an invalid intermediate layer repaired later decodes exactly once',
      () async {
        // Arrange
        int decodes = 0;
        final ConfigBlock<int> countingBlock = ConfigBlock<int>(
          key: 'app',
          decode: (Map<String, Object?> values) {
            decodes += 1;
            final int retries = values['retries']! as int;
            if (retries < 0) {
              throw FormatException('retries must be non-negative: $retries');
            }
            return retries;
          },
        );
        final ConfigLoader loader = loaderOf(
          base: 'app:\n  retries: 1\n',
          overlay: 'app:\n  retries: -1\n',
          development: 'app:\n  retries: -2\n',
          defines: <String, String>{'ACME_APP__RETRIES': '5'},
          schema: ConfigSchema(blocks: <ConfigBlockSchema>[countingBlock]),
        );

        // Act
        final Result<DieneConfig> loaded = await loader.load();

        // Assert
        expect(loaded, isOk, reason: describe(loaded));
        expect(loaded.unwrap().slice(countingBlock), 5);
        expect(decodes, 1);
      },
    );

    test('rejects a final tree that no layer repaired', () async {
      // Arrange
      final ConfigLoader loader = loaderOf(
        base: 'app:\n  name: service\n  retries: -1\n  tags: []\n',
      );

      // Act
      final Result<DieneConfig> loaded = await loader.load();

      // Assert
      expect(loaded, isErr, reason: describe(loaded));
      expect(
        loaded.unwrapErr().data['code'],
        ConfigProblemCode.schemaInvalid.wireId,
      );
    });

    test('exposes only the final tree', () async {
      // Arrange
      final ConfigLoader loader = loaderOf(
        base: 'app:\n  name: base\n  retries: -1\n  tags: []\n',
        overlay: 'app:\n  retries: 9\n',
      );

      // Act
      final DieneConfig config = (await loader.load()).unwrap();

      // Assert
      expect(config.raw['app'], isA<Map<String, Object?>>());
      expect(config.slice(appBlock).retries, 9);
    });
  });

  group('indexed list defines', () {
    test('FOO__0 and FOO__1 build a list that replaces the YAML one', () async {
      // Arrange
      final ConfigLoader loader = loaderOf(
        defines: <String, String>{
          'ACME_APP__TAGS__0': 'first',
          'ACME_APP__TAGS__1': 'second',
        },
      );

      // Act
      final Result<DieneConfig> loaded = await loader.load();

      // Assert
      expect(loaded, isOk, reason: describe(loaded));
      expect(loaded.unwrap().slice(appBlock).tags, <String>['first', 'second']);
    });

    test('a sparse index is rejected as a value', () async {
      // Arrange
      final ConfigLoader loader = loaderOf(
        defines: <String, String>{
          'ACME_APP__TAGS__0': 'first',
          'ACME_APP__TAGS__2': 'third',
        },
      );

      // Act
      final Result<DieneConfig> loaded = await loader.load();

      // Assert
      expect(loaded, isErr, reason: describe(loaded));
      expect(loaded.unwrapErr().data['code'], 'invalid_input');
    });

    test('a list index not starting at zero is rejected', () async {
      // Arrange
      final ConfigLoader loader = loaderOf(
        defines: <String, String>{'ACME_APP__TAGS__1': 'second'},
      );

      // Act
      final Result<DieneConfig> loaded = await loader.load();

      // Assert
      expect(loaded, isErr, reason: describe(loaded));
      expect(loaded.unwrapErr().data['code'], 'invalid_input');
    });

    test('mixing indexed and named children is rejected', () async {
      // Arrange
      final ConfigLoader loader = loaderOf(
        defines: <String, String>{
          'ACME_APP__TAGS__0': 'first',
          'ACME_APP__TAGS__NAMED': 'nope',
        },
      );

      // Act
      final Result<DieneConfig> loaded = await loader.load();

      // Assert
      expect(loaded, isErr, reason: describe(loaded));
      expect(loaded.unwrapErr().data['code'], 'invalid_input');
    });
  });

  group('define values are never decoded as JSON or comma lists', () {
    for (final String value in <String>['["a","b"]', 'a,b']) {
      test('$value stays a plain string', () async {
        // Arrange
        final ConfigLoader loader = loaderOf(
          defines: <String, String>{'ACME_APP__LABELS': value},
          rejectUnknownBlocks: false,
        );

        // Act
        final Result<DieneConfig> loaded = await loader.load();

        // Assert
        expect(loaded, isOk, reason: describe(loaded));
        expect(loaded.unwrap().rawSlice('app').unwrap()['labels'], value);
      });

      test('$value fails schema_invalid where a list is expected', () async {
        // Arrange
        final ConfigLoader loader = loaderOf(
          defines: <String, String>{'ACME_APP__TAGS': value},
        );

        // Act
        final Result<DieneConfig> loaded = await loader.load();

        // Assert
        expect(loaded, isErr, reason: describe(loaded));
        final Problem problem = loaded.unwrapErr();
        expect(problem.data['code'], ConfigProblemCode.schemaInvalid.wireId);
        expect(errorsOf(problem).single, startsWith('app: '));
      });
    }
  });

  group('define ingress failures keep the core-utils envelope', () {
    test(
      'an empty path component is reported unchanged, not re-minted',
      () async {
        // Arrange
        final ConfigLoader loader = loaderOf(
          defines: <String, String>{'ACME_APP____NAME': 'value'},
        );

        // Act
        final Result<DieneConfig> loaded = await loader.load();

        // Assert
        expect(loaded, isErr, reason: describe(loaded));
        final Problem problem = loaded.unwrapErr();
        expect(problem.data['util'], 'coercion');
        expect(problem.data['operation'], 'environmentToNestedMap');
        expect(problem.data['code'], 'invalid_input');
        expect(
          configProblemCode(problem).isNone,
          isTrue,
          reason: 'a core-utils code must not read as a config code',
        );
      },
    );

    test('a key that is only the prefix is rejected', () async {
      // Arrange
      final ConfigLoader loader = loaderOf(
        defines: <String, String>{'ACME_': 'value'},
      );

      // Act
      final Result<DieneConfig> loaded = await loader.load();

      // Assert
      expect(loaded, isErr, reason: describe(loaded));
      expect(loaded.unwrapErr().data['util'], 'coercion');
    });

    test('a scalar used as a parent is a conflict', () async {
      // Arrange
      final ConfigLoader loader = loaderOf(
        defines: <String, String>{
          'ACME_APP__NAME': 'scalar',
          'ACME_APP__NAME__CHILD': 'nope',
        },
      );

      // Act
      final Result<DieneConfig> loaded = await loader.load();

      // Assert
      expect(loaded, isErr, reason: describe(loaded));
      expect(loaded.unwrapErr().data['code'], 'conflict');
    });

    test('two keys normalising onto one path are a conflict', () async {
      // Arrange
      final ConfigLoader loader = loaderOf(
        defines: <String, String>{
          'ACME_APP__NAME': 'one',
          'ACME_APP__name': 'two',
        },
      );

      // Act
      final Result<DieneConfig> loaded = await loader.load();

      // Assert
      expect(loaded, isErr, reason: describe(loaded));
      expect(loaded.unwrapErr().data['code'], 'conflict');
    });

    test(
      'a separator-only path component becomes an ordinary nested key',
      () async {
        // Arrange
        final ConfigLoader loader = loaderOf(
          defines: <String, String>{'ACME_APP__---': 'value'},
        );

        // Act
        final Result<DieneConfig> loaded = await loader.load();

        // Assert
        expect(loaded, isOk, reason: describe(loaded));
        expect(loaded.unwrap().rawSlice('app').unwrap()['---'], 'value');
      },
    );

    test(
      'a separator-only root key is caught by the unknown-block check',
      () async {
        // Arrange
        final ConfigLoader loader = loaderOf(
          defines: <String, String>{'ACME_---': 'value'},
        );

        // Act
        final Result<DieneConfig> loaded = await loader.load();

        // Assert
        expect(loaded, isErr, reason: describe(loaded));
        final Problem problem = loaded.unwrapErr();
        expect(problem.data['code'], ConfigProblemCode.schemaInvalid.wireId);
        expect(errorsOf(problem).join(), contains('no composed block schema'));
      },
    );
  });

  group('layer read failures short-circuit', () {
    test('a failing base stops the load', () async {
      // Arrange
      final FakeConfigSource overlay = FakeConfigSource(<String, Object?>{});
      final ConfigLoader loader = ConfigLoader(
        base: const FailingConfigSource(name: 'base.yaml'),
        overlay: overlay,
        dartDefines: const DartDefineOverrides(prefix: 'ACME_'),
        schema: appSchema(),
      );

      // Act
      final Result<DieneConfig> loaded = await loader.load();

      // Assert
      expect(loaded, isErr, reason: describe(loaded));
      expect(
        loaded.unwrapErr().data['code'],
        ConfigProblemCode.sourceUnreadable.wireId,
      );
      expect(
        overlay.loadCount,
        0,
        reason: 'a later layer cannot repair a layer that never parsed',
      );
    });

    test('a failing overlay stops the load', () async {
      // Arrange
      final ConfigLoader loader = ConfigLoader(
        base: FakeConfigSource(<String, Object?>{
          'app': <String, Object?>{'name': 'base', 'retries': 0},
        }),
        overlay: const FailingConfigSource(
          name: 'overlay.yaml',
          code: ConfigProblemCode.sourceNotAMap,
        ),
        dartDefines: const DartDefineOverrides(prefix: 'ACME_'),
        schema: appSchema(),
      );

      // Act
      final Result<DieneConfig> loaded = await loader.load();

      // Assert
      expect(
        loaded.unwrapErr().data['code'],
        ConfigProblemCode.sourceNotAMap.wireId,
      );
    });

    test('a failing development override stops the load', () async {
      // Arrange
      final ConfigLoader loader = ConfigLoader(
        base: FakeConfigSource(<String, Object?>{
          'app': <String, Object?>{'name': 'base', 'retries': 0},
        }),
        developmentOverride: const FailingConfigSource(name: 'dev.yaml'),
        dartDefines: const DartDefineOverrides(prefix: 'ACME_'),
        schema: appSchema(),
      );

      // Act
      final Result<DieneConfig> loaded = await loader.load();

      // Assert
      expect(loaded, isErr, reason: describe(loaded));
      expect(loaded.unwrapErr().data['source'], 'dev.yaml');
    });
  });

  group('DartDefineOverrides', () {
    test('projects defines into a nested layer', () {
      // Arrange
      const DartDefineOverrides overrides = DartDefineOverrides(
        prefix: 'ACME_',
        values: <String, String>{'ACME_APP__NAME': 'value'},
      );

      // Act
      final Result<JsonObject> layer = overrides.layer();

      // Assert
      expect(layer, isOk, reason: describe(layer));
      expect(layer.unwrap(), <String, Object?>{
        'app': <String, Object?>{'name': 'value'},
      });
    });

    test('defaults to no values at all', () {
      // Arrange
      const DartDefineOverrides overrides = DartDefineOverrides(
        prefix: 'ACME_',
      );

      // Act
      final Result<JsonObject> layer = overrides.layer();

      // Assert
      expect(overrides.values, isEmpty);
      expect(layer.unwrap(), isEmpty);
    });

    test('matches its prefix case-insensitively', () async {
      // Arrange
      final ConfigLoader loader = loaderOf(
        defines: <String, String>{'acme_app__name': 'folded'},
      );

      // Act
      final Result<DieneConfig> loaded = await loader.load();

      // Assert
      expect(loaded.unwrap().slice(appBlock).name, 'folded');
    });

    test('ignores a key outside the prefix', () async {
      // Arrange
      final ConfigLoader loader = loaderOf(
        defines: <String, String>{'OTHER_APP__NAME': 'ignored'},
      );

      // Act
      final Result<DieneConfig> loaded = await loader.load();

      // Assert
      expect(loaded.unwrap().slice(appBlock).name, 'base');
    });

    test('a blank define is unset and cannot erase a base value', () async {
      // Arrange
      final ConfigLoader loader = loaderOf(
        defines: <String, String>{
          'ACME_APP__NAME': '',
          'ACME_APP__TAGS__0': '',
        },
      );

      // Act
      final Result<DieneConfig> loaded = await loader.load();

      // Assert
      expect(loaded, isOk, reason: describe(loaded));
      expect(
        loaded.unwrap().slice(appBlock),
        const AppSettings(name: 'base', retries: 1, tags: <String>['base']),
      );
    });

    test('coerces scalars but never decodes JSON or comma lists', () async {
      // Arrange
      final ConfigLoader loader = loaderOf(
        base: 'app:\n  name: base\n  retries: 0\n  tags: []\n',
        defines: <String, String>{
          'ACME_APP__RETRIES': '7',
          'ACME_APP__NAME': 'first,second',
        },
      );

      // Act
      final Result<DieneConfig> loaded = await loader.load();

      // Assert
      final AppSettings app = loaded.unwrap().slice(appBlock);
      expect(app.retries, 7, reason: 'an integer define coerces to int');
      expect(
        app.name,
        'first,second',
        reason: 'a comma string stays the string it is',
      );
    });

    test('a define lands on a differently spelled YAML key', () async {
      // Arrange
      final ConfigLoader loader = loaderOf(
        base: 'app:\n  name: base\n  retries: 0\n  displayName: yaml\n',
        defines: <String, String>{'ACME_APP__DISPLAY_NAME': 'define'},
        rejectUnknownBlocks: false,
      );

      // Act
      final Result<DieneConfig> loaded = await loader.load();

      // Assert
      final Map<String, Object?> app = loaded.unwrap().rawSlice('app').unwrap();
      expect(app['displayName'], 'define');
      expect(
        app.keys,
        isNot(contains('display_name')),
        reason: 'the base spelling wins as the output key',
      );
    });
  });
}
