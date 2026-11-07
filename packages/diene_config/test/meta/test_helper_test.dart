import 'package:diene_config/diene_config.dart';
import 'package:diene_config/test_helper.dart';
import 'package:diene_core_utils/diene_core_utils.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

import '../support.dart';

typedef Scenario = ({
  String name,
  bool expectOk,
  String baseYaml,
  Map<String, Object?> baseMap,
  String? overlayYaml,
  Map<String, Object?>? overlayMap,
  String? developmentYaml,
  Map<String, Object?>? developmentMap,
  Map<String, String> defines,
  bool rejectUnknownBlocks,
});

const String _baseYaml = '''
app:
  name: base
  retries: 1
  tags: [base]
''';

final Map<String, Object?> _baseMap = <String, Object?>{
  'app': <String, Object?>{
    'name': 'base',
    'retries': 1,
    'tags': <Object?>['base'],
  },
};

const String _overlayYaml = 'app:\n  name: overlay\n  retries: 2\n';

final Map<String, Object?> _overlayMap = <String, Object?>{
  'app': <String, Object?>{'name': 'overlay', 'retries': 2},
};

const String _developmentYaml = 'app:\n  tags: [development]\n';

final Map<String, Object?> _developmentMap = <String, Object?>{
  'app': <String, Object?>{
    'tags': <Object?>['development'],
  },
};

Scenario scenario(
  String name, {
  required bool expectOk,
  String baseYaml = _baseYaml,
  Map<String, Object?>? baseMap,
  String? overlayYaml,
  Map<String, Object?>? overlayMap,
  String? developmentYaml,
  Map<String, Object?>? developmentMap,
  Map<String, String> defines = const <String, String>{},
  bool rejectUnknownBlocks = true,
}) => (
  name: name,
  expectOk: expectOk,
  baseYaml: baseYaml,
  baseMap: baseMap ?? _baseMap,
  overlayYaml: overlayYaml,
  overlayMap: overlayMap,
  developmentYaml: developmentYaml,
  developmentMap: developmentMap,
  defines: defines,
  rejectUnknownBlocks: rejectUnknownBlocks,
);

final List<Scenario> matrix = <Scenario>[
  scenario('base only', expectOk: true),
  scenario(
    'base and overlay',
    expectOk: true,
    overlayYaml: _overlayYaml,
    overlayMap: _overlayMap,
  ),
  scenario(
    'base, overlay and development hook',
    expectOk: true,
    overlayYaml: _overlayYaml,
    overlayMap: _overlayMap,
    developmentYaml: _developmentYaml,
    developmentMap: _developmentMap,
  ),
  scenario(
    'the full ladder with indexed defines',
    expectOk: true,
    overlayYaml: _overlayYaml,
    overlayMap: _overlayMap,
    developmentYaml: _developmentYaml,
    developmentMap: _developmentMap,
    defines: <String, String>{
      'TEST_APP__NAME': 'define',
      'TEST_APP__TAGS__0': 'first',
      'TEST_APP__TAGS__1': 'second',
    },
  ),
  scenario(
    'a blank define is unset',
    expectOk: true,
    defines: <String, String>{'TEST_APP__NAME': ''},
  ),
  scenario(
    'an invalid base repaired by an overlay',
    expectOk: true,
    baseYaml: 'app:\n  name: base\n  retries: -1\n',
    baseMap: <String, Object?>{
      'app': <String, Object?>{'name': 'base', 'retries': -1},
    },
    overlayYaml: 'app:\n  retries: 3\n',
    overlayMap: <String, Object?>{
      'app': <String, Object?>{'retries': 3},
    },
  ),
  scenario(
    'nested maps merge',
    expectOk: true,
    baseYaml:
        'app:\n'
        '  name: base\n'
        '  retries: 0\n'
        '  nested:\n'
        '    kept: true\n'
        '    replaced: false\n',
    baseMap: <String, Object?>{
      'app': <String, Object?>{
        'name': 'base',
        'retries': 0,
        'nested': <String, Object?>{'kept': true, 'replaced': false},
      },
    },
    overlayYaml: 'app:\n  nested:\n    replaced: true\n',
    overlayMap: <String, Object?>{
      'app': <String, Object?>{
        'nested': <String, Object?>{'replaced': true},
      },
    },
    rejectUnknownBlocks: false,
  ),
  scenario(
    'an invalid final tree',
    expectOk: false,
    baseYaml: 'app:\n  name: service\n  retries: -1\n',
    baseMap: <String, Object?>{
      'app': <String, Object?>{'name': 'service', 'retries': -1},
    },
  ),
  scenario(
    'a malformed define key',
    expectOk: false,
    defines: <String, String>{'TEST_APP____NAME': 'bad'},
  ),
  scenario(
    'a sparse indexed define',
    expectOk: false,
    defines: <String, String>{'TEST_APP__TAGS__1': 'second'},
  ),
  scenario(
    'an unknown root key',
    expectOk: false,
    overlayYaml: 'unknown: {}\n',
    overlayMap: <String, Object?>{'unknown': <String, Object?>{}},
  ),
  scenario(
    'a JSON define where a list is expected',
    expectOk: false,
    defines: <String, String>{'TEST_APP__TAGS': '["a","b"]'},
  ),
];

