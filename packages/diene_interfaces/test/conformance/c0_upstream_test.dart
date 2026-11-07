import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:diene_interfaces/diene_interfaces.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:test/test.dart';

const String _upstreamPath = 'test/fixtures/c0/upstream';

Map<String, Object?> _object(Object? value) =>
    (value! as Map<Object?, Object?>).cast<String, Object?>();

List<Map<String, Object?>> _objects(Object? value) =>
    (value! as List<Object?>).map(_object).toList();

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

String _snakeId(String id) => id.replaceAll('-', '_');

String _withLastSegment(String uri, String id) =>
    '${uri.substring(0, uri.lastIndexOf('/') + 1)}$id';

List<Problem> _portProblems(ErrorPortal portal) => <Problem>[
  for (final PortName port in PortName.values)
    for (final PortErrorCode code in PortErrorCode.values)
      portProblem(
        port: port,
        code: code,
        operation: 'op',
        message: 'm',
        portal: portal,
      ),
];

void _checkEnvelopes(Map<String, Object?> vector) {
  final List<Map<String, Object?>> valid = _objects(vector['valid']);
  final Set<String> members = <String>{
    for (final Map<String, Object?> envelope in valid) ...envelope.keys,
  };
  expect(valid, isNotEmpty);
  for (final Map<String, Object?> envelope in valid) {
    expect(
      _canonical(Problem.fromJson(envelope).toJson()),
      _canonical(envelope),
    );
  }
  for (final Problem problem in _portProblems(ErrorPortal.localError)) {
    final Map<String, Object?> wire = problem.toJson();
    expect(members.containsAll(wire.keys), isTrue, reason: problem.type);
    expect(wire.containsKey('instance'), isFalse);
  }
}

void _checkTypeUri(Map<String, Object?> vector) {
  final List<Map<String, Object?>> valid = _objects(vector['valid']);
  expect(valid, isNotEmpty);
  for (final Map<String, Object?> sample in valid) {
    final Map<String, Object?> s = _object(sample['segments']);
    final ErrorPortal portal = ErrorPortal(
      scheme: s['scheme']! as String,
      host: s['host']! as String,
      landscape: s['landscape']! as String,
      platform: s['platform']! as String,
      service: s['service']! as String,
      module: s['module']! as String,
    );
    final String version = s['version']! as String;
    final String id = s['id']! as String;
    final String expected = sample['expectedTypeUri']! as String;
    expect(
      problemTypeUri(portal: portal, version: version, id: _snakeId(id)),
      _withLastSegment(expected, _snakeId(id)),
    );
    expect(
      () => problemTypeUri(portal: portal, version: version, id: id),
      throwsA(isA<InvalidProblemTypeSegmentError>()),
    );
    expect(interfacesProblemVersion, version);
    for (final Problem problem in _portProblems(portal)) {
      final String portId = '${problem.data['port']}_${problem.data['code']}';
      expect(problem.type, _withLastSegment(expected, portId));
    }
  }
}

const Map<String, void Function(Map<String, Object?>)> _checks =
    <String, void Function(Map<String, Object?>)>{
      'envelopes.json': _checkEnvelopes,
      'type_uri.json': _checkTypeUri,
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
    expect(source['path'], 'contracts/c0/cases/problem.json');
    expect(pinned, _checks.keys.toSet());
    for (final Object? vector in vectors.values) {
      expect(_object(vector)['reproduce'], contains('jq -cS'));
      expect(_object(vector)['adaptations'], isNotEmpty);
    }
  });

  group('upstream Problem vectors', () {
    vectors.forEach((String name, Object? pin) {
      test(name, () {
        // Arrange
        final Object? vector = jsonDecode(
          File('$_upstreamPath/$name').readAsStringSync(),
        );

        // Act
        final String digest = sha256
            .convert(utf8.encode(_canonical(vector)))
            .toString();

        // Assert
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
