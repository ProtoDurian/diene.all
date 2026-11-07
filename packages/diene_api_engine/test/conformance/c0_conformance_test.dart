import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:diene_api_engine/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';

const String _fixturesPath = 'test/fixtures/c0';

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

String _canonical(Object? value) => jsonEncode(_sortKeys(value));

void _checkConfigSchema(Object? fixture) {
  final Map<String, Object?> frozen = (fixture! as Map<Object?, Object?>)
      .cast<String, Object?>();
  expect(_canonical(ApiEngineConfig.schema), _canonical(frozen));
  expect(ApiEngineConfig.schemaEquals(frozen), isTrue);
  expect(
    ApiEngineConfig.schemaEquals(<String, Object?>{...frozen, 'otel': true}),
    isFalse,
  );
}

void _checkClassifier(Object? fixture) {
  for (final Object? raw in fixture! as List<Object?>) {
    final Map<String, Object?> row = (raw! as Map<Object?, Object?>)
        .cast<String, Object?>();
    final TransportOutcome outcome = row['network'] == true
        ? networkFailure()
        : Received(
            HttpResponse(
              status: row['status']! as int,
              body: row['body']! as String,
            ),
          );
    final Result<Object?> result = toResult<Object?>(
      outcome,
      decode: (Map<String, Object?> json) => json,
    );
    final String reason = '${row['name']}';
    switch (row['expect']) {
      case 'ok':
        expect(result.isOk, isTrue, reason: reason);
      case 'problem':
        final Problem problem = expectErr(result, because: reason);
        expect(
          problem,
          Problem.fromJson(
            jsonDecode(row['body']! as String) as Map<String, Object?>,
          ),
          reason: reason,
        );
      case 'unexpected':
        expect(
          expectProblemType(result, BridgeProblems.unexpectedResponse).status,
          row['expectStatus'],
          reason: reason,
        );
      case 'transport':
        expect(
          expectProblemType(result, BridgeProblems.transportFailure).status,
          row['expectStatus'],
          reason: reason,
        );
      default:
        fail('unknown expectation in $reason');
    }
  }
}

const Map<String, void Function(Object?)> _checks =
    <String, void Function(Object?)>{
      'classifier.json': _checkClassifier,
      'config_block_schema.json': _checkConfigSchema,
    };

void main() {
  final Map<String, Object?> manifest =
      (jsonDecode(File('$_fixturesPath/manifest.json').readAsStringSync())!
              as Map<Object?, Object?>)
          .cast<String, Object?>();
  final Map<String, Object?> fixtures =
      (manifest['fixtures']! as Map<Object?, Object?>).cast<String, Object?>();

  test('the manifest is local and pins every checked fixture', () {
    // Arrange
    final Set<String> checked = _checks.keys.toSet();

    // Act
    final Set<String> pinned = fixtures.keys.toSet();
    final Set<String> present = Directory(_fixturesPath)
        .listSync()
        .whereType<File>()
        .map((File f) => f.uri.pathSegments.last)
        .where((String name) => name != 'manifest.json')
        .toSet();

    // Assert
    expect(manifest['authority'], 'local-regression-only');
    expect(manifest['algorithm'], 'sha256');
    expect(pinned, checked);
    expect(present, pinned);
  });

  group('local fixtures', () {
    fixtures.forEach((String name, Object? rawDigest) {
      test(name, () {
        // Arrange
        final List<int> bytes = File('$_fixturesPath/$name').readAsBytesSync();

        // Act
        final String digest = sha256.convert(bytes).toString();

        // Assert
        expect(
          digest,
          rawDigest,
          reason: 'fixture "$name" digest drifted from the manifest',
        );
        _checks[name]!(jsonDecode(utf8.decode(bytes)));
      });
    });
  });
}
