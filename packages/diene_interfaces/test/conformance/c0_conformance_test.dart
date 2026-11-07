import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:diene_interfaces/diene_interfaces.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:test/test.dart';

const String _fixturesPath = 'test/fixtures/c0';

const ErrorPortal _walletPortal = ErrorPortal(
  scheme: 'https',
  host: 'docs.raichu.cluster.atomi.cloud',
  landscape: 'raichu',
  platform: 'dart',
  service: 'wallet',
  module: 'app',
);

final Map<String, Problem Function()> _mint = <String, Problem Function()>{
  'logging_invalid_input.json': () => invalidInput<void>(
    port: PortName.logging,
    operation: 'emit',
    field: 'message',
    message: 'Log message must be non-blank',
  ).problem,
  'terminal_timeout.json': () => portProblem(
    port: PortName.terminal,
    code: PortErrorCode.timeout,
    operation: 'run',
    message: 'Command timed out',
    portal: _walletPortal,
    details: <String, Object?>{'executable': 'git'},
  ),
  'vfs_not_found.json': () => portProblem(
    port: PortName.vfs,
    code: PortErrorCode.notFound,
    operation: 'readText',
    message: 'Path not found',
    details: <String, Object?>{'path': '/missing'},
  ),
};

Map<String, Object?> _decode(String source) =>
    (jsonDecode(source)! as Map<Object?, Object?>).cast<String, Object?>();

void main() {
  final Map<String, Object?> manifest = _decode(
    File('$_fixturesPath/manifest.json').readAsStringSync(),
  );
  final Map<String, Object?> fixtures =
      (manifest['fixtures']! as Map<Object?, Object?>).cast<String, Object?>();

  test('manifest is local, sha256 and pins exactly the checked fixtures', () {
    // Arrange
    final Set<String> checked = _mint.keys.toSet();

    // Act
    final Set<String> pinned = fixtures.keys.toSet();

    // Assert
    expect(manifest['authority'], 'local-regression-only');
    expect(manifest['algorithm'], 'sha256');
    expect(pinned, checked);
  });

  group('port Problem wire fixtures', () {
    fixtures.forEach((String name, Object? digest) {
      test(name, () {
        // Arrange
        final List<int> bytes = File('$_fixturesPath/$name').readAsBytesSync();
        final Map<String, Object?> wire = _decode(utf8.decode(bytes));

        // Act
        final String actualDigest = sha256.convert(bytes).toString();
        final Map<String, Object?> minted = _decode(
          jsonEncode(_mint[name]!().toJson()),
        );
        final Map<String, Object?> decoded = _decode(
          jsonEncode(Problem.fromJson(wire).toJson()),
        );

        // Assert
        expect(
          actualDigest,
          digest,
          reason: 'fixture "$name" digest drifted from the manifest',
        );
        expect(minted, wire, reason: '$name no longer matches the code');
        expect(decoded, wire, reason: '$name does not round-trip');
        expect(wire.containsKey('instance'), isFalse);
        expect(wire.values, isNot(contains(null)));
      });
    });
  });
}