Future<Result<DieneConfig>> viaReal(Scenario s) {
  final String? overlay = s.overlayYaml;
  final String? development = s.developmentYaml;
  return ConfigLoader(
    base: YamlConfigSource.string(s.baseYaml, name: 'base.yaml'),
    overlay: overlay == null ? null : YamlConfigSource.string(overlay),
    developmentOverride: development == null
        ? null
        : YamlConfigSource.string(development),
    dartDefines: DartDefineOverrides(prefix: 'TEST_', values: s.defines),
    schema: appSchema(rejectUnknownBlocks: s.rejectUnknownBlocks),
  ).load();
}

Future<Result<DieneConfig>> viaFake(Scenario s) => FakeConfigHarness(
  base: s.baseMap,
  overlay: s.overlayMap,
  developmentOverride: s.developmentMap,
  defines: s.defines,
  schema: appSchema(rejectUnknownBlocks: s.rejectUnknownBlocks),
).load();

void expectParity(
  Result<DieneConfig> fake,
  Result<DieneConfig> real,
  String label,
) {
  expect(
    fake.isOk,
    real.isOk,
    reason: '$label: fake=${describe(fake)} real=${describe(real)}',
  );
  if (fake.isOk) {
    expect(
      fake.unwrap().raw,
      real.unwrap().raw,
      reason: '$label: merged trees differ',
    );
    expect(
      fake.unwrap().slice(appBlock),
      real.unwrap().slice(appBlock),
      reason: '$label: typed slices differ',
    );
    return;
  }
  expect(
    fake.unwrapErr(),
    real.unwrapErr(),
    reason: '$label: failure envelopes differ',
  );
}

Result<String> landscapeOutcome(LandscapeSource source) =>
    landscape(source: source);

