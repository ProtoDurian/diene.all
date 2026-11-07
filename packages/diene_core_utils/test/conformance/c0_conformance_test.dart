import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:diene_core_utils/c0_temporal.dart';
import 'package:diene_core_utils/diene_core_utils.dart' hide c0TemporalContract;
import 'package:diene_problems/diene_problems.dart';
import 'package:test/test.dart';

const String _fixturesPath = 'test/fixtures/c0';
const WireCodec _codec = WireCodec();

Map<String, Object?> _object(Object? value) =>
    (value! as Map<Object?, Object?>).cast<String, Object?>();

Map<String, Object?> _cases(C0Cases cases) => <String, Object?>{
  'valid': cases.valid,
  'invalid': cases.invalid,
};

void _checkTemporalVectors(Map<String, Object?> wire) {
  const C0TemporalContract contract = c0TemporalContract;
  expect(wire, <String, Object?>{
    'dates': _cases(contract.dates),
    'times': _cases(contract.times),
    'durations': _cases(contract.durations),
    'timezones': _cases(contract.timezones),
    'instants': <Object?>[
      for (final C0InstantVector vector in contract.instants)
        <String, Object?>{
          'input': vector.input,
          'canonicalUtc': vector.canonicalUtc,
        },
    ],
    'invalidInstants': contract.invalidInstants,
  });
}

void _checkWireForms(Map<String, Object?> wire) {
  final Map<String, Object?> encoded = <String, Object?>{
    'date': _codec.encodeDate(
      _codec.decodeDate(wire['date']! as String).unwrap(),
    ),
    'time': _codec.encodeTime(
      _codec.decodeTime(wire['time']! as String).unwrap(),
    ),
    'instant': _codec
        .encodeInstant(
          _codec.decodeInstant(wire['instant']! as String).unwrap(),
        )
        .unwrap(),
    'duration': _codec.encodeDuration(
      _codec.decodeDuration(wire['duration']! as String).unwrap(),
    ),
    'timezone': _codec.encodeTimezone(
      _codec.decodeTimezone(wire['timezone']! as String).unwrap(),
    ),
  };
  expect(encoded, wire);
}

void _checkWireProblem(Map<String, Object?> wire) {
  final Map<String, Object?> data = _object(wire['data']);
  final Problem minted = WireDate.parse(data['value']! as String).unwrapErr();
  expect(minted.toJson(), wire);
  expect(Problem.fromJson(wire).toJson(), wire);
  expect(wire.values, isNot(contains(isNull)));
  expect(wire.containsKey('instance'), isFalse);
}

const Map<String, void Function(Map<String, Object?>)> _checks =
    <String, void Function(Map<String, Object?>)>{
      'temporal_vectors.json': _checkTemporalVectors,
      'wire_forms.json': _checkWireForms,
      'wire_problem.json': _checkWireProblem,
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

  group('local temporal fixtures', () {
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
