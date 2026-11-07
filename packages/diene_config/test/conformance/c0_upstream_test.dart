import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:diene_config/c0_config.dart';
import 'package:diene_config/diene_config.dart' hide c0ConfigContract;
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

const String _upstreamPath = 'test/fixtures/c0/upstream';

Map<String, Object?> _object(Object? value) =>
    (value! as Map<Object?, Object?>).cast<String, Object?>();

List<Map<String, Object?>> _objects(Object? value) =>
    (value! as List<Object?>).map(_object).toList();

Map<String, String> _defines(Map<String, Object?> vector) =>
    _object(vector['defines']).cast<String, String>();

Object? _sortKeys(Object? value) {
  if (value is Map<Object?, Object?>) {
    final List<String> keys = value.keys.cast<String>().toList()..sort();
    return <String, Object?>{
      for (final String key in keys) key: _sortKeys(value[key]),
    };
  }
  if (value is List<Object?>) {
    return value.map(_sortKeys).toList();
  }
  return value;
}

String _canonical(Object? value) => '${jsonEncode(_sortKeys(value))}\n';

int _decodeCalls = 0;

final ConfigBlock<Map<String, Object?>> _app =
    ConfigBlock<Map<String, Object?>>(
      key: 'app',
      decode: (Map<String, Object?> values) {
        _decodeCalls += 1;
        final Object? name = values['name'];
        final Object? retries = values['retries'];
        if (name is! String || name.isEmpty) {
          throw FormatException('name must be a non-empty string, got $name');
        }
        if (retries is! int || retries < 0) {
          throw FormatException(
            'retries must be a non-negative int, got $retries',
          );
        }
        if (values['tags'] is! List<Object?>) {
          throw FormatException('tags must be a list, got ${values['tags']}');
        }
        return values;
      },
    );

final ConfigBlock<Object?> _anyApp = ConfigBlock<Object?>(
  key: 'app',
  decode: (Map<String, Object?> values) => values,
);

Future<Result<DieneConfig>> _load(
  Map<String, Object?> vector, {
  String? overlayKey,
  String? developmentKey,
  Map<String, String>? defines,
  ConfigBlock<Object?>? block,
}) {
  YamlConfigSource? layer(String? key) => key == null
      ? null
      : YamlConfigSource.string(vector[key]! as String, name: key);
  return ConfigLoader(
    base: YamlConfigSource.string(
      vector['baseYaml']! as String,
      name: 'baseYaml',
    ),
    overlay: layer(overlayKey),
    developmentOverride: layer(developmentKey),
    dartDefines: DartDefineOverrides(
      prefix: vector['prefix']! as String,
      values: defines ?? _defines(vector),
    ),
    schema: ConfigSchema(blocks: <ConfigBlockSchema>[block ?? _app]),
  ).load();
}

ConfigProblemCode? _code(Problem problem) => configProblemCode(
  problem,
).match(some: (ConfigProblemCode code) => code, none: () => null);

Map<String, Object?> _appOf(Result<DieneConfig> loaded) =>
    loaded.unwrap().rawSlice('app').unwrap();

Future<void> _checkBlankIsUnset(Map<String, Object?> vector) async {
  final Result<Map<String, Object?>> layer = DartDefineOverrides(
    prefix: vector['prefix']! as String,
    values: _defines(vector),
  ).layer();
  final Result<DieneConfig> loaded = await _load(vector);
  expect(_defines(vector).values, everyElement(isEmpty));
  expect(layer.unwrap(), isEmpty);
  expect(_appOf(loaded), vector['expected']);
}

Future<void> _checkCaseInsensitiveKeys(Map<String, Object?> vector) async {
  final List<Map<String, Object?>> variants = _objects(vector['variants']);
  final ConfigBlock<Object?> settings = ConfigBlock<Object?>(
    key: 'app-settings',
    decode: (Map<String, Object?> values) => values,
  );
  expect(variants, hasLength(3));
  for (final Map<String, Object?> variant in variants) {
    final String key = variant['defineKey']! as String;
    final Result<DieneConfig> loaded = await _load(
      vector,
      defines: <String, String>{key: variant['expectedValue']! as String},
      block: settings,
    );
    expect(loaded.unwrap().raw, <String, Object?>{
      'app-settings': <String, Object?>{
        'displayName': variant['expectedValue'],
      },
    }, reason: key);
  }
}

