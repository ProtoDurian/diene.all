import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:diene_core_utils/diene_core_utils.dart';
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

// Reads only what the vectors use: one nested map level, scalars, [a, b].
JsonObject _readYaml(String source) {
  final JsonObject root = <String, Object?>{};
  JsonObject cursor = root;
  for (final String raw in const LineSplitter().convert(source)) {
    if (raw.trim().isEmpty) {
      continue;
    }
    final bool nested = raw.startsWith(' ');
    final String line = raw.trim();
    final int colon = line.indexOf(':');
    final String key = line.substring(0, colon);
    final String value = line.substring(colon + 1).trim();
    if (nested) {
      cursor[key] = _readScalar(value);
    } else if (value.isEmpty) {
      cursor = <String, Object?>{};
      root[key] = cursor;
    } else {
      root[key] = _readScalar(value);
    }
  }
  return root;
}

Object? _readScalar(String value) {
  if (value.startsWith('[') && value.endsWith(']')) {
    final String inner = value.substring(1, value.length - 1).trim();
    return <Object?>[
      if (inner.isNotEmpty)
        for (final String item in inner.split(',')) _readScalar(item.trim()),
    ];
  }
  return int.tryParse(value) ?? value;
}

JsonObject _mapDefines(Map<String, String> defines, String prefix) {
  final Result<JsonObject> mapped = environmentToNestedMap(
    defines,
    prefix: prefix,
  );
  expect(mapped.isOk, isTrue, reason: '$defines did not map');
  return mapped.unwrap();
}

void _checkBlankIsUnset(Map<String, Object?> vector) {
  final JsonObject base = _readYaml(vector['baseYaml']! as String);
  final JsonObject defines = _mapDefines(
    _defines(vector),
    vector['prefix']! as String,
  );
  expect(_defines(vector).values, everyElement(isEmpty));
  expect(defines, isEmpty);
  expect(deepMergeAll(<JsonObject>[base, defines])['app'], vector['expected']);
}

void _checkCaseInsensitiveKeys(Map<String, Object?> vector) {
  final JsonObject base = _readYaml(vector['baseYaml']! as String);
  final List<Map<String, Object?>> variants = _objects(vector['variants']);
  expect(variants, hasLength(3));
  for (final Map<String, Object?> variant in variants) {
    final String value = variant['expectedValue']! as String;
    final JsonObject merged = deepMergeAll(<JsonObject>[
      base,
      _mapDefines(<String, String>{
        variant['defineKey']! as String: value,
      }, vector['prefix']! as String),
    ]);
    expect(merged, <String, Object?>{
      'app-settings': <String, Object?>{'displayName': value},
    }, reason: variant['defineKey'] as String?);
  }
}

void _checkLayering(Map<String, Object?> vector) {
  final JsonObject merged = deepMergeAll(<JsonObject>[
    _readYaml(vector['baseYaml']! as String),
    _readYaml(vector['developmentYaml']! as String),
    _readYaml(vector['landscapeYaml']! as String),
    _mapDefines(_defines(vector), vector['prefix']! as String),
  ]);
  expect(merged['app'], vector['expected']);
}

void _checkNoJsonNoComma(Map<String, Object?> vector) {
  final List<Map<String, Object?>> rejected = _objects(vector['rejected']);
  expect(rejected, hasLength(2));
  for (final Map<String, Object?> entry in rejected) {
    final JsonObject defines = _mapDefines(
      _defines(entry),
      entry['prefix']! as String,
    );
    expect(
      _object(defines['app'])['tags'],
      _defines(entry).values.single,
      reason: entry['name'] as String?,
    );
  }
}

const Map<String, void Function(Map<String, Object?>)> _checks =
    <String, void Function(Map<String, Object?>)>{
      'blank_is_unset.json': _checkBlankIsUnset,
      'case_insensitive_key_matching.json': _checkCaseInsensitiveKeys,
      'layering_and_indexed_list.json': _checkLayering,
      'no_json_no_comma.json': _checkNoJsonNoComma,
    };

void main() {
  final Map<String, Object?> manifest = _object(
    jsonDecode(File('$_upstreamPath/manifest.json').readAsStringSync()),
  );
  final Map<String, Object?> vectors = _object(manifest['vectors']);

  test('manifest pins the source release and every checked vector', () {
    // Arrange
    final Map<String, Object?> source = _object(manifest['source']);

    // Act
    final Set<String> pinned = vectors.keys.toSet();

    // Assert
    expect(manifest['authority'], 'c0-fixtures-r2');
    expect(source['commit'], 'fe77520d591f81a9762c40ebf68dc9c0106502d3');
    expect(source['path'], 'contracts/c0/cases/config.json');
    expect(pinned, _checks.keys.toSet());
    for (final Object? vector in vectors.values) {
      expect(_object(vector)['reproduce'], contains('jq -cS'));
      expect(_object(vector)['adaptations'], isNotEmpty);
    }
  });

  group('upstream config vectors', () {
    vectors.forEach((String name, Object? pin) {
      test(name, () {
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
        _checks[name]!(_object(vector));
      });
    });
  });
}
