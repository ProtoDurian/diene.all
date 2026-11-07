/// Test fakes and assertions for `diene_config`; imports no test framework.
library;

import 'dart:async';

import 'package:diene_core_utils/diene_core_utils.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';

import 'diene_config.dart';

/// Thrown when a `diene_config` assertion fails.
final class ConfigAssertionFailure extends StateError {
  ConfigAssertionFailure(super.message);
}

/// An in-memory layer that counts its loads.
final class FakeConfigSource implements ConfigSource {
  FakeConfigSource(Map<String, Object?> values)
    : _values = deepClone(values)! as JsonObject;

  final JsonObject _values;

  int loadCount = 0;

  @override
  Future<Result<JsonObject>> load() async {
    loadCount += 1;
    return Ok<JsonObject>(deepClone(_values)! as JsonObject);
  }
}

/// A layer that always fails.
final class FailingConfigSource implements ConfigSource {
  const FailingConfigSource({
    this.name = 'failing',
    this.code = ConfigProblemCode.sourceUnreadable,
    this.message = 'fake layer failure',
  });

  /// Reported as `data.source`.
  final String name;

  final ConfigProblemCode code;

  final String message;

  @override
  Future<Result<JsonObject>> load() async => configFailure<JsonObject>(
    code: code,
    message: message,
    details: <String, Object?>{'source': name},
  );
}

/// A fixed landscape; `''` fakes a missing define.
final class FakeLandscapeSource implements LandscapeSource {
  const FakeLandscapeSource(this.value);

  final String value;

  @override
  String read() => value;
}

/// Builds a [DieneConfig] through the real [ConfigSchema.validate].
final class ConfigStubBuilder {
  final Map<String, Object?> _raw = <String, Object?>{};
  final List<ConfigBlockSchema> _blocks = <ConfigBlockSchema>[];

  ConfigStubBuilder add<T>(ConfigBlock<T> block, Map<String, Object?> values) {
    _blocks.add(block);
    _raw[block.key] = values;
    return this;
  }

  /// Adds a root key with no composed block.
  ConfigStubBuilder addRaw(String key, Object? value) {
    _raw[key] = value;
    return this;
  }

  /// Throws [ConfigAssertionFailure] when the stub does not validate.
  DieneConfig build({bool rejectUnknownBlocks = true}) {
    final Result<DieneConfig> validated = ConfigSchema(
      blocks: _blocks,
      rejectUnknownBlocks: rejectUnknownBlocks,
    ).validate(_raw);
    return validated.match(
      ok: (DieneConfig config) => config,
      err: (Problem problem) => throw ConfigAssertionFailure(
        'ConfigStubBuilder produced an INVALID stub: '
        '${_describeProblem(problem)}',
      ),
    );
  }

  Result<DieneConfig> tryBuild({bool rejectUnknownBlocks = true}) =>
      ConfigSchema(
        blocks: _blocks,
        rejectUnknownBlocks: rejectUnknownBlocks,
      ).validate(_raw);
}

/// The real [ConfigLoader] over in-memory layers.
final class FakeConfigHarness {
  FakeConfigHarness({
    required this.base,
    required this.schema,
    this.overlay,
    this.developmentOverride,
    this.defines = const <String, String>{},
    this.prefix = 'TEST_',
  }) : baseSource = FakeConfigSource(base),
       overlaySource = overlay == null ? null : FakeConfigSource(overlay),
       developmentSource = developmentOverride == null
           ? null
           : FakeConfigSource(developmentOverride);

  final Map<String, Object?> base;

  final Map<String, Object?>? overlay;

  final Map<String, Object?>? developmentOverride;

  final Map<String, String> defines;

  final String prefix;

  final ConfigSchema schema;

  final FakeConfigSource baseSource;

  final FakeConfigSource? overlaySource;

  final FakeConfigSource? developmentSource;

  ConfigLoader get loader => ConfigLoader(
    base: baseSource,
    overlay: overlaySource,
    developmentOverride: developmentSource,
    dartDefines: DartDefineOverrides(prefix: prefix, values: defines),
    schema: schema,
  );

  Future<Result<DieneConfig>> load() => loader.load();
}

/// Returns the config, or throws with the problem's details.
DieneConfig expectOkConfig(Result<DieneConfig> result) => result.match(
  ok: (DieneConfig config) => config,
  err: (Problem problem) => throw ConfigAssertionFailure(
    'Expected a valid configuration but the load FAILED: '
    '${_describeProblem(problem)}',
  ),
);

/// Returns the problem, or throws when the load succeeded.
Problem expectErrConfig(Result<DieneConfig> result) => result.match(
  ok: (DieneConfig config) => throw ConfigAssertionFailure(
    'Expected the load to FAIL but it produced a valid configuration: '
    '${config.raw}',
  ),
  err: (Problem problem) => problem,
);

/// Returns the problem when [result] failed with the config-owned [code].
Problem assertConfigProblem(
  Result<DieneConfig> result,
  ConfigProblemCode code,
) {
  final Problem problem = expectErrConfig(result);
  final Option<ConfigProblemCode> actual = configProblemCode(problem);
  final bool matches = actual.match(
    some: (ConfigProblemCode found) => found == code,
    none: () => false,
  );
  if (!matches) {
    throw ConfigAssertionFailure(
      'Expected config problem "${code.wireId}" but found '
      '"${problem.data['code']}": ${_describeProblem(problem)}',
    );
  }
  return problem;
}

/// Compares with the slice type's own `==`.
void assertConfigSlice<T>(
  DieneConfig config,
  ConfigBlock<T> block,
  T expected,
) {
  final T actual = config.slice<T>(block);
  if (actual != expected) {
    throw ConfigAssertionFailure(
      'Expected slice "${block.key}" to be <$expected> but found <$actual>.',
    );
  }
}

String _describeProblem(Problem problem) {
  final Object? errors = problem.data['errors'];
  final String suffix = errors is List<Object?>
      ? '\n- ${errors.join('\n- ')}'
      : '';
  return '${problem.status} ${problem.title} (${problem.detail})$suffix';
}
