import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:diene_config/c0_config.dart';
import 'package:diene_config/diene_config.dart' hide c0ConfigContract;
import 'package:diene_problems/diene_problems.dart';
import 'package:test/test.dart';

const String _fixturesPath = 'test/fixtures/c0';

Map<String, Object?> _object(Object? value) =>
    (value! as Map<Object?, Object?>).cast<String, Object?>();

void _checkContract(Map<String, Object?> wire) {
  expect(wire, <String, Object?>{
    'releaseId': c0ConfigContract.provenance.releaseId,
    'contractVersion': c0ConfigContract.provenance.contractVersion,
    'releaseDigest': c0ConfigContract.provenance.releaseDigest,
    'sourceCase': c0ConfigContract.provenance.sourceCase,
    'c0Sections': c0ConfigContract.provenance.c0Sections,
    'projectedCases': c0ConfigContract.projectedCases,
  });
}

void _checkLandscapeProblem(Map<String, Object?> wire) {
  final Problem minted = landscape(
    source: const DartDefineLandscapeSource(value: ' '),
  ).unwrapErr();
  expect(minted.toJson(), wire);
  expect(Problem.fromJson(wire).toJson(), wire);
  expect(wire.values, isNot(contains(isNull)));
  expect(_object(wire['data']).values, isNot(contains(isNull)));
  expect(wire.containsKey('instance'), isFalse);
}

const Map<String, void Function(Map<String, Object?>)> _checks =
    <String, void Function(Map<String, Object?>)>{
      'contract.json': _checkContract,
      'landscape_missing_problem.json': _checkLandscapeProblem,
    };

void main() {
  final Map<String, Object?> manifest = _object(
    jsonDecode(File('$_fixturesPath/manifest.json').readAsStringSync()),
  );
  final Map<String, Object?> fixtures = _object(manifest['fixtures']);

  test('manifest declares its local provenance and every fixture', () {
    // Arrange
    final Set<String> expected = _checks.keys.toSet();

    // Act
    final Set<String> pinned = fixtures.keys.toSet();

    // Assert
    expect(manifest['authority'], 'local-regression-only');
    expect(manifest['algorithm'], 'sha256');
    expect(pinned, expected);
  });

  group('local config fixtures', () {
    fixtures.forEach((String name, Object? rawDigest) {
      test(name, () {
        // Arrange
        final List<int> bytes = File('$_fixturesPath/$name').readAsBytesSync();

        // Act
        final String digest = sha256.convert(bytes).toString();
        final Map<String, Object?> wire = _object(
          jsonDecode(utf8.decode(bytes)),
        );

        // Assert
        expect(
          digest,
          rawDigest,
          reason: 'fixture "$name" digest drifted from the manifest',
        );
        _checks[name]!(wire);
      });
    });
  });
}