Future<void> _checkLayering(Map<String, Object?> vector) async {
  final Map<String, Object?> development = _appOf(
    await _load(
      vector,
      developmentKey: 'developmentYaml',
      defines: const <String, String>{},
      block: _anyApp,
    ),
  );
  final Map<String, Object?> withoutDefines = _appOf(
    await _load(
      vector,
      overlayKey: 'landscapeYaml',
      developmentKey: 'developmentYaml',
      defines: const <String, String>{},
      block: _anyApp,
    ),
  );
  final Map<String, Object?> merged = _appOf(
    await _load(
      vector,
      overlayKey: 'landscapeYaml',
      developmentKey: 'developmentYaml',
      block: _anyApp,
    ),
  );
  expect(development, <String, Object?>{
    'name': 'development',
    'retries': -1,
    'tags': <Object?>['development'],
  });
  expect(withoutDefines, <String, Object?>{
    'name': 'development',
    'retries': 2,
    'tags': <Object?>['development'],
  });
  expect(_defines(vector).keys, contains('ACME_APP__TAGS__1'));
  expect(merged, vector['expected']);
}

Future<void> _checkNoJsonNoComma(Map<String, Object?> vector) async {
  final List<Map<String, Object?>> rejected = _objects(vector['rejected']);
  expect(rejected, hasLength(2));
  for (final Map<String, Object?> entry in rejected) {
    final Result<DieneConfig> kept = await _load(entry, block: _anyApp);
    final Result<DieneConfig> strict = await _load(entry);
    expect(
      _appOf(kept)['tags'],
      _defines(entry).values.single,
      reason: entry['name'] as String?,
    );
    expect(
      _code(strict.unwrapErr()),
      ConfigProblemCode.schemaInvalid,
      reason: entry['name'] as String?,
    );
  }
}

Future<void> _checkFinalLayerValidation(Map<String, Object?> vector) async {
  final Map<String, Object?> invalid = _object(vector['invalid']);
  final String prefix = invalid['prefix']! as String;
  final Problem problem = (await _load(invalid)).unwrapErr();
  _decodeCalls = 0;
  final Result<DieneConfig> repaired = await _load(
    invalid,
    defines: <String, String>{'${prefix}APP__RETRIES': '5'},
  );
  expect(_defines(invalid), isEmpty);
  expect(_code(problem), ConfigProblemCode.schemaInvalid);
  expect(
    (problem.data['errors']! as List<Object?>).join(),
    contains('retries'),
  );
  expect(_appOf(repaired)['retries'], 5);
  expect(_decodeCalls, 1);
}

const Map<String, Future<void> Function(Map<String, Object?>)> _checks =
    <String, Future<void> Function(Map<String, Object?>)>{
      'blank_is_unset.json': _checkBlankIsUnset,
      'case_insensitive_key_matching.json': _checkCaseInsensitiveKeys,
      'final_layer_validation.json': _checkFinalLayerValidation,
      'layering_and_indexed_list.json': _checkLayering,
      'no_json_no_comma.json': _checkNoJsonNoComma,
    };

void main() {
  final Map<String, Object?> manifest = _object(
    jsonDecode(File('$_upstreamPath/manifest.json').readAsStringSync()),
  );
  final Map<String, Object?> vectors = _object(manifest['vectors']);

  test('manifest pins the source release and every checked case', () {
    // Arrange
    final Map<String, Object?> source = _object(manifest['source']);

    // Act
    final Set<String> cases = <String>{
      for (final Object? pin in vectors.values)
        (_object(pin)['pointer']! as String).split('/').last,
    };

    // Assert
    expect(manifest['authority'], c0ConfigContract.provenance.releaseId);
    expect(source['commit'], 'fe77520d591f81a9762c40ebf68dc9c0106502d3');
    expect(source['path'], c0ConfigContract.provenance.sourceCase);
    expect(vectors.keys.toSet(), _checks.keys.toSet());
    expect(cases, c0ConfigContract.projectedCases.toSet());
    for (final Object? pin in vectors.values) {
      expect(_object(pin)['reproduce'], contains('jq -cS'));
      expect(_object(pin)['adaptations'], isNotEmpty);
    }
  });

  group('upstream config cases', () {
    vectors.forEach((String name, Object? pin) {
      test(name, () async {
        // Arrange
        final List<int> bytes = File('$_upstreamPath/$name').readAsBytesSync();
        final Object? vector = jsonDecode(utf8.decode(bytes));

        // Act
        final String fileDigest = sha256.convert(bytes).toString();
        final String digest = sha256
            .convert(utf8.encode(_canonical(vector)))
            .toString();

        // Assert
        expect(
          fileDigest,
          _object(pin)['fileSha256'],
          reason:
              'upstream vector file "$name" digest drifted from the manifest',
        );
        expect(
          digest,
          _object(pin)['sha256'],
          reason: 'upstream vector "$name" digest drifted from the manifest',
        );
        await _checks[name]!(_object(vector));
      });
    });
  });
}
