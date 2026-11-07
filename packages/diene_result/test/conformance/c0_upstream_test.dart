import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
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

List<Object?> _wire(Map<String, Object?> vector) =>
    List<Object?>.from(vector['wire']! as List<Object?>);

Result<Object?> _decodeResult(List<Object?> wire) =>
    Result<Object?>.fromSerial(wire, decodeOk: (Object? value) => value);

Option<Object?> _decodeOption(List<Object?> wire) =>
    Option<Object?>.fromSerial(wire, decodeSome: (Object? value) => value);

void main() {
  final Map<String, Object?> manifest = _object(
    jsonDecode(File('$_upstreamPath/manifest.json').readAsStringSync()),
  );
  final Map<String, Object?> pin = _object(
    _object(manifest['vectors'])['result_wire.json'],
  );
  final Map<String, Object?> cases = _object(
    jsonDecode(File('$_upstreamPath/result_wire.json').readAsStringSync()),
  );
  final Map<String, Object?> results = _object(cases['results']);
  final Map<String, Object?> options = _object(cases['options']);

  test('manifest pins the source release and the vendored vector', () {
    // Arrange
    final Map<String, Object?> source = _object(manifest['source']);

    // Act
    final Set<String> pinned = _object(manifest['vectors']).keys.toSet();

    // Assert
    expect(manifest['authority'], 'c0-fixtures-r2');
    expect(source['commit'], 'fe77520d591f81a9762c40ebf68dc9c0106502d3');
    expect(source['path'], 'contracts/c0/cases/result-wire.json');
    expect(pinned, <String>{'result_wire.json'});
    expect(pin['pointer'], '/cases');
    expect(pin['reproduce'], contains('jq -cS .cases'));
    expect(pin['adaptations'], isNotEmpty);
  });

  test('vendored vector matches its pinned digest', () {
    // Arrange
    final List<int> canonical = utf8.encode(_canonical(cases));

    // Act
    final String digest = sha256.convert(canonical).toString();

    // Assert
    expect(
      digest,
      pin['sha256'],
      reason: 'upstream vector digest drifted from the manifest',
    );
  });

  test('tags and combinator names match the Dart surface', () {
    // Arrange
    final Result<int> ok = const Result<int>.ok(1)
        .map((int value) => value + 1)
        .mapErr((Problem problem) => problem)
        .andThen((int value) => Result<int>.ok(value));

    // Act
    final String tag = ok.match(ok: (int _) => 'ok', err: (Problem _) => 'err');

    // Assert
    expect(tag, 'ok');
    expect(cases['combinators'], <String>['map', 'mapErr', 'andThen', 'match']);
    expect(cases['resultTags'], <String>['ok', 'err']);
    expect(cases['optionTags'], <String>['some', 'none']);
  });

  group('Result vectors', () {
    for (final Map<String, Object?> vector in _objects(results['valid'])) {
      test('valid ${vector['name']} round-trips', () {
        // Arrange
        final List<Object?> wire = _wire(vector);

        // Act
        final ResultSerial encoded = _decodeResult(wire).serial();

        // Assert
        expect(_canonical(encoded), _canonical(wire));
      });
    }
    for (final Map<String, Object?> vector in _objects(results['invalid'])) {
      test('invalid ${vector['name']} is rejected', () {
        // Arrange
        final List<Object?> wire = _wire(vector);

        // Act
        Result<Object?> decode() => _decodeResult(wire);

        // Assert
        expect(decode, throwsFormatException);
      });
    }
  });

  group('Option vectors', () {
    for (final Map<String, Object?> vector in _objects(options['valid'])) {
      test('valid ${vector['name']} round-trips', () {
        // Arrange
        final List<Object?> wire = _wire(vector);

        // Act
        final OptionSerial encoded = _decodeOption(wire).serial();

        // Assert
        expect(_canonical(encoded), _canonical(wire));
      });
    }
    for (final Map<String, Object?> vector in _objects(options['invalid'])) {
      test('invalid ${vector['name']} is rejected', () {
        // Arrange
        final List<Object?> wire = _wire(vector);

        // Act
        Option<Object?> decode() => _decodeOption(wire);

        // Assert
        expect(decode, throwsFormatException);
      });
    }
  });
}