void main() {
  group('FakeConfigSource', () {
    test('reports the values it was built with', () async {
      // Arrange
      final FakeConfigSource source = FakeConfigSource(<String, Object?>{
        'app': <String, Object?>{'name': 'fake'},
      });

      // Act
      final Result<JsonObject> loaded = await source.load();

      // Assert
      expect(loaded, isOk, reason: describe(loaded));
      expect((loaded.unwrap()['app']! as JsonObject)['name'], 'fake');
    });

    test('counts every load', () async {
      // Arrange
      final FakeConfigSource source = FakeConfigSource(<String, Object?>{});

      // Act
      await source.load();
      await source.load();

      // Assert
      expect(source.loadCount, 2);
    });

    test('is not corrupted by mutating the map it was built from', () async {
      // Arrange
      final Map<String, Object?> seed = <String, Object?>{
        'app': <String, Object?>{'name': 'original'},
      };
      final FakeConfigSource source = FakeConfigSource(seed);

      // Act
      (seed['app']! as Map<String, Object?>)['name'] = 'mutated';

      // Assert
      expect(
        ((await source.load()).unwrap()['app']! as JsonObject)['name'],
        'original',
      );
    });

    test('is not corrupted by mutating a previous load result', () async {
      // Arrange
      final FakeConfigSource source = FakeConfigSource(<String, Object?>{
        'app': <String, Object?>{'name': 'original'},
      });

      // Act
      final JsonObject first = (await source.load()).unwrap();
      (first['app']! as JsonObject)['name'] = 'mutated';

      // Assert
      expect(
        ((await source.load()).unwrap()['app']! as JsonObject)['name'],
        'original',
      );
    });
  });

  group('FailingConfigSource', () {
    test('fails with its declared code and name', () async {
      // Arrange
      const ConfigSource source = FailingConfigSource(
        name: 'overlay.yaml',
        code: ConfigProblemCode.sourceNotAMap,
        message: 'deliberate',
      );

      // Act
      final Result<JsonObject> loaded = await source.load();

      // Assert
      expect(loaded, isErr, reason: describe(loaded));
      final Problem problem = loaded.unwrapErr();
      expect(problem.data['code'], ConfigProblemCode.sourceNotAMap.wireId);
      expect(problem.data['source'], 'overlay.yaml');
      expect(problem.title, 'deliberate');
    });

    test('defaults to an unreadable-source failure', () async {
      // Arrange
      const ConfigSource source = FailingConfigSource();

      // Act
      final Result<JsonObject> loaded = await source.load();

      // Assert
      expect(
        loaded.unwrapErr().data['code'],
        ConfigProblemCode.sourceUnreadable.wireId,
      );
    });
  });

  group('FakeLandscapeSource', () {
    test('drives landscape() to its injected value', () {
      // Arrange
      const LandscapeSource source = FakeLandscapeSource('lapras');

      // Act
      final Result<String> track = landscape(source: source);

      // Assert
      expect(track.unwrap(), 'lapras');
    });

    test('an empty value fakes an absent define', () {
      // Arrange
      const LandscapeSource source = FakeLandscapeSource('');

      // Act
      final Result<String> track = landscape(source: source);

      // Assert
      expect(track, isErr, reason: describe(track));
      expect(
        track.unwrapErr().data['code'],
        ConfigProblemCode.landscapeMissing.wireId,
      );
    });
  });

  group('ConfigStubBuilder', () {
    test('builds a stub through the real schema path', () {
      // Arrange
      final ConfigStubBuilder builder = ConfigStubBuilder().add(
        appBlock,
        <String, Object?>{
          'name': 'stub',
          'retries': 1,
          'tags': <Object?>['x'],
        },
      );

      // Act
      final DieneConfig config = builder.build();

      // Assert
      expect(
        config.slice(appBlock),
        const AppSettings(name: 'stub', retries: 1, tags: <String>['x']),
      );
      expect(
        () => config.raw['app'] = null,
        throwsUnsupportedError,
        reason: 'a stub must be as immutable as a loaded config',
      );
    });

    test('build throws on a stub the loader would reject', () {
      // Arrange
      final ConfigStubBuilder builder = ConfigStubBuilder().add(
        appBlock,
        <String, Object?>{'name': '', 'retries': -1},
      );

      // Act
      DieneConfig build() => builder.build();

      // Assert
      expect(
        build,
        throwsA(
          isA<ConfigAssertionFailure>().having(
            (ConfigAssertionFailure error) => error.message,
            'message',
            allOf(contains('INVALID stub'), contains('non-empty string')),
          ),
        ),
      );
    });

    test('addRaw introduces an unknown root key, rejected by default', () {
      // Arrange
      final ConfigStubBuilder builder = ConfigStubBuilder()
          .add(appBlock, <String, Object?>{'name': 'a', 'retries': 0})
          .addRaw('extra', <String, Object?>{'x': 1});

      // Act
      DieneConfig build() => builder.build();

      // Assert
      expect(build, throwsA(isA<ConfigAssertionFailure>()));
    });

    test('addRaw is accepted when unknown blocks are tolerated', () {
      // Arrange
      final ConfigStubBuilder builder = ConfigStubBuilder()
          .add(appBlock, <String, Object?>{'name': 'a', 'retries': 0})
          .addRaw('extra', <String, Object?>{'x': 1});

      // Act
      final DieneConfig config = builder.build(rejectUnknownBlocks: false);

      // Assert
      expect(config.rawSlice('extra').unwrap()['x'], 1);
    });

    test('tryBuild returns the failure instead of throwing', () {
      // Arrange
      final ConfigStubBuilder builder = ConfigStubBuilder().add(
        appBlock,
        <String, Object?>{'name': '', 'retries': 0},
      );

      // Act
      final Result<DieneConfig> built = builder.tryBuild();

      // Assert
      expect(built, isErr, reason: describe(built));
      expect(
        built.unwrapErr().data['code'],
        ConfigProblemCode.schemaInvalid.wireId,
      );
    });

    test('tryBuild succeeds on a valid stub', () {
      // Arrange
      final ConfigStubBuilder builder = ConfigStubBuilder().add(
        appBlock,
        <String, Object?>{'name': 'ok', 'retries': 0},
      );

      // Act
      final Result<DieneConfig> built = builder.tryBuild();

      // Assert
      expect(built, isOk, reason: describe(built));
    });

    test('chains fluently across several blocks', () {
      // Arrange
      final ConfigBlock<String> apiBlock = ConfigBlock<String>(
        key: 'api',
        decode: (Map<String, Object?> values) => values['baseUrl']! as String,
      );

      // Act
      final DieneConfig config = ConfigStubBuilder()
          .add(appBlock, <String, Object?>{'name': 'a', 'retries': 0})
          .add(apiBlock, <String, Object?>{'baseUrl': 'https://api.test'})
          .build();

      // Assert
      expect(config.slice(apiBlock), 'https://api.test');
    });
  });

  group('FakeConfigHarness', () {
    test('exposes the fakes it wired, for load-count assertions', () async {
      // Arrange
      final FakeConfigHarness harness = FakeConfigHarness(
        base: <String, Object?>{
          'app': <String, Object?>{'name': 'base', 'retries': 0},
        },
        overlay: <String, Object?>{
          'app': <String, Object?>{'name': 'overlay'},
        },
        schema: appSchema(),
      );

      // Act
      await harness.load();

      // Assert
      expect(harness.baseSource.loadCount, 1);
      expect(harness.overlaySource!.loadCount, 1);
      expect(harness.developmentSource, isNull);
    });

    test(
      'omits an overlay and development layer that were not supplied',
      () async {
        // Arrange
        final FakeConfigHarness harness = FakeConfigHarness(
          base: <String, Object?>{
            'app': <String, Object?>{'name': 'base', 'retries': 0},
          },
          schema: appSchema(),
        );

        // Act
        final Result<DieneConfig> loaded = await harness.load();

        // Assert
        expect(harness.overlaySource, isNull);
        expect(harness.loader.overlay, isNull);
        expect(harness.loader.developmentOverride, isNull);
        expect(loaded.unwrap().slice(appBlock).name, 'base');
      },
    );

    test('drives the real ConfigLoader, not a reimplementation', () {
      // Arrange
      final FakeConfigHarness harness = FakeConfigHarness(
        base: <String, Object?>{},
        schema: appSchema(),
      );

      // Act
      final ConfigLoader loader = harness.loader;

      // Assert
      expect(loader, isA<ConfigLoader>());
      expect(loader.schema, same(harness.schema));
      expect(loader.dartDefines.prefix, 'TEST_');
    });
  });

  group('expectOkConfig', () {
    test('returns the configuration on a known-good input', () {
      // Arrange
      final Result<DieneConfig> ok = appSchema().validate(<String, Object?>{
        'app': <String, Object?>{'name': 'ok', 'retries': 0},
      });

      // Act
      final DieneConfig config = expectOkConfig(ok);

      // Assert
      expect(config.slice(appBlock).name, 'ok');
    });

    test('throws on a known-bad input, naming the schema errors', () {
      // Arrange
      final Result<DieneConfig> err = appSchema().validate(<String, Object?>{});

      // Act
      DieneConfig check() => expectOkConfig(err);

      // Assert
      expect(
        check,
        throwsA(
          isA<ConfigAssertionFailure>()
              .having(
                (ConfigAssertionFailure error) => error,
                'is a StateError',
                isA<StateError>(),
              )
              .having(
                (ConfigAssertionFailure error) => error.message,
                'message',
                allOf(
                  contains('load FAILED'),
                  contains('app: required block is missing'),
                ),
              ),
        ),
      );
    });

    test('throws on a failure that carries no error list', () async {
      // Arrange
      final Result<DieneConfig> err = await ConfigLoader(
        base: const FailingConfigSource(name: 'base.yaml'),
        dartDefines: const DartDefineOverrides(prefix: 'TEST_'),
        schema: appSchema(),
      ).load();

      // Act
      DieneConfig check() => expectOkConfig(err);

      // Assert
      expect(
        check,
        throwsA(
          isA<ConfigAssertionFailure>().having(
            (ConfigAssertionFailure error) => error.message,
            'message',
            allOf(contains('load FAILED'), isNot(contains('\n- '))),
          ),
        ),
      );
    });
  });

  group('expectErrConfig', () {
    test('returns the problem on a known-good input', () {
      // Arrange
      final Result<DieneConfig> err = appSchema().validate(<String, Object?>{});

      // Act
      final Problem problem = expectErrConfig(err);

      // Assert
      expect(problem.data['code'], ConfigProblemCode.schemaInvalid.wireId);
    });

    test('throws on a known-bad input, showing the configuration it got', () {
      // Arrange
      final Result<DieneConfig> ok = appSchema().validate(<String, Object?>{
        'app': <String, Object?>{'name': 'unexpected', 'retries': 0},
      });

      // Act
      Problem check() => expectErrConfig(ok);

      // Assert
      expect(
        check,
        throwsA(
          isA<ConfigAssertionFailure>().having(
            (ConfigAssertionFailure error) => error.message,
            'message',
            allOf(
              contains('Expected the load to FAIL'),
              contains('unexpected'),
            ),
          ),
        ),
      );
    });
  });

  group('assertConfigProblem', () {
    test('accepts the matching code and returns the problem', () {
      // Arrange
      final Result<DieneConfig> err = appSchema().validate(<String, Object?>{});

      // Act
      final Problem problem = assertConfigProblem(
        err,
        ConfigProblemCode.schemaInvalid,
      );

      // Assert
      expect(problem.status, 422);
    });

    test('throws on a different config code', () {
      // Arrange
      final Result<DieneConfig> err = appSchema().validate(<String, Object?>{});

      // Act
      Problem check() =>
          assertConfigProblem(err, ConfigProblemCode.sourceUnreadable);

      // Assert
      expect(
        check,
        throwsA(
          isA<ConfigAssertionFailure>().having(
            (ConfigAssertionFailure error) => error.message,
            'message',
            allOf(
              contains('Expected config problem "source_unreadable"'),
              contains('"schema_invalid"'),
            ),
          ),
        ),
      );
    });

    test(
      'throws on a foreign envelope rather than misreading its code',
      () async {
        // Arrange
        final Result<DieneConfig> err = await ConfigLoader(
          base: FakeConfigSource(<String, Object?>{
            'app': <String, Object?>{'name': 'base', 'retries': 0},
          }),
          dartDefines: const DartDefineOverrides(
            prefix: 'ACME_',
            values: <String, String>{'ACME_APP____NAME': 'bad'},
          ),
          schema: appSchema(),
        ).load();

        // Act
        Problem check() =>
            assertConfigProblem(err, ConfigProblemCode.schemaInvalid);

        // Assert
        expect(err.unwrapErr().data['code'], 'invalid_input');
        expect(check, throwsA(isA<ConfigAssertionFailure>()));
      },
    );

    test('throws when the result actually succeeded', () {
      // Arrange
      final Result<DieneConfig> ok = appSchema().validate(<String, Object?>{
        'app': <String, Object?>{'name': 'ok', 'retries': 0},
      });

      // Act
      Problem check() =>
          assertConfigProblem(ok, ConfigProblemCode.schemaInvalid);

      // Assert
      expect(check, throwsA(isA<ConfigAssertionFailure>()));
    });
  });

  group('assertConfigSlice', () {
    test('accepts the matching slice', () {
      // Arrange
      final DieneConfig config = ConfigStubBuilder().add(
        appBlock,
        <String, Object?>{'name': 'sliced', 'retries': 2},
      ).build();

      // Act
      void check() => assertConfigSlice(
        config,
        appBlock,
        const AppSettings(name: 'sliced', retries: 2, tags: <String>[]),
      );

      // Assert
      expect(check, returnsNormally);
    });

    test('throws on a mismatched slice, showing both values', () {
      // Arrange
      final DieneConfig config = ConfigStubBuilder().add(
        appBlock,
        <String, Object?>{'name': 'actual', 'retries': 0},
      ).build();

      // Act
      void check() => assertConfigSlice(
        config,
        appBlock,
        const AppSettings(name: 'expected', retries: 0, tags: <String>[]),
      );

      // Assert
      expect(
        check,
        throwsA(
          isA<ConfigAssertionFailure>().having(
            (ConfigAssertionFailure error) => error.message,
            'message',
            allOf(contains('expected'), contains('actual')),
          ),
        ),
      );
    });

    test('propagates the StateError for a block that was never composed', () {
      // Arrange
      final DieneConfig config = ConfigStubBuilder().add(
        appBlock,
        <String, Object?>{'name': 'a', 'retries': 0},
      ).build();
      final ConfigBlock<int> absent = ConfigBlock<int>(
        key: 'absent',
        decode: (_) => 0,
      );

      // Act
      void check() => assertConfigSlice(config, absent, 0);

      // Assert
      expect(check, throwsStateError);
    });
  });

  group('ConfigAssertionFailure', () {
    test('is catchable as a StateError', () {
      // Arrange
      const String diagnostic = 'diagnostic';

      // Act
      final ConfigAssertionFailure failure = ConfigAssertionFailure(diagnostic);

      // Assert
      expect(failure, isA<StateError>());
      expect(failure.message, diagnostic);
    });
  });

  group('fake and real loaders agree on the scenario matrix', () {
    for (final Scenario s in matrix) {
      test(s.name, () async {
        // Arrange
        final Scenario current = s;

        // Act
        final Result<DieneConfig> fake = await viaFake(current);
        final Result<DieneConfig> real = await viaReal(current);

        // Assert
        expectParity(fake, real, current.name);
        expect(real.isOk, current.expectOk, reason: describe(real));
      });
    }

    test('the full ladder lands on the expected slice', () async {
      // Arrange
      final Scenario full = matrix.singleWhere(
        (Scenario s) => s.name == 'the full ladder with indexed defines',
      );

      // Act
      final Result<DieneConfig> real = await viaReal(full);

      // Assert
      assertConfigSlice(
        expectOkConfig(real),
        appBlock,
        const AppSettings(
          name: 'define',
          retries: 2,
          tags: <String>['first', 'second'],
        ),
      );
    });

    test('an invalid final tree is schema_invalid through both', () async {
      // Arrange
      final Scenario invalid = matrix.singleWhere(
        (Scenario s) => s.name == 'an invalid final tree',
      );

      // Act
      final Result<DieneConfig> fake = await viaFake(invalid);
      final Result<DieneConfig> real = await viaReal(invalid);

      // Assert
      expect(
        assertConfigProblem(fake, ConfigProblemCode.schemaInvalid),
        assertConfigProblem(real, ConfigProblemCode.schemaInvalid),
      );
    });

    test('the parity comparator rejects a divergence', () {
      // Arrange
      final Result<DieneConfig> ok = appSchema().validate(<String, Object?>{
        'app': <String, Object?>{'name': 'a', 'retries': 0},
      });
      final Result<DieneConfig> otherOk = appSchema().validate(
        <String, Object?>{
          'app': <String, Object?>{'name': 'DIFFERENT', 'retries': 0},
        },
      );
      final Result<DieneConfig> err = appSchema().validate(<String, Object?>{});
      final Result<DieneConfig> otherErr = appSchema().validate(
        <String, Object?>{'app': 'not a map'},
      );

      // Act
      void channels() => expectParity(ok, err, 'channel divergence');
      void values() => expectParity(ok, otherOk, 'value divergence');
      void problems() => expectParity(err, otherErr, 'problem divergence');

      // Assert
      expect(channels, throwsA(isA<TestFailure>()));
      expect(values, throwsA(isA<TestFailure>()));
      expect(problems, throwsA(isA<TestFailure>()));
    });
  });

  group('FakeConfigSource and YAML text give the same layer', () {
    test('a nested document', () async {
      // Arrange
      final ConfigSource fake = FakeConfigSource(_baseMap);
      final ConfigSource real = YamlConfigSource.string(_baseYaml);

      // Act
      final Result<JsonObject> viaFakeSource = await fake.load();
      final Result<JsonObject> viaYaml = await real.load();

      // Assert
      expect(viaFakeSource.unwrap(), viaYaml.unwrap());
    });

    test('an empty document', () async {
      // Arrange
      final ConfigSource fake = FakeConfigSource(<String, Object?>{});
      final ConfigSource real = YamlConfigSource.string('');

      // Act
      final Result<JsonObject> viaFakeSource = await fake.load();
      final Result<JsonObject> viaYaml = await real.load();

      // Assert
      expect(viaFakeSource.unwrap(), viaYaml.unwrap());
    });
  });

  group('FailingConfigSource and a failing YAML layer fail the same way', () {
    test('an unreadable layer', () async {
      // Arrange
      final ConfigLoader fake = ConfigLoader(
        base: const FailingConfigSource(name: 'base.yaml'),
        dartDefines: const DartDefineOverrides(prefix: 'TEST_'),
        schema: appSchema(),
      );
      final ConfigLoader real = ConfigLoader(
        base: YamlConfigSource(
          name: 'base.yaml',
          read: () => throw StateError('missing'),
        ),
        dartDefines: const DartDefineOverrides(prefix: 'TEST_'),
        schema: appSchema(),
      );

      // Act
      final Problem viaFakeSource = assertConfigProblem(
        await fake.load(),
        ConfigProblemCode.sourceUnreadable,
      );
      final Problem viaYaml = assertConfigProblem(
        await real.load(),
        ConfigProblemCode.sourceUnreadable,
      );

      // Assert
      expect(viaFakeSource.type, viaYaml.type);
      expect(viaFakeSource.status, viaYaml.status);
      expect(viaFakeSource.data['source'], viaYaml.data['source']);
    });

    test('a layer whose root is not a map', () async {
      // Arrange
      final ConfigLoader fake = ConfigLoader(
        base: FakeConfigSource(_baseMap),
        overlay: const FailingConfigSource(
          name: 'overlay.yaml',
          code: ConfigProblemCode.sourceNotAMap,
        ),
        dartDefines: const DartDefineOverrides(prefix: 'TEST_'),
        schema: appSchema(),
      );
      final ConfigLoader real = ConfigLoader(
        base: YamlConfigSource.string(_baseYaml),
        overlay: YamlConfigSource.string('- a\n', name: 'overlay.yaml'),
        dartDefines: const DartDefineOverrides(prefix: 'TEST_'),
        schema: appSchema(),
      );

      // Act
      final Problem viaFakeSource = assertConfigProblem(
        await fake.load(),
        ConfigProblemCode.sourceNotAMap,
      );
      final Problem viaYaml = assertConfigProblem(
        await real.load(),
        ConfigProblemCode.sourceNotAMap,
      );

      // Assert
      expect(viaFakeSource.type, viaYaml.type);
      expect(viaFakeSource.status, viaYaml.status);
      expect(viaFakeSource.data['source'], viaYaml.data['source']);
    });
  });

  group('FakeLandscapeSource and the define source agree', () {
    for (final String value in <String>['lapras', '  pichu \n', '', '   ']) {
      test('for ${value.trim().isEmpty ? 'a blank value' : value.trim()}', () {
        // Arrange
        final LandscapeSource fake = FakeLandscapeSource(value);
        final LandscapeSource real = DartDefineLandscapeSource(value: value);

        // Act
        final Result<String> viaFakeSource = landscapeOutcome(fake);
        final Result<String> viaDefine = landscapeOutcome(real);

        // Assert
        expect(viaFakeSource.isOk, viaDefine.isOk);
        expect(
          viaFakeSource.match(ok: (String v) => v, err: (Problem p) => p),
          viaDefine.match(ok: (String v) => v, err: (Problem p) => p),
        );
      });
    }
  });

  group('ConfigStubBuilder and the real loader agree', () {
    test('on a valid tree', () async {
      // Arrange
      final ConfigStubBuilder builder = ConfigStubBuilder().add(
        appBlock,
        _baseMap['app']! as Map<String, Object?>,
      );
      final ConfigLoader loader = ConfigLoader(
        base: YamlConfigSource.string(_baseYaml),
        dartDefines: const DartDefineOverrides(prefix: 'TEST_'),
        schema: appSchema(),
      );

      // Act
      final DieneConfig stub = builder.build();
      final DieneConfig loaded = expectOkConfig(await loader.load());

      // Assert
      expect(stub.raw, loaded.raw);
      expect(stub.slice(appBlock), loaded.slice(appBlock));
    });

    test('on an invalid tree', () async {
      // Arrange
      final ConfigStubBuilder builder = ConfigStubBuilder().add(
        appBlock,
        <String, Object?>{'name': 'service', 'retries': -1},
      );
      final ConfigLoader loader = ConfigLoader(
        base: YamlConfigSource.string('app:\n  name: service\n  retries: -1\n'),
        dartDefines: const DartDefineOverrides(prefix: 'TEST_'),
        schema: appSchema(),
      );

      // Act
      final Problem stub = expectErrConfig(builder.tryBuild());
      final Problem loaded = expectErrConfig(await loader.load());

      // Assert
      expect(stub, loaded);
      expect(builder.build, throwsA(isA<ConfigAssertionFailure>()));
    });
  });
}
